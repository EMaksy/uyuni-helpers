# Uyuni backport helper

`uyuni-backport.sh` backports all commits from the pull request associated with
your current Uyuni branch to `SUSE/spacewalk`. It creates or refreshes a
Spacewalk backport branch, pushes it, and creates or updates the corresponding
pull request. New pull requests are opened as drafts by default.

## Prerequisites

- Bash, Git, `jq`, `sha1sum`, and the GitHub CLI (`gh`)
- Local checkouts of `uyuni-project/uyuni` and `SUSE/spacewalk`
- Permission to push branches to `SUSE/spacewalk`
- An authenticated GitHub CLI:

  ```bash
  gh auth login --hostname github.com
  ```

The Spacewalk checkout's `origin` must point to `SUSE/spacewalk`, not to a
personal fork.

## One-time configuration

Choose one of the following ways to run the helper.

### Option 1: direct Git alias

Point a Git alias directly at the cloned script. The script does not need to be
in `PATH` or marked executable because Bash opens it explicitly:

```bash
git config --global alias.backport \
  '!bash /absolute/path/to/uyuni-helpers/backports/uyuni-backport.sh'
```

This provides the `git backport` command.

### Option 2: install in PATH

Make the script executable and link it into a directory in `PATH`:

```bash
chmod +x /absolute/path/to/uyuni-helpers/backports/uyuni-backport.sh
mkdir -p "$HOME/.local/bin"
ln -s /absolute/path/to/uyuni-helpers/backports/uyuni-backport.sh \
  "$HOME/.local/bin/uyuni-backport"
```

If necessary, add the directory to `PATH` in `~/.bashrc`:

```bash
export PATH="$HOME/.local/bin:$PATH"
```

Then register the shorter Git alias:

```bash
git config --global alias.backport '!uyuni-backport'
```

This allows both `uyuni-backport` and `git backport` to run the helper.

### Option 3: Bash alias

To call the helper directly without modifying `PATH`, add this to `~/.bashrc`:

```bash
alias uyuni-backport='bash /absolute/path/to/uyuni-helpers/backports/uyuni-backport.sh'
```

Reload the shell configuration and invoke the command as `uyuni-backport`:

```bash
source ~/.bashrc
uyuni-backport Manager-5.2
```

This Bash alias does not provide `git backport`; use one of the Git alias
options above if that command name is preferred.

## Local settings

Copy the configuration template and edit it for your machine:

```bash
cd /absolute/path/to/uyuni-helpers/backports
cp .env.example .env
```

```dotenv
SPACEWALK_REPO=/absolute/path/to/spacewalk
UYUNI_BACKPORT_TARGET_BRANCH=Manager-5.2
```

The `.env` file is loaded from the directory containing the script, regardless
of the directory from which the command is run. It is ignored by Git.

If `SPACEWALK_REPO` is empty or not configured, the script expects the Uyuni and
Spacewalk checkouts to be sibling directories:

```text
work/
├── uyuni/
└── spacewalk/
```

You can also configure the values in your shell instead of using `.env`:

```bash
export SPACEWALK_REPO=/absolute/path/to/spacewalk
export UYUNI_BACKPORT_TARGET_BRANCH=Manager-5.2
```

The priority order is command-line argument, shell environment, `.env`, then
the built-in defaults. You can override the Spacewalk path for one invocation
with `--spacewalk /absolute/path/to/spacewalk`.

## Quick usage

Run the command from the clean Uyuni feature branch associated with the PR:

```bash
cd /path/to/uyuni
git switch my-feature-branch

# Backport to Manager-5.2 (the default), push, and open/update a draft PR
git backport

# Backport to another product branch
git backport Manager-5.1

# Open a normal ready-for-review PR instead of a draft
git backport Manager-5.1 --ready

# Backport a merged PR by number; the current branch supplies the readable name
git backport Manager-5.1 --pr 11192 --allow-unapproved

# Build only the local Spacewalk branch; do not push or open a PR
git backport Manager-5.2 --no-push

# Push the branch without opening or updating a PR
git backport Manager-5.2 --no-pr

# Permit a Uyuni PR that is not currently approved
git backport Manager-5.2 --allow-unapproved

# Override the Spacewalk checkout location
git backport Manager-5.2 --spacewalk /path/to/spacewalk

# Show all options
git backport --help
```

## Checks and behavior

The script stops unless:

- the current repository is a clean Uyuni checkout;
- the current branch is not `master`;
- without `--pr`, the current branch has a Uyuni PR and local `HEAD` matches
  that PR's current head;
- with `--pr NUMBER`, every source PR commit is available in the local Uyuni
  checkout (the current branch is used only for the generated backport name);
- the PR is approved, unless `--allow-unapproved` is supplied; and
- the requested Spacewalk target branch exists.

The generated branch is named similarly to:

```text
backport/uyuni-123-my-feature-to-Manager-5.2
```

Generated Spacewalk PR titles include the target version so parallel ports are
easy to distinguish, for example:

```text
5.2 - Fix React and Bootstrap modal error logs
5.1 - Fix React and Bootstrap modal error logs
```

The generated PR body keeps the Uyuni source metadata and includes the standard
`Changelogs` section. `No changelog needed` is unchecked by default so the PR
author must explicitly make that decision. A normal rerun also refreshes this
title and body on an already synchronized Spacewalk PR; `--no-pr` never creates
or updates PR metadata.

New PRs are drafts by default. Supply `--ready` to create a ready-for-review PR.
When `--ready` finds an existing matching draft, it marks that PR ready after
updating its metadata. A normal rerun does not downgrade an existing ready PR
back to draft.

It is safe to rerun the command after the Uyuni PR changes. The generated
Spacewalk branch is rebuilt from the target branch and an existing remote branch
is replaced using `--force-with-lease`.

To avoid trusting PR text alone, the body records the Uyuni source HEAD, the
Spacewalk target HEAD used as the base, and the exact generated Spacewalk
backport HEAD. The synchronization shortcut is used only when all three still
match, including the actual remote backport branch. A missing or stale marker,
a force-pushed backport, or an advanced target branch causes a rebuild. This
also means PRs created by older helper versions are rebuilt once. `--no-push`
always rebuilds the local branch and never updates a PR. `--no-pr` may use a
verified synchronization shortcut, but it never creates or edits a PR.

If a cherry-pick conflicts, the script keeps its temporary worktree instead of
changing the main Spacewalk checkout. One generated-file conflict is handled
automatically: when `web/html/src/vendors/npm.licenses.hash.txt` is the only
unresolved file, the helper regenerates it as the SHA-1 of
`web/package-lock.json`, stages it, and continues the cherry-pick. This also
works when multiple queued commits encounter the same generated conflict.

Every other conflict still stops safely. The terminal output prominently shows
the retained worktree path and prints ready-to-copy commands to open it, for
example:

```bash
cd /tmp/uyuni-backport-XXXXXX/worktree
code /tmp/uyuni-backport-XXXXXX/worktree
```

Resolve the conflicts entirely inside that isolated worktree. The helper prints
the complete recovery sequence: inspect unresolved files, stage the resolutions,
continue every queued cherry-pick, validate the result, create the local
backport branch, push it, and create or update the Spacewalk PR. New-PR recovery
commands include `--draft` unless `--ready` was requested. The instructions also
respect `--no-push` and `--no-pr`.
