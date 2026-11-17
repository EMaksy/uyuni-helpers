# uyuni-helpers

Tools and instructions for maintaining Uyuni and carrying fixes into SUSE
Manager product branches. This repository is a handover reference for colleagues
who need to repeat these tasks:

- Update an npm dependency in the Uyuni or Spacewalk frontend.
- Check that the update still installs, passes tests, and builds.
- Prepare a security update with advisory references, licenses, and a changelog.
- Backport an Uyuni pull request to a Spacewalk product branch.
- Follow the same workflows manually or with an AI assistant.

The repository contains two Bash scripts and two written workflow guides,
stored as `SKILL.md` files. The scripts run against separate Uyuni and
Spacewalk checkouts on your machine. The guides explain the steps, checks, and
expected results in plain text. You can follow them yourself or give them to
an AI assistant such as GitHub Copilot, Gemini, or Claude. The scripts also
work directly from a terminal.

## Contents

- [Terms used in this guide](#terms-used-in-this-guide)
- [Choose the right tool](#choose-the-right-tool)
- [Set up your machine](#set-up-your-machine)
- [Update or validate an npm dependency](#update-or-validate-an-npm-dependency)
- [Backport an Uyuni pull request](#backport-an-uyuni-pull-request)
- [Use the guides with an AI assistant](#use-the-guides-with-an-ai-assistant)
- [Complete a security update](#complete-a-security-update)
- [Troubleshooting](#troubleshooting)
- [Repository layout and maintenance](#repository-layout-and-maintenance)

## Terms used in this guide

| Term | Meaning here |
| --- | --- |
| Uyuni | The upstream project, in `uyuni-project/uyuni` on GitHub. |
| Spacewalk | The `SUSE/spacewalk` repository used for the product backports in this workflow. Access is required. |
| Backport | Apply an upstream fix to an older product branch. |
| PR | A GitHub pull request: a proposed change for review. |
| Draft PR | A PR that is still being prepared before review. |
| npm dependency | A JavaScript package used by the frontend or its development tools. |
| Lockfile | `package-lock.json`, which records the resolved dependency versions. |
| CVE / GHSA | Identifiers for published security vulnerabilities or GitHub security advisories. |
| bsc | A SUSE Bugzilla reference, written as `bsc#1234567` in changelogs. |
| Worktree | An additional working directory for a Git repository. The backport helper uses one to isolate its work. |

`Manager-5.1` and `Manager-5.2` are example target branches used in these
workflows. Choose the branch required for your task and confirm that it exists;
these examples are not a product support schedule.

## Choose the right tool

| You want to… | Use | What it changes |
| --- | --- | --- |
| Update a directly declared npm package or root override | `uyuni-npm-dependency.sh bump` | Updates package declarations and the lockfile, then runs validation. Installation and build steps can update generated files. Never commits or pushes. |
| Validate a package update you already made | `uyuni-npm-dependency.sh validate` | Reinstalls dependencies and runs checks. Generated files can change. Never commits or pushes. |
| Backport an Uyuni PR | `uyuni-backport.sh` | Creates or rebuilds a local Spacewalk branch. **By default, also pushes it and creates or updates a PR.** |
| Prepare an npm security fix, manually or with an AI assistant | `uyuni-npm-security-bump` guide | Covers advisory checks, the update, changelog, licenses, and validation. Specifies local preparation unless further steps are requested. |
| Follow a backport workflow, manually or with an AI assistant | `uyuni-backport` guide | Covers use of the backport script, conflict resolution, and verification of the resulting PR. |

The npm script does not assess security advisories or write changelogs. Those
steps are covered by the security update guide and the
[full dependency workflow](npm-dependencies/README.md#complete-security-dependency-workflow).
The backport script does not run the product's test suite; validate the result
before handing it over for review.

## Set up your machine

### Required tools and access

| Task | Requirements |
| --- | --- |
| Run either script | Bash and Git. |
| Update or validate npm packages | Node.js and npm versions matching the target checkout's `web/package.json`; npm registry access for downloads. |
| Run the backport helper, including `--no-push` | GitHub CLI (`gh`), `jq`, `sha1sum`, GitHub authentication, and access to both source and target repositories. Publishing also requires permission to push to `SUSE/spacewalk`. |
| Assess Dependabot alerts | GitHub access to the repository's security alerts. Public repository access alone may not provide this. |
| Validate security changelogs | The target repository's changelog validator and its dependencies. See the [security workflow](skills/uyuni-npm-security-bump/README.md). |
| Use a guide with an AI assistant | Provide the guide and relevant project context. To execute the workflow, the assistant needs terminal, file, and repository access; otherwise, run the commands yourself. |

Use your own credentials. Authenticate the GitHub CLI when needed:

```bash
gh auth login --hostname github.com
gh auth status --hostname github.com
```

### Local directory layout

Clone this repository using its GitHub clone URL. The examples below assume
this layout; replace `$HOME/Work` with your own location if needed:

```text
~/Work/
├── uyuni-helpers/    # This repository
├── uyuni/            # Checkout of uyuni-project/uyuni
└── spacewalk/        # Checkout of SUSE/spacewalk, if backporting
```

You only need the target checkout for npm work. You need both Uyuni and Spacewalk
for backports. The helper scripts are invoked with Bash, so no executable bit
or installation into `PATH` is required.

For backports, the Spacewalk checkout's `origin` must point to
`SUSE/spacewalk`, rather than a personal fork. Check it with:

```bash
git -C "$HOME/Work/spacewalk" remote -v
```

### Optional backport configuration

The backport helper finds Spacewalk automatically when it is a sibling of the
Uyuni checkout. Its default target is `Manager-5.2`.

To change those defaults, copy the template:

```bash
cd "$HOME/Work/uyuni-helpers/backports"
cp .env.example .env
```

Edit `.env` for your machine:

```dotenv
SPACEWALK_REPO=/absolute/path/to/spacewalk
UYUNI_BACKPORT_TARGET_BRANCH=Manager-5.2
```

Command-line options take priority over shell environment values, which take
priority over `.env`, followed by the built-in defaults. The `.env` file is
loaded from beside the script and is ignored by Git. It is sourced as Bash
configuration; keep it local and use configuration you trust.

### Optional shorter commands

The examples in this guide use full script paths. For convenience, you can
also register a Git alias:

```bash
git config --global alias.backport \
  '!bash "$HOME/Work/uyuni-helpers/backports/uyuni-backport.sh"'
```

You can then run `git backport Manager-5.2` from Uyuni. This command publishes
by default; add `--no-push` to prepare only the local branch.

For npm work, add this alias to `~/.bashrc` and reload your shell:

```bash
alias npm-dependency='bash "$HOME/Work/uyuni-helpers/npm-dependencies/uyuni-npm-dependency.sh"'
```

You can then run `npm-dependency validate PACKAGE` from the target checkout.

## Update or validate an npm dependency

Use this helper for the `web` npm project in Uyuni or Spacewalk. Start on a
separate branch and inspect existing changes before running it.

### Validate an update already on your branch

Replace `PACKAGE` with the dependency name, for example `lodash`:

```bash
cd "$HOME/Work/uyuni"
git status --short --branch
bash "$HOME/Work/uyuni-helpers/npm-dependencies/uyuni-npm-dependency.sh" \
  validate PACKAGE
```

### Update to a chosen version and validate

Replace `PACKAGE` and `VERSION` with the package and the version you have
selected. For a security fix, first confirm that the version fixes every
advisory in scope.

```bash
cd "$HOME/Work/uyuni"
bash "$HOME/Work/uyuni-helpers/npm-dependencies/uyuni-npm-dependency.sh" \
  bump PACKAGE VERSION
```

If you omit `VERSION`, the helper uses the npm registry's `latest` tag. For a
security update, the smallest version fixing all relevant advisories is
usually the intended choice, so pass that version explicitly.

The helper updates existing declarations in dependencies, development,
optional, and peer dependencies, plus root overrides. It preserves ordinary
`^`, `~`, and exact version styles and lets npm refresh the lockfile.

Both `bump` and `validate` run these steps in order and stop at the first
failure:

1. `npm ci` — install from the lockfile, recreating `node_modules`.
2. `npm ls PACKAGE --all` — show the installed dependency tree.
3. `npm run test` — run unit tests.
4. `npm run tsc` — check TypeScript.
5. `npm run lint:production` — run production lint checks.
6. `npm run build` — build the frontend.
7. `git diff --check` — check the diff for whitespace errors.
8. `git status --short` — show changed files.

After success, review the package declarations, lockfile, generated license
files, and any other reported changes. The helper leaves the changes uncommitted.
If a step fails, earlier file changes remain available for inspection.

Both modes require a direct declaration or root override for the package.
Packages used only through another dependency need a separate npm-managed
update; the [security update guide](skills/uyuni-npm-security-bump/SKILL.md) covers
that case. Complex declarations such as Git URLs, local paths, aliases, and
nested override objects need manual handling before validation.

Use `--repo /path/to/checkout` to select another checkout, or
`--package-dir path/to/npm-project` to select a different npm project. That
project must provide the npm scripts listed above.

See the [npm dependency guide](npm-dependencies/README.md) for full examples.

## Backport an Uyuni pull request

Use this helper when an Uyuni fix also needs to be applied to a Spacewalk
product branch. It reads the source PR's commits and metadata from GitHub.

### Prepare the source branch

Run from a clean Uyuni feature branch associated with a PR. The branch must
not be `master`, and its local `HEAD` must match the PR's current head. The PR
must be approved unless you explicitly use `--allow-unapproved`.

```bash
cd "$HOME/Work/uyuni"
git switch YOUR_SOURCE_BRANCH
git status --short --branch
```

### Create the backport locally first

This creates or rebuilds the local Spacewalk backport branch without pushing
or changing a PR. It still fetches repository data and reads GitHub metadata.

```bash
bash "$HOME/Work/uyuni-helpers/backports/uyuni-backport.sh" \
  Manager-5.2 --no-push
```

The helper prints the generated branch name, in this form:

```text
backport/uyuni-123-your-source-branch-to-Manager-5.2
```

Switch to the printed branch in the Spacewalk checkout, review the changes,
and run checks appropriate to the fix. For npm updates, use the dependency
helper there too. Product branches can have different dependencies or build
requirements, so a successful upstream check does not validate the backport.

### Publish the backport

Before rerunning the helper, switch the Spacewalk checkout away from the
generated backport branch; the helper refuses to rebuild a branch that is
checked out in any worktree. Return to the original Uyuni source branch and
run:

```bash
cd "$HOME/Work/spacewalk"
git switch Manager-5.2

cd "$HOME/Work/uyuni"
bash "$HOME/Work/uyuni-helpers/backports/uyuni-backport.sh" Manager-5.2
```

This rebuilds as needed, pushes the generated branch to Spacewalk, and creates
or updates its PR. New PRs are drafts by default. If the source or target
changed after local validation, review and validate the rebuilt result again.

### Available options

| Option | Effect |
| --- | --- |
| `Manager-5.1` or another target argument | Select the product branch. Without an argument, use the configured target or `Manager-5.2`. |
| `--no-push` | Create or rebuild only the local branch. No push or PR update. |
| `--no-pr` | Push the branch, but do not create or update a PR. |
| `--ready` | Create a ready-for-review PR, or mark a matching existing draft ready. Cannot be combined with `--no-push` or `--no-pr`. |
| `--pr NUMBER` | Select a source PR explicitly, including a merged PR. Its commits must be available locally; the current branch supplies the readable part of the generated branch name. |
| `--allow-unapproved` | Permit a source PR whose current review decision is not approved. |
| `--spacewalk PATH` | Select the local Spacewalk checkout. |
| `--help` | Show usage. |

Rerunning the helper synchronizes the generated branch with the source PR and
target branch. It can replace an existing remote backport branch using
`--force-with-lease`, which checks that the remote branch has not changed
unexpectedly. Keep original fixes in the Uyuni source branch; a rebuild
replaces the generated backport branch's local history. A rerun also refreshes
the PR title and body unless `--no-push` or `--no-pr` is selected.

The PR body records the source, target, and backport commit IDs. The helper
checks these against the actual remote branch before treating a backport as
already synchronized. Review the PR's changelog section before handover; the
helper leaves the `No changelog needed` checkbox unchecked.

### Resolve a cherry-pick conflict

The helper applies commits in an isolated temporary Spacewalk worktree. If a
conflict needs manual resolution, it retains that directory and prints its
path and the commands needed to continue.

1. Open the printed worktree directory.
2. Inspect the conflicting files and resolve them for the target branch.
3. Stage the resolved files and continue the cherry-pick.
4. Repeat if later commits conflict, then review and validate the result.
5. Follow the printed commands to finish the branch and any requested push or PR.

Keep conflict resolution in that worktree. The one automatic conflict repair
is `web/html/src/vendors/npm.licenses.hash.txt` when it is the only unresolved
file: the helper regenerates it from the backported lockfile. Other conflicts
require review. Source PR merge commits also require manual handling.

See the [backport guide](backports/README.md) for configuration, synchronization
details, and recovery examples.

## Use the guides with an AI assistant

The files under `skills/` describe the workflows in Markdown. A "skill" here
means a reusable set of instructions: what to inspect, which commands to run,
what to verify, and when to ask for more information. You can read these files
as checklists or provide them to your preferred AI assistant.

| Guide | Purpose |
| --- | --- |
| [`uyuni-npm-security-bump`](skills/uyuni-npm-security-bump/SKILL.md) | Assess a Dependabot alert or existing PR, check for duplicate fixes, map CVEs to SUSE Bugzilla entries, prepare the update, regenerate licenses, write a changelog, and validate. |
| [`uyuni-backport`](skills/uyuni-backport/SKILL.md) | Run the backport helper, resolve conflicts in its isolated worktree, and verify the Spacewalk PR. |

### Provide the instructions and project context

For an assistant with access to your local files, point it to the relevant
`SKILL.md`. Ask it to read any referenced files too. For a chat interface
without local file access, attach or paste the guide and the relevant project
files or command output. A local path alone will not give that assistant
access to your machine.

Use a request like this, replacing the path and alert number:

```text
Read and follow /absolute/path/to/uyuni-helpers/skills/uyuni-npm-security-bump/SKILL.md
to prepare Uyuni Dependabot alert #ALERT locally.
Validate the result and give me the review and commit commands. Do not push.
If you cannot access files or run commands, tell me what you need and give me
the commands to run. Only report checks as passed when their results are available.
```

For a backport:

```text
Read and follow /absolute/path/to/uyuni-helpers/skills/uyuni-backport/SKILL.md
to backport Uyuni PR #PR_NUMBER to Manager-5.2 and open a draft Spacewalk PR.
If you cannot execute the workflow, give me the commands and review steps.
```

State which checkouts and branches to use, and whether you want local
preparation, a commit, a push, or a PR. The security update guide specifies
local preparation by default; further steps must be requested. Review the
assistant's commands and results as you would a colleague's work.

### Assistant integration is optional

No assistant-specific installation is needed to read and follow these guides.
Automatic skill discovery, registration directories, and invocation syntax
depend on the tool you use. The presence of a `SKILL.md` file does not mean
every assistant will load it automatically.

See the [security update guide](skills/uyuni-npm-security-bump/README.md) for
more examples and required checks.
The underlying scripts and workflow steps are the same whichever assistant
you use.

## Complete a security update

Use this sequence as a handover checklist, whether working manually or with an
AI assistant:

1. **Assess the alert.** Read every grouped advisory, confirm affected versions
   and the smallest complete fix, and check how the dependency is used.
2. **Check existing work.** Look for PRs that already fix it, including changes
   to parent packages that bring in the vulnerable dependency.
3. **Choose the branch.** Update the existing PR branch, or create a fresh branch
   from the intended upstream base. Keep unrelated changes separate.
4. **Apply the update.** Use npm to update declarations and the lockfile. Check
   all declarations and overrides; do not hand-edit the lockfile.
5. **Document it.** Add the version change, each CVE, and the verified `bsc`
   reference to a changelog fragment. Use your own author identifier in the
   filename. Keep each physical line within 67 characters and run the target
   repository's changelog validator.
6. **Validate and review.** Run frontend checks, relevant tests, and Storybook
   when applicable. Review generated licenses and confirm the license hash
   matches the lockfile. Leave generated distribution output out of the commit.
7. **Prepare the PR.** Review and commit the intended files, push to the correct
   repository, open or update the PR, and verify its metadata and CI results.
   New PRs in these workflows are drafts by default.
8. **Backport if required.** Once the Uyuni PR exists, prepare the product
   backport, validate it separately, and publish its Spacewalk PR.

If no patched version exists, report the exposure and available options rather
than making a version change that cannot fix the alert. If a required CVE or
Bugzilla mapping is unclear, obtain it before finalizing the security changelog.

For a colleague picking up the work, record the alert/advisory links, old and
new versions, branch and PR links, target product branch, checks that passed or
failed, and anything still pending. For a conflict, also record the retained
worktree path.

## Troubleshooting

| Problem | What to check or do |
| --- | --- |
| The backport helper rejects local changes | Inspect `git status` in Uyuni and commit or set aside your own work before retrying. |
| No source PR is found, or local `HEAD` differs | Check the Uyuni branch and PR. Fetch or push the intended source commits as appropriate, or select the PR explicitly with `--pr`. |
| The source PR is unapproved | Wait for approval, or use `--allow-unapproved` when the task explicitly calls for proceeding before approval. |
| Spacewalk is not found or its remote is rejected | Check `--spacewalk`, `.env`, and `git remote -v`. Spacewalk `origin` must point to `SUSE/spacewalk`. |
| The generated backport branch is checked out | Switch the relevant Spacewalk worktree to another branch before rebuilding. |
| A cherry-pick stops | Continue in the retained temporary worktree using the printed recovery steps. |
| npm says the package is not directly declared | Inspect `npm ls PACKAGE --all`. A transitive dependency needs the separate workflow described in the security update guide. |
| An npm validation step fails | Read the first failing command's output, check the target Node.js/npm requirements, fix the cause, and rerun validation. Earlier changes are retained. |
| Tests or builds change tracked files | Inspect the full diff, especially licenses, the lockfile hash, and packaging files, before committing. |
| GitHub access or push fails | Check `gh auth status`, repository access, remotes, and push permissions. Public access to this helpers repo does not grant product repository access. |

Both scripts provide usage without running their workflows:

```bash
bash "$HOME/Work/uyuni-helpers/npm-dependencies/uyuni-npm-dependency.sh" --help
bash "$HOME/Work/uyuni-helpers/backports/uyuni-backport.sh" --help
```

## Repository layout and maintenance

```text
uyuni-helpers/
├── README.md                         # Start here: setup and handover guide
├── backports/
│   ├── README.md                     # Detailed backport guide
│   ├── .env.example                  # Local configuration template
│   └── uyuni-backport.sh              # Backport automation
├── npm-dependencies/
│   ├── README.md                     # Dependency and security workflow guide
│   └── uyuni-npm-dependency.sh        # Update and validation automation
└── skills/
    ├── uyuni-backport/                # Backport workflow instructions
    └── uyuni-npm-security-bump/       # Security update workflow instructions
```

Some detailed guides include paths, package versions, PR numbers, and author
names from earlier work. Treat those as examples and substitute your own values.

When maintaining this repository, keep the script's `--help`, its detailed
README, this guide, and the corresponding `SKILL.md` consistent. If target branches,
frontend npm scripts, or changelog rules change, check the target project's
configuration and update the affected instructions. Keep credentials and local
machine configuration out of commits.
