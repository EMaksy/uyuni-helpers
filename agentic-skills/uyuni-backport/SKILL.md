---
name: uyuni-backport
description: Backport a Uyuni pull request or feature branch to a SUSE Manager product branch with the local uyuni-backport helper, including isolated conflict recovery, branch push, and draft Spacewalk pull-request creation or refresh. Use for requests to backport Uyuni work to branches such as Manager-5.2 or Manager-5.1; do not use for ordinary cherry-picks unrelated to the Uyuni-to-Spacewalk workflow.
---

# Uyuni Backport

Use the repository's `automated-scripts/uyuni-backport.sh` helper as the source of truth. Read [the script reference](../../automated-scripts/REFERENCE.md#backport-script) only when setup, options, or behavior beyond this workflow is relevant. The human version of this workflow is [Backporting to the product branches](../../automated-scripts/README.md#backporting-to-the-product-branches).

## Prepare

- Work from the clean Uyuni feature branch associated with the source PR. Confirm the branch, status, and upstream before starting.
- Take the target branch from the user's request. Preserve explicitly requested options and previously established workflow context.
- New Spacewalk PRs are drafts by default. Add `--ready` only when the user explicitly requests a ready-for-review PR.
- If the user names a shell alias, resolve it and preserve its arguments. Non-interactive shells may not load Bash aliases; invoke the equivalent `git backport` command directly.
- Use `--allow-unapproved` only when the named alias includes it, the user requests it, or the current conversation has already established that option for the same backport.
- The helper performs GitHub writes and writes to the configured Spacewalk checkout. Obtain any required authorization immediately before running it.

From the Uyuni checkout, run:

```bash
git backport TARGET_BRANCH [OPTIONS]
```

If the Git alias is unavailable, invoke `../../automated-scripts/uyuni-backport.sh` relative to this skill's directory with Bash and the same arguments. Do not improvise a separate backport implementation while the helper is available.

## Build, validate, then publish

The team's default is to validate every backport locally before publishing it. Publish directly only when the user explicitly asks for that. Local validation matters: the product branches have their own dependency trees, and their PR checks (`changelog_test`, `frontend_checks`, `merge_enabled`) run on SUSE's internal Jenkins, whose logs are reachable only inside the SUSE network.

The helper creates new commits, which must be signed. Before running it, check that `git -C <Spacewalk checkout> config --get commit.gpgsign` prints `true`; otherwise tell the user and stop.

1. Build the local branch: `git backport TARGET_BRANCH --no-push`, plus any options the user requested. Note the printed branch name.
2. Validate it in the Spacewalk checkout. Checking out the branch changes the user's Spacewalk worktree, so confirm that it is clean first; otherwise ask. For npm dependency changes, run the dependency helper (`../../automated-scripts/uyuni-npm-dependency.sh`, relative to this skill's directory) with `validate PACKAGE`, then `npm --prefix web run build-storybook`. Confirm that `npm --prefix web audit --package-lock-only --json` lists no vulnerability for the package, that `sha1sum web/package-lock.json` matches `web/html/src/vendors/npm.licenses.hash.txt`, run `git diff --check origin/TARGET_BRANCH...HEAD`, and check that `git status --short` shows no changed tracked files. For other changes, run focused tests that fit the change.
3. If validation fails or changes tracked files, stop and report. Do not publish.
4. Switch the Spacewalk checkout back to the branch it was on before; the helper refuses to rebuild a checked-out branch. From the Uyuni source branch, rerun the helper with the same options, without `--no-push`.

For several targets, such as `Manager-5.1` and `Manager-5.2`, finish all steps for one target before starting the next, in the order the user gave.

## Handle the result

On success, verify the PR rather than relying only on command output:

- it is in `SUSE/spacewalk`;
- its base is the requested Manager branch;
- its head is the generated `backport/uyuni-...` branch;
- it is a draft unless `--ready` was requested;
- its body records the full Uyuni source, Spacewalk target, and Spacewalk backport SHAs; and
- the source Uyuni worktree remains unchanged.

Report the PR link, target, and backport commit. State exactly which validation or tests ran.

## Recover conflicts

The helper deliberately retains a temporary isolated Spacewalk worktree when a cherry-pick conflicts. Keep all resolution work in the printed worktree path; do not switch or modify the user's main Spacewalk worktree.

1. Inspect `git status`, unmerged paths, the source commit, and the target-branch conventions before editing.
2. Resolve conflicts semantically, stage them, and run `GIT_EDITOR=true git cherry-pick --continue`. Repeat for every queued commit. For `web/package.json` and `web/package-lock.json`, take the target branch version (`git checkout --ours`) and repeat the npm bump; never merge the lockfile by hand. For the generated license files and `web/spacewalk-web.spec`, take the target branch version and regenerate them with `npm --prefix web ci` and `npm --prefix web run build`, staging the regenerated files when the build asks for it. If Git reports an empty commit, run `git cherry-pick --skip`.
3. Run at least `git diff --check origin/TARGET_BRANCH...HEAD` and inspect the final name-status and stat. Run focused tests when the backport changes executable behavior and suitable tests are available.
4. Follow the helper's printed recovery commands to create the local backport branch, push it, and create or update the PR. For an existing remote branch, use only the printed `--force-with-lease` form and expected remote SHA.
5. Use full commit SHAs in the PR body, then verify the remote PR metadata.
6. Remove the temporary worktree only after the branch is pushed and the PR is verified. Preserve unrelated changes in the main Spacewalk checkout.

### Schema migration directories

Do not blindly accept Git's rename suggestion for a schema migration. Read `schema/spacewalk/susemanager-schema.spec` on the target branch and inspect existing upgrade directories and recent history. A target currently at version `X.Y.Z` normally receives a new migration in the existing `susemanager-schema-X.Y.Z-to-susemanager-schema-X.Y.(Z+1)` directory. Confirm that convention for the branch, then move or stage the migration there.

## Stop safely

- Do not overwrite a changed remote branch without lease protection.
- If source commits, target branch, PR identity, or an existing remote branch cannot be established unambiguously, stop before pushing and ask for direction.
- If PR creation fails after a successful push, keep the local branch and report the pushed branch plus the precise remaining step.
