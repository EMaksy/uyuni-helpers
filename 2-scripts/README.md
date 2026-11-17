# Bumping and backporting with the helper scripts

Two scripts automate the repetitive parts of the
[manual workflow](../1-manual/README.md):

- `uyuni-npm-dependency.sh` (`npm-dependency`) bumps a package and runs all
  validation commands.
- `uyuni-backport.sh` (`git backport`) applies the Uyuni PR to a Spacewalk
  product branch, pushes it, and opens a draft PR.

Research, the changelog, and the reviews stay manual. For these steps, this
guide links to the manual guide. For all options and details of the scripts,
see the [script reference](REFERENCE.md).

- [Requirements](#requirements)
- [Installing the scripts](#installing-the-scripts)
- [Bumping a dependency](#bumping-a-dependency)
- [Backporting to the product branches](#backporting-to-the-product-branches)
- [Updating backports after review changes](#updating-backports-after-review-changes)
- [Special cases](#special-cases)

## Requirements

You need everything from the [manual requirements](../1-manual/README.md#requirements),
plus `sha1sum` for the backport script.

## Installing the scripts

Install the scripts once.

1. Clone this repository:

   ```bash
   git clone https://github.com/EMaksy/uyuni-helpers.git ~/Work/uyuni-helpers
   ```

2. Register the `git backport` command:

   ```bash
   git config --global alias.backport \
     '!bash ~/Work/uyuni-helpers/2-scripts/uyuni-backport.sh'
   ```

3. Register the `npm-dependency` command in `~/.bashrc`:

   ```bash
   cat >> ~/.bashrc <<'EOF'
   alias npm-dependency='bash ~/Work/uyuni-helpers/2-scripts/uyuni-npm-dependency.sh'
   EOF
   ```

4. Load the new command in the current terminal:

   ```bash
   source ~/.bashrc
   ```

5. Check that both commands print their usage:

   ```bash
   git backport -h
   ```

   ```bash
   npm-dependency --help
   ```

> [!NOTE]
> Use `git backport -h`, not `--help`. For aliases, Git intercepts `--help` and
> shows only the alias definition.

The backport script expects Spacewalk next to the Uyuni clone, in
`~/Work/spacewalk`. To use another location, see
[Configuration](REFERENCE.md#configuration).

## Bumping a dependency

1. Choose the package and version, and set the variables. Follow these manual
   sections:
   [Finding the alerts to fix](../1-manual/README.md#finding-the-alerts-to-fix),
   [Choosing the target version](../1-manual/README.md#choosing-the-target-version),
   and [Preparing your terminal](../1-manual/README.md#preparing-your-terminal).

2. Change to your Uyuni clone:

   ```bash
   cd ~/Work/uyuni
   ```

3. Get a branch. Either check out a Dependabot PR as in
   [Using a Dependabot security update](../1-manual/README.md#using-a-dependabot-security-update),
   or create your own branch:

   ```bash
   git fetch origin master
   ```

   ```bash
   git switch --create "$BRANCH" origin/master
   ```

4. Bump and validate the package. On your own branch, run:

   ```bash
   npm-dependency bump "$PACKAGE" "$VERSION"
   ```

   On a Dependabot branch, the bump exists already. Validate it:

   ```bash
   npm-dependency validate "$PACKAGE"
   ```

   The script installs the packages, then runs the unit tests, TypeScript, lint,
   the `package.json` order check, and the production build. It stops at the
   first failure.

5. If the build step stops with *changes to license and/or spec files haven't
   been committed*, stage the regenerated files. This is expected after a bump:

   ```bash
   git add web/html/src/vendors/ web/spacewalk-web.spec
   ```

   Then validate again:

   ```bash
   npm-dependency validate "$PACKAGE"
   ```

6. Check that the license hash matches the lockfile:

   ```bash
   [ "$(sha1sum web/package-lock.json | awk '{print $1}')" = \
     "$(cat web/html/src/vendors/npm.licenses.hash.txt)" ] \
     && echo "license hash OK" || echo "license hash MISMATCH"
   ```

7. Add the changelog fragment as in
   [Adding the changelog](../1-manual/README.md#adding-the-changelog).

8. Review, commit, and open the draft PR as in
   [Reviewing and committing](../1-manual/README.md#reviewing-and-committing)
   and [Opening the draft pull request](../1-manual/README.md#opening-the-draft-pull-request).
   Wait until CI passes.

> [!NOTE]
> The npm script bumps only packages that `package.json` declares directly or
> in its root `overrides`. For a transitive package, bump it as in
> [Bumping manually](../1-manual/README.md#bumping-manually), then run
> `npm-dependency validate "$PACKAGE"`.

## Backporting to the product branches

When CI passes on the Uyuni PR, backport it to each product branch, currently
`Manager-5.1` and `Manager-5.2`. For each branch, build the backport locally,
validate it, then publish it.

The backport script accepts only approved Uyuni PRs by default. Before
approval, use `--allow-unapproved` only when you are sure that the PR is merged
as it is.

1. Set the backport options. Use `--allow-unapproved` before approval, or leave
   the value empty after approval:

   ```bash
   BACKPORT_OPTS=--allow-unapproved
   ```

2. Set the target branch:

   ```bash
   TARGET=Manager-5.1
   ```

3. Change to your Uyuni clone and the PR branch:

   ```bash
   cd ~/Work/uyuni
   ```

   ```bash
   git switch "$BRANCH"
   ```

4. Build the backport locally, without pushing it:

   ```bash
   git backport "$TARGET" --no-push $BACKPORT_OPTS
   ```

   The script prints the name of the backport branch. It resolves the usual
   conflict in `npm.licenses.hash.txt` automatically. For other conflicts, see
   [Resolving a cherry-pick conflict](REFERENCE.md#resolving-a-cherry-pick-conflict).

5. Store the backport branch name:

   ```bash
   BACKPORT="backport/uyuni-$PR-$(printf '%s' "$BRANCH" \
     | tr -cs 'A-Za-z0-9._-' '-')-to-$TARGET"
   ```

6. Change to your Spacewalk clone and the backport branch:

   ```bash
   cd ~/Work/spacewalk
   ```

   ```bash
   git switch "$BACKPORT"
   ```

7. Validate the backport:

   ```bash
   npm-dependency validate "$PACKAGE"
   ```

8. Check the license hash and the backport commits:

   ```bash
   [ "$(sha1sum web/package-lock.json | awk '{print $1}')" = \
     "$(cat web/html/src/vendors/npm.licenses.hash.txt)" ] \
     && echo "license hash OK" || echo "license hash MISMATCH"
   ```

   ```bash
   git diff --check "origin/$TARGET...HEAD"
   ```

9. Check that the validation changed no tracked files. The output must be
   empty, apart from untracked files marked `??`:

   ```bash
   git status --short
   ```

10. Switch the Spacewalk clone back to the target branch. The script does not
    rebuild a branch that is checked out:

    ```bash
    git switch "$TARGET"
    ```

11. Publish the backport. The script pushes the branch and opens a draft PR
    titled `5.1 - <Uyuni PR title>`:

    ```bash
    cd ~/Work/uyuni
    ```

    ```bash
    git backport "$TARGET" $BACKPORT_OPTS
    ```

12. Repeat from step 2 with `TARGET=Manager-5.2`.

13. Add both Spacewalk PR links to the `Port(s):` line of the Uyuni PR
    description.

14. Get the reviews as in [Getting the reviews](../1-manual/README.md#getting-the-reviews).

> [!IMPORTANT]
> **Do not publish a backport that failed validation**
>
> If validation fails or changes tracked files, the published PR would contain
> the same problem. Fix the cause in the Uyuni PR and start again from step 2.
> If only the product branch needs the change, publish that backport manually,
> as in [Backporting to the product branches](../1-manual/README.md#backporting-to-the-product-branches).

## Updating backports after review changes

If the Uyuni PR changes during the review, update both backports. For each
target, set `TARGET` and run the script again from your Uyuni clone:

```bash
git backport "$TARGET" $BACKPORT_OPTS
```

The script rebuilds the backport branch from the updated PR and updates the
Spacewalk PR. It replaces the remote branch with `--force-with-lease`, which
fails if someone else pushed to it in the meantime. Validate the rebuilt
backports again.

## Special cases

| Situation | What to do |
| --- | --- |
| The script reports uncommitted changes in Uyuni | Commit or stash your work, then run it again. |
| *Local HEAD is not the current PR HEAD* | Push your branch, or check out the commit the PR points to. |
| *Review decision is not APPROVED* | Wait for approval, or use `--allow-unapproved` if you are sure that the PR is merged as it is. |
| The backport branch *is checked out* | Switch the Spacewalk clone to the target branch. |
| A cherry-pick stops with a conflict | Follow the commands that the script prints. See [Resolving a cherry-pick conflict](REFERENCE.md#resolving-a-cherry-pick-conflict). |
| A cherry-pick reports an empty commit | The change exists on the target already. Run `git cherry-pick --skip` in the printed worktree. |
| npm reports that the package is not declared directly | The package is transitive. See the note in [Bumping a dependency](#bumping-a-dependency). |
