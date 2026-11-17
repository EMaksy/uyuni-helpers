---
name: uyuni-npm-security-bump
description: Assess, prepare, validate, document, and hand off npm security dependency bumps for Uyuni's web project, including Dependabot review, CVE-to-bsc mapping, lockfile and license regeneration, changelog checks, draft PRs, and optional Spacewalk backports. Use for Uyuni web dependency vulnerabilities or existing Dependabot PRs; do not use for unrelated feature dependency updates.
---

# Uyuni npm Security Bump

Prepare the smallest complete security update for an npm dependency in
Uyuni's `web` project. Preserve the user's branches and unrelated changes.
Prepare locally by default; commit, push, edit an existing PR, create a PR, or
start a backport only when the user requests that external step.

Use `../../npm-dependencies/uyuni-npm-dependency.sh` when its `bump` or
`validate` mode fits the dependency. The workflow below remains authoritative
for assessment, transitive-only dependencies, changelogs, review, and PR
metadata. Resolve that helper relative to this skill's directory instead of
assuming that `uyuni-helpers` is checked out at a fixed absolute path.

## Establish scope

1. Read the repository's `AGENTS.md`, any nearer instructions, and the web
   package configuration.
2. Confirm the intended base branch. For new Uyuni security bumps this is
   normally the current `origin/master`, but never assume that for a backport
   or supported product branch.
3. Inspect `git status`, the current branch, remotes, and any local branch with
   the proposed name. Do not discard or carry unrelated work into the bump.
4. Check whether an open PR already handles the dependency or alert. Update
   the existing PR branch instead of creating a duplicate.

## Assess the alert

Collect and cross-check:

- alert number, package, manifest, current version, relationship, and scope;
- every grouped GHSA/CVE, severity, affected range, and first patched version;
- upstream advisory, release notes, and the npm version that contains the fix;
- the matching SUSE CVE page and Bugzilla ID;
- dependency introduction paths and vulnerable-feature reachability; and
- existing Uyuni PR coverage.

Prefer current primary sources: GitHub's Dependabot API and advisory, upstream
release data, npm metadata, and the SUSE CVE page. GitHub alert metadata can
temporarily lack a CVE after one has been assigned, so check current upstream
and SUSE records too.

Never invent a CVE or bsc ID. If a CVE exists but its SUSE Bugzilla is missing,
report that Security must create or provide one before writing the final CVE
changelog entry. If no patched version exists, do not create a version-only
bump; report the blocker and assess exposure or available upstream patches.
If no CVE has been assigned, keep the ordinary version entry, identify the
GHSA in the PR body, and ask Security or the maintainer how the final security
changelog should be represented.

Useful checks include:

```bash
gh api repos/uyuni-project/uyuni/dependabot/alerts/ALERT
gh pr list --repo uyuni-project/uyuni --state open \
  --search 'PACKAGE in:title'
npm --prefix web ls PACKAGE --all
rg 'VULNERABLE_FEATURE_OR_OPTION' web \
  --glob '!node_modules/**' --glob '!html/src/dist/**'
```

Treat the title search only as a first pass. A transitive alert can be fixed by
a parent-package PR whose title never names the vulnerable package. Also check
the alert's linked fix PR, open PR file lists and lockfile diffs, and the
resolved version before concluding that no PR exists.

## Select or create the branch

For an existing PR, inspect it before switching:

```bash
gh pr view PR --repo uyuni-project/uyuni \
  --json title,baseRefName,headRefName,headRepositoryOwner,commits,files
git fetch REMOTE
git switch EXISTING_HEAD_BRANCH
git merge --ff-only REMOTE/EXISTING_HEAD_BRANCH
# If no local branch exists yet:
git switch -c EXISTING_HEAD_BRANCH --track REMOTE/EXISTING_HEAD_BRANCH
```

Choose `REMOTE` by matching the PR head owner to `git remote -v`; do not assume
that every PR head is on `origin`. For an existing local branch, switch and
fast-forward it. Otherwise use only the tracking-branch form. A human commit on a
Dependabot branch prevents Dependabot from automatically rebasing it; mention
that consequence in the handoff.

For a new bump, start a separate branch from the confirmed upstream base:

```bash
git fetch origin master
git switch -c bump-PACKAGE-VERSION origin/master
```

Normalize scoped package names safely in branch and changelog filenames, for
example `@babel/core` becomes `babel-core`.

## Update with npm

Let npm update `package-lock.json`; never hand-edit it. Use the smallest
patched version unless the user or compatibility constraints justify a newer
one.

For a root declaration or root override, the helper can bump and validate:

```bash
bash /path/to/uyuni-helpers/npm-dependencies/uyuni-npm-dependency.sh \
  bump PACKAGE VERSION
```

Otherwise use the equivalent npm operations from the repository root. Update
every existing declaration of the package, including root `overrides`, then
resolve the lockfile with npm. An exact direct bump typically uses:

```bash
npm --prefix web install PACKAGE@VERSION \
  --save-exact --package-lock-only --ignore-scripts
```

For a purely transitive dependency, `npm update` may choose the newest version
allowed by the parent instead of the requested minimum. Verify the result. If
an exact version is required, temporarily constrain it with a root override,
run npm's update, and remove only the temporary override afterward:

```bash
npm --prefix web pkg set 'overrides.PACKAGE=VERSION'
npm --prefix web update PACKAGE \
  --package-lock-only --ignore-scripts --save=false
npm --prefix web pkg delete 'overrides.PACKAGE'
```

Do not delete or replace a pre-existing override. For a package already present
both as a dependency and override, update both consistently before resolving
the lockfile.

After resolution, inspect the full lockfile diff and installed tree. If the
build exposes a real compatibility requirement, add only the minimum companion
bump needed, verify why it is required, and include that version change in the
changelog and PR description.

## Add the changelog

Create a fragment beside `web/spacewalk-web.changes`:

```text
web/spacewalk-web.changes.<author>.<topic>
```

Infer `<author>` from the current user's existing fragments in the target
repository or from their Git identity. Never reuse another person's
identifier; ask if it cannot be established. Include the version change and
one entry per CVE:

```text
- Update PACKAGE from version OLD to NEW
- CVE-XXXX-YYYYY: summary text (bsc#NNNNNNN)
```

Wrap continuation lines with two spaces. Every physical line must be at most
67 characters:

```bash
awk 'length($0) > 67 { print NR ":" length($0) ":" $0; bad=1 }
     END { exit bad }' web/spacewalk-web.changes.<author>.<topic>
```

List every companion dependency version change. Do not omit the ordinary
version line merely because CVE entries are present.

The repository's `.github/workflows/changelogs/changelogs.py` is the
authoritative formatter and tracker validator. It requires
`python-bugzilla~=3.2.0`. Run the local portion from the Uyuni root with:

```bash
python3 .github/workflows/changelogs/changelogs.py \
  --tracker-file .github/workflows/changelogs/trackers.xml \
  --uyuni-dir . \
  web/spacewalk-web.changes.<author>.<topic>
```

Without `BZ_TOKEN`, the script skips live Bugzilla validation. Once a PR
exists, add `--git-repo uyuni-project/uyuni --pr-number PR` to reproduce its
PR/commit tracker checks. After push, always verify the PR's
`changelog_test`; unlike the `awk` guard, CI also checks entry syntax, package
coverage, PR/commit tracker references, and bsc validity.

## Regenerate and validate

Install exactly from the updated lockfile before generating licenses. Run
these commands from the Uyuni repository root; its `package.json` forwards
`build`, `lint:production`, `tsc`, `sort-package`, and `test` to `web/`:

```bash
npm --prefix web ci --ignore-scripts --save=false
npm run build
npm run lint:production
npm run tsc
npm run sort-package -- --check
npm --prefix web ls PACKAGE --all
git diff --check
```

Run `npm run test -- --runInBand` for Babel, Jest, loaders, compilers, or other
toolchain changes, and whenever the dependency can affect runtime behavior.
Build Storybook when the affected introduction path or functionality is
Storybook-specific.

The build regenerates the npm license inventory and hash. Review those files,
including removed or substituted packages and changed copyright text. Never
commit `web/html/src/dist/`.

The current generator can change the RPM expression
`GPL-3.0-only OR MIT` to `GPL-3.0 OR MIT` even when the dependency did not
change licensing. Compare against the base and dependency license set; remove
that unrelated spec churn only when it is demonstrably unrelated. Never hide a
real license change.

## Double-check before handoff

Verify all of the following rather than relying on a successful npm command:

```bash
git diff --stat
git diff -- web/package.json web/package-lock.json
sha1sum web/package-lock.json
cat web/html/src/vendors/npm.licenses.hash.txt
test "$(sha1sum web/package-lock.json | cut -d' ' -f1)" = \
  "$(cat web/html/src/vendors/npm.licenses.hash.txt)"
git diff --check
git status --short --branch
```

- The requested and installed versions match in every declaration, lock entry,
  and `npm ls` path.
- The computed SHA-1 equals `npm.licenses.hash.txt`.
- License changes follow from the new dependency graph.
- Changelog lines are at most 67 characters and every CVE has the correct bsc.
- No generated dist files, credentials, unrelated formatting, or previous
  dependency work entered the branch.
- Build, lint, TypeScript, relevant tests, and package ordering passed; report
  warnings separately from failures.

## Commit and PR handoff

Do not commit or push merely because local preparation was requested. When the
user asks for commands, name every reviewed file explicitly in `git add`.

Use this title format, appending every CVE/bsc pair:

```text
Bump PACKAGE from OLD to NEW in /web (CVE-..., bsc#...)
```

New PRs are drafts unless the user requests otherwise. Their body should have:

- `## What does this PR change?` with the bump, vulnerability, and companion
  dependency rationale;
- `## Changelogs` naming the fragment; and
- `## Validation` listing the commands and concrete test totals.

Choose the push remote from `git remote -v` and the user's established
practice. For an upstream `uyuni-project/uyuni` remote, use the plain branch
name as the PR head. For a personal fork, use a qualified head such as
`GITHUB_USER:BRANCH`, with the current user's GitHub login. Ask if the remote
cannot be established unambiguously. For an existing upstream Dependabot
PR, push its exact head branch to `origin` only if authorized, then update the
existing PR title with `gh pr edit`. Verify the remote PR metadata and checks
after any external write:

```bash
gh pr view PR --repo uyuni-project/uyuni \
  --json title,baseRefName,headRefName,isDraft,commits,files,url
gh pr checks PR --repo uyuni-project/uyuni
```

Confirm that `changelog_test` passed; do not treat other green checks as a
substitute for it.

## Optional product backport

Backport only after the Uyuni PR exists and only when requested. Read and use
the sibling [Uyuni backport skill](../uyuni-backport/SKILL.md); do not recreate
its conflict handling or draft Spacewalk PR workflow here.

## Stop safely

Stop before mutation and ask for direction when the base branch, alert-to-PR
mapping, required patched version, CVE/bsc pairing, remote ownership, or an
unexpected broad dependency rewrite cannot be established unambiguously.
