---
name: uyuni-backport
description: Backport a Uyuni pull request or feature branch to a SUSE Manager product branch with the local uyuni-backport helper, including isolated conflict recovery, branch push, and draft Spacewalk pull-request creation or refresh. Use for requests to backport Uyuni work to branches such as Manager-5.2 or Manager-5.1; do not use for ordinary cherry-picks unrelated to the Uyuni-to-Spacewalk workflow.
---

# Uyuni Backport

Use the repository's `backports/uyuni-backport.sh` helper as the source of truth. Read [the helper documentation](../../backports/README.md) only when setup, options, or behavior beyond this workflow is relevant.

## Prepare

- Work from the clean Uyuni feature branch associated with the source PR. Confirm the branch, status, and upstream before starting.
- Take the target branch from the user's request. Preserve explicitly requested options and previously established workflow context.
- New Spacewalk PRs are drafts by default. Add `--ready` only when the user explicitly requests a ready-for-review PR.
- If the user names a shell alias, resolve it and preserve its arguments. Non-interactive shells may not load Bash aliases; invoke the equivalent `git backport` command directly.
- Use `--allow-unapproved` only when the named alias includes it, the user requests it, or the current conversation has already established that option for the same backport.
- The helper performs GitHub writes and writes to the sibling Spacewalk checkout. Obtain any required authorization immediately before running it.

From the Uyuni checkout, run:

```bash
git backport TARGET_BRANCH [OPTIONS]
```

If the Git alias is unavailable, invoke `../../backports/uyuni-backport.sh` relative to this skill's directory with Bash and the same arguments. Do not improvise a separate backport implementation while the helper is available.

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
2. Resolve conflicts semantically, stage them, and run `GIT_EDITOR=true git cherry-pick --continue`. Repeat for every queued commit.
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
