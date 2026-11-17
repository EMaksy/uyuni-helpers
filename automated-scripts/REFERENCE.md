# Script reference

This reference describes the options and the behavior of both helper scripts.
For the workflow, see the [scripts guide](README.md). For the installation, see
[Installing the scripts](README.md#installing-the-scripts).

- [Script reference](#script-reference)
  - [npm dependency script](#npm-dependency-script)
    - [Usage](#usage)
    - [What bump changes](#what-bump-changes)
    - [Validation steps](#validation-steps)
    - [Limitations](#limitations)
  - [Backport script](#backport-script)
    - [Usage](#usage-1)
    - [Configuration](#configuration)
    - [Checks before any change](#checks-before-any-change)
    - [Generated branch and PR](#generated-branch-and-pr)
    - [Reruns](#reruns)
    - [Resolving a cherry-pick conflict](#resolving-a-cherry-pick-conflict)
    - [Limitations](#limitations-1)

## npm dependency script

`uyuni-npm-dependency.sh` bumps an npm package in the `web` project of an Uyuni
or Spacewalk clone and validates the result. It stops at the first failure and
never commits or pushes.

### Usage

Run the script from anywhere inside the clone. Put options before the command:

```bash
npm-dependency [OPTIONS] bump PACKAGE VERSION
```

```bash
npm-dependency [OPTIONS] validate PACKAGE
```

| Command or option | Effect |
| --- | --- |
| `bump PACKAGE VERSION` | Update `PACKAGE` to `VERSION`, then validate. `VERSION` can be a version or an npm tag. Without `VERSION`, the script uses the `latest` tag. |
| `validate PACKAGE` | Validate the version that is declared now, for example on a Dependabot or backport branch. |
| `--repo PATH` | Use this clone instead of the current one. |
| `--package-dir PATH` | Use this npm project, relative to the clone. The default is `web`. The project must provide the npm scripts listed in [Validation steps](#validation-steps). |
| `-h`, `--help` | Show the usage. |

### What bump changes

The `bump` command performs these steps:

1. It resolves the requested version with `npm view`.
2. It updates every declaration of the package in `dependencies`,
   `devDependencies`, `optionalDependencies`, `peerDependencies`, and the root
   `overrides`. It keeps a leading `^` or `~`. Any other specifier that starts
   with a digit or `v`, such as `1.x`, becomes the exact new version.
3. It refreshes `package-lock.json` with
   `npm install --package-lock-only --ignore-scripts`.

Then it runs the validation steps.

### Validation steps

Both commands run these steps in order:

| Step | Command |
| --- | --- |
| 1. Clean install from the lockfile | `npm ci` |
| 2. Show the package in the dependency tree | `npm ls PACKAGE --all` |
| 3. Unit tests | `npm run test` |
| 4. TypeScript check | `npm run tsc` |
| 5. Production lint | `npm run lint:production` |
| 6. Key order in `package.json` | `npm run sort-package -- --check` |
| 7. Production build | `npm run build` |
| 8. Whitespace errors | `git diff --check` |
| 9. Changed files | `git status --short` |

Steps 1–7 run in the npm project, steps 8–9 in the root of the clone. The build
regenerates the license files when the lockfile changed. If a step fails, the
changes made so far stay in place.

### Limitations

The npm script has these limitations:

- It works only for packages that `package.json` declares directly or in the
  root `overrides`, for both `bump` and `validate`.
- It rejects specifiers such as Git URLs, local paths, aliases, and override
  objects. Update those by hand, then run `validate`. Overrides nested under
  another package are neither updated nor reported.
- It does not check advisories, write changelogs, or verify the license hash.
- It does not build Storybook, which the Uyuni CI builds for every frontend
  change. Run `npm --prefix web run build-storybook` separately.

## Backport script

`uyuni-backport.sh` applies the commits of an Uyuni PR to a product branch in
`SUSE/spacewalk`. It works in a temporary Git worktree, pushes the backport
branch, and creates or updates a draft Spacewalk PR.

> [!WARNING]
> **The script pushes by default**
>
> Without `--no-push`, the script pushes to `SUSE/spacewalk` and creates or
> updates a PR. Use `--no-push` to build only the local branch.

### Usage

Run the script from the Uyuni branch of the PR:

```bash
git backport TARGET_BRANCH [OPTIONS]
```

| Argument or option | Effect |
| --- | --- |
| `TARGET_BRANCH` | Spacewalk branch to backport to, for example `Manager-5.1`. The default is the configured target or `Manager-5.2`. |
| `--no-push` | Build or rebuild only the local branch. No push, no PR change. |
| `--no-pr` | Push the branch, but do not create or update a PR. |
| `--ready` | Create the PR ready for review, or mark an existing draft ready. Cannot be combined with `--no-push` or `--no-pr`. |
| `--allow-unapproved` | Accept a source PR that is not approved. |
| `--pr NUMBER` | Select the source PR explicitly, for example a merged PR. Its commits must exist in the local Uyuni clone. The script then skips the check that the local `HEAD` matches the PR. The current branch still names the backport branch and must not be `master`. |
| `--spacewalk PATH` | Use this Spacewalk clone. |
| `-h`, `--help` | Show the usage. |

### Configuration

By default, the script expects Spacewalk next to the Uyuni clone and targets
`Manager-5.2`. To change these defaults, create a `.env` file next to the
script.

1. Change to the script directory:

   ```bash
   cd ~/Work/uyuni-helpers/automated-scripts
   ```

2. Copy the template:

   ```bash
   cp .env.example .env
   ```

3. Edit the values:

   ```bash
   ${EDITOR:-vi} .env
   ```

The file contains these variables:

```dotenv
SPACEWALK_REPO=/absolute/path/to/spacewalk
UYUNI_BACKPORT_TARGET_BRANCH=Manager-5.2
```

You can also export the variables in your shell. Command-line arguments take
precedence over the shell environment, which takes precedence over `.env`.

The script reads `.env` from its own directory and resolves symbolic links.
Git ignores the file. The script sources it as Bash code, so add only trusted
content.

### Checks before any change

The script stops before it changes anything unless all of these are true:

- The current directory is a Git clone without uncommitted changes or untracked
  files.
- The current branch is not `master` and not a detached `HEAD`.
- Without `--pr`, the branch has an Uyuni PR, and the local `HEAD` matches the
  PR head.
- With `--pr`, every commit of that PR exists locally.
- The PR is approved, or `--allow-unapproved` is set.
- The Spacewalk clone exists, its `origin` points to `SUSE/spacewalk`, and the
  target branch exists.
- The GitHub CLI is logged in.
- The backport branch is not checked out in any worktree.

### Generated branch and PR

The backport branch name contains the PR number, the source branch, and the
target:

```text
backport/uyuni-12718-bump-webpack-5.104.1-to-Manager-5.1
```

The PR title starts with the target version:

```text
5.1 - Bump webpack from 5.99.7 to 5.104.1 in /web
```

The PR body contains these items:

- A link to the Uyuni PR.
- The target branch and three commit IDs: the Uyuni source head, the Spacewalk
  base, and the backport head.
- The standard changelog section. *No changelog needed* stays unchecked,
  because the backport contains the changelog fragment.

New PRs are drafts. A normal rerun never turns a ready PR back into a draft.

### Reruns

You can run the script again at any time:

- If the remote branch, the Uyuni head, and the Spacewalk base still match the
  commit IDs in the PR body, and an open PR exists, the script only refreshes
  the PR title and body. With `--ready`, it also marks a draft ready. With
  `--no-pr`, it changes nothing.
- Otherwise, it rebuilds the backport branch on the current target branch, with
  new commit IDs. This also applies to the first publish after `--no-push`. It
  replaces an existing remote branch with `--force-with-lease`.
- With `--no-push`, it always rebuilds the local branch and never changes the
  PR.

A rebuild replaces the history of the backport branch. Make fixes in the Uyuni
PR, not on the backport branch.

### Resolving a cherry-pick conflict

The script cherry-picks in a temporary worktree, so your Spacewalk clone stays
untouched.

When `web/html/src/vendors/npm.licenses.hash.txt` is the only conflicting file,
the script resolves the conflict automatically. It writes the SHA-1 of the
backported lockfile and continues.

For any other conflict, the script stops, keeps the worktree, and prints its
path and the exact commands to finish. Resolve the conflict in that worktree:

1. Change to the printed worktree:

   ```bash
   cd /tmp/uyuni-backport-XXXXXX/worktree
   ```

2. List the conflicting files:

   ```bash
   git diff --name-only --diff-filter=U
   ```

3. Resolve the files as described in
   [Resolving backport conflicts](../manual-steps/README.md#resolving-backport-conflicts).

4. Stage the resolved files:

   ```bash
   git add -A
   ```

5. Continue the cherry-pick. Repeat steps 2–5 if a later commit conflicts:

   ```bash
   git cherry-pick --continue
   ```

6. Run the commands that the script printed. They create the backport branch
   and, unless you used `--no-push`, push it and create or update the PR. With
   `--no-pr`, they only push it.

If Git reports a commit as empty, its change exists on the target already. Run
`git cherry-pick --skip` instead of `--continue`.

After `--no-push`, the printed commands end after creating the local branch.
Running the script again would stop on the same conflict. Push the branch and
create the PR manually, as in step 7 of
[Backporting to the product branches](../manual-steps/README.md#backporting-to-the-product-branches).

Remove the worktree only after the PR exists:

```bash
git -C ~/Work/spacewalk worktree remove /tmp/uyuni-backport-XXXXXX/worktree
```

For schema migrations, do not accept the rename that Git suggests. See
[Schema migration directories](../agentic-skills/uyuni-backport/SKILL.md#schema-migration-directories).

### Limitations

The backport script has these limitations:

- It does not run tests. Validate every backport before you publish it.
- It cannot cherry-pick merge commits from the source PR.
- Changes made only on the backport branch are lost on the next rebuild.
