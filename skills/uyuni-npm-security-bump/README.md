# Uyuni npm security update guide

This guide describes the complete npm security-update workflow for Uyuni's
`web` project: assess a Dependabot alert, avoid duplicate PRs, map CVEs to SUSE
Bugzilla entries, perform the smallest npm-managed bump, regenerate licenses,
write a compliant changelog, validate the frontend, and prepare draft PR or
backport handoff commands.

Follow it manually or provide the companion [`SKILL.md`](SKILL.md) to an AI
assistant such as GitHub Copilot, Gemini, or Claude. The instructions specify
local preparation by default: committing, pushing, creating or editing a PR,
and starting a Spacewalk backport require an explicit request.

## Use it with an AI assistant

For an assistant with local file access, point it at the checked-out guide.
Replace the path and alert or PR numbers below with your own values. For a
chat interface without local access, attach or paste `SKILL.md` and the
relevant project context instead. If the assistant cannot run commands, ask
for commands to run yourself and provide their output for review.

```text
Read and follow the instructions at
/absolute/path/to/uyuni-helpers/skills/uyuni-npm-security-bump/SKILL.md
to prepare Dependabot alert #535 locally. Do not push it.
```

For an existing PR:

```text
Read and follow the instructions at
/absolute/path/to/uyuni-helpers/skills/uyuni-npm-security-bump/SKILL.md
to add the CVE and bsc changelog metadata to Uyuni PR #12697, validate it,
and give me the commit and push commands.
```

For a new draft PR including the external steps:

```text
Read and follow the instructions at
/absolute/path/to/uyuni-helpers/skills/uyuni-npm-security-bump/SKILL.md
to prepare this npm security bump, commit it, push it to my fork, and open a
draft Uyuni PR.
```

## Optional assistant integration

The Markdown instructions can be read directly without installation. Automatic
discovery and shortcuts depend on your assistant; a `SKILL.md` file is not
automatically loaded by every tool.

For GitHub Copilot, Gemini, or Claude, provide the guide using the file or
context features available in your setup. Ask the assistant to read the full
guide and its referenced files before making changes. No particular assistant
or automatic skill registration is required to follow the workflow.

## Required checks

The workflow requires independent checks at each boundary, whether performed
manually or with an assistant:

| Boundary | Checks |
| --- | --- |
| Alert | Package, current version, dependency relationship, affected range, patched version, every grouped advisory |
| Duplication | Existing Uyuni PRs and their exact head branches |
| Security metadata | Current upstream CVE/GHSA plus the SUSE CVE page and Bugzilla ID |
| Exposure | `npm ls` introduction paths and searches for vulnerable options or features |
| Resolution | Every dependency/override declaration, exact lockfile version, companion compatibility bumps |
| Packaging | Generated license inventory, removed/substituted packages, and lockfile SHA-1 |
| Changelog | Version line, every CVE/bsc pair, and a maximum of 67 characters per physical line |
| Validation | Clean npm install, build, ESLint, TypeScript, package ordering, relevant Jest tests, and Storybook when applicable |
| Final diff | No dist output, secrets, unrelated formatting, previous bumps, or unexplained RPM license changes |
| PR | Correct base/head, draft state, title, body, commits, checks, and authorization before writes |

## Manual workflow

These are the steps represented by `SKILL.md`.

### 1. Assess and de-duplicate

```bash
cd ~/Work/SUSE-MANAGER-LINUX/uyuni
git status --short --branch
git remote -v

gh api repos/uyuni-project/uyuni/dependabot/alerts/ALERT
gh pr list --repo uyuni-project/uyuni --state open \
  --search 'PACKAGE in:title'
npm --prefix web ls PACKAGE --all
```

Confirm the fix in the upstream advisory or release and find the matching CVE
and `bsc#` on the SUSE CVE page. If a CVE exists without a SUSE Bugzilla, ask
Security for one. If upstream has no patched release, stop instead of creating
a bump that cannot close the alert. The PR-title search is not sufficient for
transitive dependencies: inspect linked fix PRs, PR files, and lockfile diffs
because the fixing PR may be named after a parent package.

### 2. Select the branch

For a new PR:

```bash
git fetch origin master
git switch -c bump-PACKAGE-VERSION origin/master
```

For an existing Dependabot PR:

```bash
gh pr view PR --repo uyuni-project/uyuni \
  --json title,baseRefName,headRefName,headRepositoryOwner,commits,files
git fetch REMOTE
git switch EXISTING_HEAD_BRANCH
git merge --ff-only REMOTE/EXISTING_HEAD_BRANCH
# If no local branch exists yet:
git switch -c EXISTING_HEAD_BRANCH --track REMOTE/EXISTING_HEAD_BRANCH
```

Match `REMOTE` to the PR head owner. Fast-forward an existing local branch, or
use only the tracking-branch form when it does not exist locally.

### 3. Apply the bump with npm

For a directly declared package or root override, use the helper:

```bash
bash ~/Work/uyuni-helpers/npm-dependencies/uyuni-npm-dependency.sh \
  bump PACKAGE VERSION
```

The helper is documented in
[`npm-dependencies/README.md`](../../npm-dependencies/README.md). For a purely
transitive package, use npm's lockfile update and verify the exact resolved
version. Never hand-edit `package-lock.json`.

Check for multiple declarations, especially root overrides:

```bash
rg -n '"PACKAGE"' web/package.json web/package-lock.json
```

### 4. Add the changelog

Create:

```text
web/spacewalk-web.changes.emaksy.PACKAGE-VERSION
```

Use:

```text
- Update PACKAGE from version OLD to NEW
- CVE-XXXX-YYYYY: concise summary (bsc#NNNNNNN)
```

Multiple vulnerabilities get separate CVE lines. Companion bumps get separate
version lines. Verify the 67-character limit:

```bash
awk 'length($0) > 67 { print NR ":" length($0) ":" $0; bad=1 }
     END { exit bad }' web/spacewalk-web.changes.emaksy.PACKAGE-VERSION
```

This catches the CI failure seen during the first run. The authoritative
validator requires `python-bugzilla~=3.2.0` and can be run from the Uyuni root:

```bash
python3 .github/workflows/changelogs/changelogs.py \
  --tracker-file .github/workflows/changelogs/trackers.xml \
  --uyuni-dir . \
  web/spacewalk-web.changes.emaksy.PACKAGE-VERSION
```

Without `BZ_TOKEN`, it skips live Bugzilla validation. For an existing PR, add
`--git-repo uyuni-project/uyuni --pr-number PR`. After pushing, verify that the
PR's `changelog_test` passes because CI also validates entry syntax, package
coverage, tracker references, and bsc IDs.

### 5. Regenerate and validate

```bash
npm --prefix web ci --ignore-scripts --save=false
npm --prefix web ls PACKAGE --all
npm run build
npm run lint:production
npm run tsc
npm run sort-package -- --check
npm run test -- --runInBand
git diff --check
```

Jest is especially important for Babel and other build-tool changes. Run the
Storybook build when Storybook introduces or exercises the dependency.

### 6. Review generated files

```bash
git diff --stat
git diff -- web/package.json web/package-lock.json
git diff -- web/html/src/vendors/npm.licenses.txt
sha1sum web/package-lock.json
cat web/html/src/vendors/npm.licenses.hash.txt
test "$(sha1sum web/package-lock.json | cut -d' ' -f1)" = \
  "$(cat web/html/src/vendors/npm.licenses.hash.txt)"
git status --short --branch
```

The two hashes must match. Keep genuine license-graph changes. Remove only
proven unrelated generator churn, such as the currently observed change from
`GPL-3.0-only OR MIT` to `GPL-3.0 OR MIT` when the updated dependency did not
change that license. Never commit `web/html/src/dist/`.

### 7. Commit and open a draft PR

Stage only the reviewed files. Typical files are:

```bash
git add \
  web/package.json \
  web/package-lock.json \
  web/html/src/vendors/npm.licenses.hash.txt \
  web/html/src/vendors/npm.licenses.txt \
  web/spacewalk-web.changes.emaksy.PACKAGE-VERSION

git commit -m "Bump PACKAGE from OLD to NEW"
git push -u fork BRANCH
```

Use this title format:

```text
Bump PACKAGE from OLD to NEW in /web (CVE-..., bsc#...)
```

Create new PRs as drafts. The body should explain the security impact, every
companion bump, the changelog, and the exact validations that passed. For an
existing Dependabot PR, push its exact upstream head branch only when
authorized and update that PR rather than opening another one.

After any push or PR edit, verify the remote result:

```bash
gh pr view PR --repo uyuni-project/uyuni \
  --json title,baseRefName,headRefName,isDraft,commits,files,url
gh pr checks PR --repo uyuni-project/uyuni
```

### 8. Optional Spacewalk backport

Once the Uyuni PR exists, use the sibling
[`uyuni-backport` skill](../uyuni-backport/SKILL.md) for requested Manager-5.1
or Manager-5.2 backports. It owns isolated conflict recovery, generated license
hash conflicts, pushing, and draft Spacewalk PR verification.

## Lessons captured from the first runs

- A transitive `npm update` can select a newer version than the minimum fix;
  always inspect the resolved lock entry.
- Direct dependencies can also be pinned in `overrides`; update both.
- A core tool bump can require a companion override bump. Babel core 7.29.6,
  for example, required Babel helpers 7.29.2 for `isInternal`.
- A successful install is not enough: build and Jest can reveal API mismatch.
- License-file changes can be much larger than the direct bump when one
  transitive implementation replaces another.
- Dependabot alerts may receive CVE assignments after the alert was opened;
  re-check current advisory and SUSE metadata.
- Every changelog line, including wrapped CVE summaries, must be no longer than
  67 characters.
