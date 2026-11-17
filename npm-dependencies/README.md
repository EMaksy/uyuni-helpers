# Uyuni npm dependency helper

`uyuni-npm-dependency.sh` validates npm dependency updates in the `web`
project of an Uyuni or Spacewalk checkout. It can also perform a basic bump
before running the validation.

The helper stops at the first failed command. It never commits or pushes.

## Prerequisites

- Bash, Git, Node.js, and npm
- The Node.js/npm versions required by the target project's `web/package.json`
- Registry access when using `bump`, or when `npm ci` needs uncached packages

## Installation

The most convenient setup is a Bash alias:

```bash
alias npm-dependency='bash /home/emaksy/Work/SUSE-MANAGER-LINUX/uyuni-helpers/npm-dependencies/uyuni-npm-dependency.sh'
```

Add it to `~/.bashrc`, then reload the shell:

```bash
source ~/.bashrc
```

Alternatively, mark the script executable and link it into a directory in
`PATH`:

```bash
chmod +x /home/emaksy/Work/SUSE-MANAGER-LINUX/uyuni-helpers/npm-dependencies/uyuni-npm-dependency.sh
ln -s /home/emaksy/Work/SUSE-MANAGER-LINUX/uyuni-helpers/npm-dependencies/uyuni-npm-dependency.sh ~/.local/bin/npm-dependency
```

## Usage

Validate a dependency that you already bumped:

```bash
cd /home/emaksy/Work/SUSE-MANAGER-LINUX/uyuni
npm-dependency validate lodash
```

The same command works inside Spacewalk:

```bash
cd /home/emaksy/Work/SUSE-MANAGER-LINUX/spacewalk
npm-dependency validate lodash
```

Bump to the registry's `latest` version and validate:

```bash
npm-dependency bump lodash
```

Bump to a selected version or npm tag and validate:

```bash
npm-dependency bump lodash 4.18.1
npm-dependency bump lodash next
```

Run against a checkout without changing directory:

```bash
npm-dependency --repo /path/to/spacewalk validate lodash
```

Use a different npm project directory:

```bash
npm-dependency --package-dir path/to/npm-project validate lodash
```

## What `bump` changes

The command resolves the requested version with `npm view`, updates existing
root declarations in `dependencies`, `devDependencies`,
`optionalDependencies`, `peerDependencies`, and `overrides`, and refreshes
`package-lock.json`.

Existing version style is retained: `^` remains `^`, `~` remains `~`, and an
exact version remains exact. Complex specifiers such as Git URLs, local paths,
aliases, and nested override objects are intentionally rejected; update those
manually and run `validate`.

## Validation sequence

Both commands run these checks one after another:

1. `npm ci`
2. `npm ls PACKAGE --all`
3. `npm run test`
4. `npm run tsc`
5. `npm run lint:production`
6. `npm run build`
7. `git diff --check`
8. `git status --short`

`npm ci` recreates `node_modules`. Project lifecycle scripts can also update
generated files such as `web/html/src/vendors/npm.licenses.structured.js`.
Always review every reported change before committing.

## Complete security dependency workflow

The following workflow covers an npm security update in Uyuni and its optional
Manager 5.1 backport. Replace the example names and versions with the values
from the Dependabot alert.

### 1. Assess the update

Before changing the lockfile:

1. Read every advisory grouped into the Dependabot alert.
2. Confirm the affected and first patched versions from the upstream advisory.
3. Use the smallest version that fixes all grouped advisories unless there is a
   specific reason to take a newer release.
4. Check how the package enters the dependency tree:

   ```bash
   cd ~/Work/SUSE-MANAGER-LINUX/uyuni/web
   npm ls webpack --all
   ```

5. Check whether the vulnerable feature is configured in Uyuni. For example:

   ```bash
   rg 'buildHttp|allowedUris|HttpUriPlugin' . \
     --glob '!node_modules/**' \
     --glob '!html/src/dist/**'
   ```

If upstream has no patched release, verify and document the exposure instead
of creating a version-only bump that cannot fix the alert.

### 2. Create the Uyuni branch

Always branch from the current upstream `master`, not from the preceding
dependency branch:

```bash
cd ~/Work/SUSE-MANAGER-LINUX/uyuni
git status --short --branch
git fetch origin master
git switch -c bump-webpack-5.104.1 origin/master
```

The `origin` remote must point to `uyuni-project/uyuni` when the feature branch
and PR are intended to live in the upstream repository:

```bash
git remote -v
```

### 3. Bump and validate the dependency

Run the dependency helper from the Uyuni checkout:

```bash
cd ~/Work/SUSE-MANAGER-LINUX/uyuni
npm-dependency bump webpack 5.104.1
```

This refreshes the declaration and lockfile, performs a clean installation,
and runs unit tests, TypeScript, production lint, the production build, and
basic Git checks.

If the reported introduction path is Storybook, also build Storybook:

```bash
cd ~/Work/SUSE-MANAGER-LINUX/uyuni/web
npm run build-storybook
```

Use `npm audit` as a package-specific cross-check, not as an instruction to mix
unrelated dependency updates into the same commit. Existing audit findings
should remain separate tasks.

### 4. Review and commit

Review every generated change, including the dependency declarations,
lockfile, npm license files, license hash, and RPM spec:

```bash
cd ~/Work/SUSE-MANAGER-LINUX/uyuni
git diff --stat
git diff -- web/package.json web/package-lock.json
sha1sum web/package-lock.json
cat web/html/src/vendors/npm.licenses.hash.txt
git diff --check
```

The computed SHA-1 and `npm.licenses.hash.txt` must match. Add a changelog
fragment under `web`, for example:

```text
web/spacewalk-web.changes.emaksy.webpack-5-104-1
```

```text
- Update webpack from version 5.99.7 to 5.104.1
```

Commit only the reviewed files. Keep the message concise and do not add
automated attribution or generated trailers:

```bash
git add web/package.json \
  web/package-lock.json \
  web/html/src/vendors/npm.licenses.txt \
  web/html/src/vendors/npm.licenses.hash.txt \
  web/spacewalk-web.spec \
  web/spacewalk-web.changes.emaksy.webpack-5-104-1
git commit -m "bump webpack to 5.104.1"
```

### 5. Push and open the Uyuni draft PR

Run this from the Uyuni repository. Pushing to `origin` makes the PR branch an
upstream Uyuni branch rather than a branch in the personal fork:

```bash
cd ~/Work/SUSE-MANAGER-LINUX/uyuni
git push --set-upstream origin bump-webpack-5.104.1 && \
gh pr create \
  --repo uyuni-project/uyuni \
  --draft \
  --base master \
  --head bump-webpack-5.104.1 \
  --title "Bump webpack from 5.99.7 to 5.104.1 in /web" \
  --body $'Bumps [webpack](https://github.com/webpack/webpack) from 5.99.7 to 5.104.1.\n\n- [Release notes](https://github.com/webpack/webpack/releases)\n- [Changelog](https://github.com/webpack/webpack/blob/main/CHANGELOG.md)\n- [Commits](https://github.com/webpack/webpack/compare/v5.99.7...v5.104.1)'
```

### 6. Prepare the Manager 5.1 backport locally

The Uyuni PR must exist before the backport helper can read its commits and
metadata. From the clean Uyuni source branch, create only the local Spacewalk
branch first:

```bash
cd ~/Work/SUSE-MANAGER-LINUX/uyuni
git backport Manager-5.1 --no-push
```

For an unapproved PR or when selecting the PR explicitly:

```bash
git backport Manager-5.1 --pr 12718 --allow-unapproved --no-push
```

The helper automatically resolves the known generated-file conflict when
`web/html/src/vendors/npm.licenses.hash.txt` is the only unresolved file. It
recomputes the hash from the backported `web/package-lock.json` before
continuing the cherry-pick. Any other conflict stops for manual review.

### 7. Validate the Manager 5.1 backport

The backport branch belongs to the Spacewalk checkout, so switch directories
before testing or pushing:

```bash
cd ~/Work/SUSE-MANAGER-LINUX/spacewalk
git switch backport/uyuni-12718-bump-webpack-5.104.1-to-Manager-5.1

cd web
npm ci
npm run all
npm run build-storybook
```

Verify that testing did not modify tracked files and that the generated hash
still matches:

```bash
cd ~/Work/SUSE-MANAGER-LINUX/spacewalk
git status --short --branch
sha1sum web/package-lock.json
cat web/html/src/vendors/npm.licenses.hash.txt
git diff --check origin/Manager-5.1..HEAD
```

Pre-existing untracked build directories in the Spacewalk checkout should be
left untouched.

### 8. Push and open the Spacewalk draft PR

Run the push and PR creation from the Spacewalk repository, not from Uyuni:

```bash
cd ~/Work/SUSE-MANAGER-LINUX/spacewalk
git push --set-upstream origin \
  backport/uyuni-12718-bump-webpack-5.104.1-to-Manager-5.1

gh pr create \
  --repo SUSE/spacewalk \
  --draft \
  --base Manager-5.1 \
  --head backport/uyuni-12718-bump-webpack-5.104.1-to-Manager-5.1 \
  --title "5.1 - Bump webpack from 5.99.7 to 5.104.1 in /web" \
  --body-file /path/to/reviewed-backport-pr-body.md
```

The PR body should contain the source PR link and these exact values collected
immediately before pushing:

```bash
git -C ~/Work/SUSE-MANAGER-LINUX/uyuni rev-parse bump-webpack-5.104.1
git rev-parse origin/Manager-5.1
git rev-parse HEAD
```

Record them as `Uyuni source HEAD`, `Spacewalk target HEAD`, and `Spacewalk
backport HEAD`, respectively, together with `Target product branch:
Manager-5.1` and the standard changelog section.
