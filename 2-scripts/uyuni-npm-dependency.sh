#!/usr/bin/env bash

set -Eeuo pipefail

usage() {
    cat <<'EOF'
Usage:
  npm-dependency [options] validate PACKAGE
  npm-dependency [options] bump PACKAGE [VERSION]

Validate an existing npm dependency bump, or bump a dependency and then run
the same validation. Run the command from anywhere inside an Uyuni or
Spacewalk checkout.

Commands:
  validate PACKAGE        Validate the currently declared dependency version
  bump PACKAGE [VERSION]  Bump PACKAGE (default VERSION: latest), then validate

Options:
  --repo PATH             Repository checkout (default: current Git checkout)
  --package-dir PATH      npm project, relative to the repository (default: web)
  -h, --help              Show this help

Validation sequence:
  npm ci
  npm ls PACKAGE --all
  npm run test
  npm run tsc
  npm run lint:production
  npm run sort-package -- --check
  npm run build
  git diff --check
  git status --short

Examples:
  npm-dependency validate lodash
  npm-dependency bump lodash
  npm-dependency bump lodash 4.18.1
  npm-dependency --repo /path/to/spacewalk validate lodash
EOF
}

die() {
    printf 'error: %s\n' "$*" >&2
    exit 1
}

repo=""
package_dir_arg="web"

while (($#)); do
    case "$1" in
        --repo)
            (($# >= 2)) || die "--repo requires a path"
            repo="$2"
            shift 2
            ;;
        --package-dir)
            (($# >= 2)) || die "--package-dir requires a path"
            package_dir_arg="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        --)
            shift
            break
            ;;
        -*)
            die "unknown option: $1"
            ;;
        *)
            break
            ;;
    esac
done

(($# >= 2)) || {
    usage >&2
    exit 2
}

action="$1"
dependency="$2"
shift 2

case "$action" in
    validate)
        (($# == 0)) || die "validate accepts only a package name"
        ;;
    bump)
        (($# <= 1)) || die "bump accepts a package name and optional version"
        requested_version="${1:-latest}"
        ;;
    *)
        die "command must be 'validate' or 'bump'"
        ;;
esac

[[ -n "$dependency" ]] || die "package name cannot be empty"
[[ "$dependency" != -* ]] || die "invalid package name: $dependency"

command -v git >/dev/null || die "git is required"
command -v node >/dev/null || die "Node.js is required"
command -v npm >/dev/null || die "npm is required"

if [[ -z "$repo" ]]; then
    repo="$(git rev-parse --show-toplevel 2>/dev/null)" ||
        die "run inside a Git checkout or use --repo PATH"
fi

repo="$(cd -- "$repo" 2>/dev/null && pwd)" || die "repository not found: $repo"
git -C "$repo" rev-parse --git-dir >/dev/null 2>&1 || die "not a Git checkout: $repo"

if [[ "$package_dir_arg" = /* ]]; then
    package_dir="$package_dir_arg"
else
    package_dir="$repo/$package_dir_arg"
fi
package_dir="$(cd -- "$package_dir" 2>/dev/null && pwd)" ||
    die "npm project directory not found: $package_dir"

[[ -f "$package_dir/package.json" ]] || die "package.json not found in $package_dir"
[[ -f "$package_dir/package-lock.json" ]] || die "package-lock.json not found in $package_dir"

show_declarations() {
    node - "$package_dir/package.json" "$dependency" <<'NODE'
const fs = require("node:fs");

const [packageJsonPath, dependency] = process.argv.slice(2);
const manifest = JSON.parse(fs.readFileSync(packageJsonPath, "utf8"));
const sections = ["dependencies", "devDependencies", "optionalDependencies", "peerDependencies"];
const declarations = [];

for (const section of sections) {
    if (Object.hasOwn(manifest[section] || {}, dependency)) {
        declarations.push([section, manifest[section][dependency]]);
    }
}

if (Object.hasOwn(manifest.overrides || {}, dependency)) {
    declarations.push(["overrides", manifest.overrides[dependency]]);
}

if (declarations.length === 0) {
    console.error(`error: ${dependency} is not declared directly or in root overrides`);
    process.exit(1);
}

for (const [section, specifier] of declarations) {
    const rendered = typeof specifier === "string" ? specifier : JSON.stringify(specifier);
    console.log(`  ${section}: ${rendered}`);
}
NODE
}

resolve_version() {
    local npm_output

    printf 'Resolving %s@%s from the npm registry...\n' "$dependency" "$requested_version" >&2
    npm_output="$(cd -- "$package_dir" && npm view "$dependency@$requested_version" version --json)" ||
        die "could not resolve $dependency@$requested_version"

    node -e '
const input = JSON.parse(process.argv[1]);
const versions = Array.isArray(input) ? input : [input];
const version = versions.at(-1);
if (typeof version !== "string" || version.length === 0) process.exit(1);
process.stdout.write(version);
' "$npm_output" || die "npm returned an invalid version for $dependency@$requested_version"
}

update_declarations() {
    local resolved_version="$1"

    node - "$package_dir/package.json" "$dependency" "$resolved_version" <<'NODE'
const fs = require("node:fs");

const [packageJsonPath, dependency, version] = process.argv.slice(2);
const manifest = JSON.parse(fs.readFileSync(packageJsonPath, "utf8"));
const sections = ["dependencies", "devDependencies", "optionalDependencies", "peerDependencies"];
let updates = 0;

function bumpedSpecifier(current, location) {
    if (typeof current !== "string") {
        throw new Error(`${location} uses a non-string declaration that cannot be bumped automatically`);
    }
    if (current.startsWith("^")) return `^${version}`;
    if (current.startsWith("~")) return `~${version}`;
    if (/^(?:v)?\d/.test(current)) return version;
    throw new Error(`${location} uses unsupported specifier '${current}'; bump it manually, then use validate`);
}

try {
    for (const section of sections) {
        if (Object.hasOwn(manifest[section] || {}, dependency)) {
            manifest[section][dependency] = bumpedSpecifier(
                manifest[section][dependency],
                `${section}.${dependency}`
            );
            updates += 1;
        }
    }

    if (Object.hasOwn(manifest.overrides || {}, dependency)) {
        manifest.overrides[dependency] = bumpedSpecifier(
            manifest.overrides[dependency],
            `overrides.${dependency}`
        );
        updates += 1;
    }
} catch (error) {
    console.error(`error: ${error.message}`);
    process.exit(1);
}

if (updates === 0) {
    console.error(`error: ${dependency} is not declared directly or in root overrides`);
    process.exit(1);
}

fs.writeFileSync(packageJsonPath, `${JSON.stringify(manifest, null, 2)}\n`);
console.log(`Updated ${updates} declaration(s) to npm version ${version}.`);
NODE
}

run_in_package() {
    local label="$1"
    shift

    printf '\n==> %s\n' "$label"
    if ! (cd -- "$package_dir" && "$@"); then
        printf '\nFAILED: %s\n' "$label" >&2
        exit 1
    fi
}

run_in_repo() {
    local label="$1"
    shift

    printf '\n==> %s\n' "$label"
    if ! (cd -- "$repo" && "$@"); then
        printf '\nFAILED: %s\n' "$label" >&2
        exit 1
    fi
}

printf 'Repository:  %s\n' "$repo"
printf 'npm project: %s\n' "$package_dir"
printf 'Dependency:  %s\n' "$dependency"
printf 'Mode:        %s\n' "$action"
printf 'Current declaration(s):\n'
show_declarations

if [[ "$action" == "bump" ]]; then
    resolved_version="$(resolve_version)"
    printf 'Resolved npm version: %s\n' "$resolved_version"
    update_declarations "$resolved_version"
    printf 'New declaration(s):\n'
    show_declarations
    run_in_package "Refresh package-lock.json" npm install --package-lock-only --ignore-scripts
fi

printf '\nValidation uses npm ci, which recreates node_modules.\n'
run_in_package "Clean install and lockfile verification" npm ci
run_in_package "Installed dependency tree" npm ls "$dependency" --all
run_in_package "Unit tests" npm run test
run_in_package "TypeScript check" npm run tsc
run_in_package "Production lint" npm run lint:production
run_in_package "package.json ordering" npm run sort-package -- --check
run_in_package "Production build" npm run build
run_in_repo "Whitespace/error-marker check" git diff --check

printf '\n==> Repository changes\n'
git -C "$repo" status --short

printf '\nSUCCESS: %s passed dependency validation for %s.\n' "$(basename "$repo")" "$dependency"
if [[ "$action" == "bump" ]]; then
    printf 'Review package.json, package-lock.json, generated license files, and all other changes before committing.\n'
fi
