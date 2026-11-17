# Bumping and backporting with the helper scripts

Two scripts automate the repetitive parts of the workflow:

- `uyuni-npm-dependency.sh` (`npm-dependency`) bumps a package and runs all
  validation commands.
- `uyuni-backport.sh` (`git backport`) applies the Uyuni PR to a Spacewalk
  product branch, pushes it, and opens a draft PR.

This guide covers the complete workflow with the scripts. Each part sets its
own variables, so you can start any part in a new terminal. For the background
of each step, see the [manual steps](../manual-steps/README.md). For all
options of the scripts, see the [script reference](REFERENCE.md).

- [Bumping and backporting with the helper scripts](#bumping-and-backporting-with-the-helper-scripts)
  - [Requirements](#requirements)
  - [Installing the scripts](#installing-the-scripts)
  - [Bumping a dependency](#bumping-a-dependency)
    - [Choosing the package and version](#choosing-the-package-and-version)
    - [Setting the variables](#setting-the-variables)
    - [Creating the branch](#creating-the-branch)
    - [Bumping and validating](#bumping-and-validating)
    - [Adding the changelog](#adding-the-changelog)
    - [Double-checking the result](#double-checking-the-result)
    - [Committing and opening the draft PR](#committing-and-opening-the-draft-pr)
  - [Backporting to the product branches](#backporting-to-the-product-branches)
  - [Updating backports after review changes](#updating-backports-after-review-changes)
  - [Getting the reviews](#getting-the-reviews)
  - [Special cases](#special-cases)

## Requirements

You need the following access and tools:

- Access to the Dependabot alerts of `uyuni-project/uyuni`.
- Push access to `uyuni-project/uyuni` and to `SUSE/spacewalk`.
- Git, the GitHub CLI (`gh`), `jq`, and `sha1sum`.
- Node.js 22 and npm 10 or later.
- Clones of both repositories in `~/Work/uyuni` and `~/Work/spacewalk`.
- Git set up to sign your commits. Uyuni requires signed commits, and the
  backport script creates new commits in Spacewalk.

Check that Git signs your commits. The command prints `true` if it does:

```bash
git config --get commit.gpgsign
```

If it prints nothing, set up signing with a GPG or SSH key as described in
[GitHub: Signing commits](https://docs.github.com/en/authentication/managing-commit-signature-verification/signing-commits).

Log in to GitHub with the GitHub CLI:

```bash
gh auth login --hostname github.com
```

## Installing the scripts

Install the scripts once.

1. Clone this repository:

   ```bash
   git clone https://github.com/EMaksy/uyuni-helpers.git ~/Work/uyuni-helpers
   ```

2. Register the `git backport` command:

   ```bash
   git config --global alias.backport \
     '!bash ~/Work/uyuni-helpers/automated-scripts/uyuni-backport.sh'
   ```

3. Register the `npm-dependency` command in `~/.bashrc`:

   ```bash
   cat >> ~/.bashrc <<'EOF'
   alias npm-dependency='bash ~/Work/uyuni-helpers/automated-scripts/uyuni-npm-dependency.sh'
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

## Bumping a dependency

Bump one package per branch and per PR.

### Choosing the package and version

1. List the packages with open npm alerts, sorted by their number of alerts:

   ```bash
   gh api --method GET --paginate --slurp \
     repos/uyuni-project/uyuni/dependabot/alerts \
     --raw-field state=open --raw-field ecosystem=npm --raw-field per_page=100 \
     | jq --raw-output 'add | group_by(.dependency.package.name)
         | sort_by(-length)[]
         | [length, .[0].dependency.package.name,
            (map(.security_advisory.severity) | unique | join(","))]
         | @tsv'
   ```

   Choose a package with critical or high severity first, then the one with
   the most alerts.

2. Store the package name:

   ```bash
   PACKAGE=dompurify
   ```

3. List its open alerts. The columns are alert number, severity, CVE, and first
   fixed version:

   ```bash
   gh api --method GET --paginate \
     repos/uyuni-project/uyuni/dependabot/alerts \
     --raw-field state=open --raw-field ecosystem=npm \
     --raw-field package="$PACKAGE" --raw-field per_page=100 \
     --jq '.[] | [.number, .security_advisory.severity,
       (.security_advisory.cve_id // "no CVE"),
       (.security_vulnerability.first_patched_version.identifier // "none")]
       | @tsv'
   ```

   The highest fixed version is the smallest version that fixes all alerts.

Before you bump, confirm the fix in the advisory, on GitHub, and on npm. Check
how Uyuni uses the package, and find the `bsc#` number of each CVE. The
[manual steps](../manual-steps/README.md#choosing-the-target-version) describe
these checks.

### Setting the variables

1. Set the values for this bump. For `AUTHOR`, use the same identifier as in
   your earlier changelog files, usually your GitHub or SUSE user name:

   ```bash
   PACKAGE=dompurify                      # package to bump
   OLD=3.4.15                             # current version
   VERSION=3.4.17                         # new version
   REFS="CVE-2026-104844, bsc#1284190"    # CVE and bsc# pairs, or empty
   AUTHOR=jdoe                            # your changelog identifier
   ```

2. Derive the branch name, the changelog file name, and the PR title:

   ```bash
   SLUG=$(echo "$PACKAGE" | sed 's#^@##; s#/#-#g')
   BRANCH="bump-$SLUG-$VERSION"
   CHANGES="web/spacewalk-web.changes.$AUTHOR.$SLUG-${VERSION//./-}"
   TITLE="Bump $PACKAGE from $OLD to $VERSION in /web${REFS:+ ($REFS)}"
   ```

3. Check the values:

   ```bash
   printf '%s\n' "$BRANCH" "$CHANGES" "$TITLE"
   ```

> [!NOTE]
> Variables exist only in the current terminal. The following sections up to
> [Committing and opening the draft PR](#committing-and-opening-the-draft-pr)
> use them. In a new terminal, run this section again.

### Creating the branch

1. Change to your Uyuni clone:

   ```bash
   cd ~/Work/uyuni
   ```

2. Check that the working tree is clean:

   ```bash
   git status --short --branch
   ```

3. Fetch the current `master`:

   ```bash
   git fetch origin master
   ```

4. Create your branch from it:

   ```bash
   git switch --create "$BRANCH" origin/master
   ```

If Dependabot opened a PR for the package, use its branch instead of steps 3
and 4. Store the PR number, check out the PR, and take over its branch name:

```bash
PR=12345
```

```bash
gh pr checkout "$PR"
```

```bash
BRANCH=$(git branch --show-current)
```

### Bumping and validating

1. Bump and validate the package. On your own branch, run:

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

2. If the build step stops with *changes to license and/or spec files haven't
   been committed*, stage the regenerated files. This is expected after a bump:

   ```bash
   git add web/html/src/vendors/ web/spacewalk-web.spec
   ```

3. Validate again. All steps now pass:

   ```bash
   npm-dependency validate "$PACKAGE"
   ```

4. Build Storybook. The script does not build it, but the CI does for every
   frontend change:

   ```bash
   npm --prefix web run build-storybook
   ```

5. Confirm that npm reports no known vulnerability for the package. npm checks
   the same GitHub advisories as Dependabot:

   ```bash
   npm --prefix web audit --package-lock-only --json \
     | jq --raw-output --arg p "$PACKAGE" \
       '.vulnerabilities[$p] // "no known vulnerabilities"'
   ```

   If the output lists advisories instead, open them. Either the new version
   does not fix all of them, or a dependency of the package is still
   vulnerable.

> [!NOTE]
> The npm script bumps only packages that `package.json` declares directly or
> in its root `overrides`. For a transitive package, bump it as in
> [Bumping manually](../manual-steps/README.md#bumping-manually), then run
> `npm-dependency validate "$PACKAGE"`.

### Adding the changelog

1. Create the changelog fragment with the version line:

   ```bash
   echo "- Update $PACKAGE from version $OLD to $VERSION" > "$CHANGES"
   ```

2. Add one entry per CVE with a text editor:

   ```bash
   ${EDITOR:-vi} "$CHANGES"
   ```

   The finished fragment looks like this. Indent continuation lines with two
   spaces:

   ```text
   - Update postcss-selector-parser from version 7.1.0 to 7.1.7
   - CVE-2026-104844: PostCSS: Quadratic complexity in flat selector
     parsing allows CPU exhaustion (bsc#1284190)
   ```

3. Check that no line is longer than 67 characters. No output means the file
   is fine:

   ```bash
   awk 'length > 67 {print FILENAME ":" FNR ": " length " characters"}' "$CHANGES"
   ```

### Double-checking the result

Optionally, double-check that all is good before you commit.

1. Check that the license hash matches the lockfile:

   ```bash
   [ "$(sha1sum web/package-lock.json | awk '{print $1}')" = \
     "$(cat web/html/src/vendors/npm.licenses.hash.txt)" ] \
     && echo "license hash OK" || echo "license hash MISMATCH"
   ```

2. Check the list of changed files. Expect `package.json`, the lockfile, the
   license files, and the changelog fragment:

   ```bash
   git status --short
   ```

3. Review the lockfile change. Only the package and its own dependencies may
   change:

   ```bash
   git diff HEAD -- web/package-lock.json
   ```

### Committing and opening the draft PR

1. Stage the change:

   ```bash
   git add web/package.json web/package-lock.json \
     web/html/src/vendors/ web/spacewalk-web.spec "$CHANGES"
   ```

2. Commit it:

   ```bash
   git commit --message "Bump $PACKAGE from $OLD to $VERSION"
   ```

3. Push the branch:

   ```bash
   git push --set-upstream origin "$BRANCH"
   ```

4. Create the draft PR. When `gh` asks for the description, name the fixed
   advisories and the checks that passed:

   ```bash
   gh pr create --repo uyuni-project/uyuni --draft \
     --base master --head "$BRANCH" --title "$TITLE"
   ```

   On a Dependabot branch, the PR exists already. Convert it to a draft and set
   the title instead:

   ```bash
   gh pr ready "$PR" --undo
   ```

   ```bash
   gh pr edit "$PR" --title "$TITLE"
   ```

5. Store the PR number:

   ```bash
   PR=$(gh pr view --json number --jq .number)
   ```

6. Wait for CI:

   ```bash
   gh pr checks "$PR" --repo uyuni-project/uyuni --watch
   ```

   All checks must pass. Make sure that the list contains `changelog_test` and
   the four frontend checks: `frontend_build`, `frontend_lint`,
   `frontend_unit_tests`, and `frontend_typescript_compilation`. The frontend
   checks run only when files in `web/html/src/` change. If they are missing,
   the license files are not part of the PR.

## Backporting to the product branches

When CI passes on the Uyuni PR, backport it to each product branch, currently
`Manager-5.1` and `Manager-5.2`. For each branch, build the backport locally,
validate it, then publish it. This section sets its own variables, so you can
start it in a new terminal.

The backport script accepts only approved Uyuni PRs by default. Before
approval, use `--allow-unapproved` only when you are sure that the PR is merged
as it is.

> [!IMPORTANT]
> **Validate every backport before you publish it**
>
> The product branches run little CI. `Manager-5.1` runs no frontend checks,
> and `Manager-5.2` runs only the build, the unit tests, and TypeScript. If
> validation fails or changes tracked files, do not publish. Fix the cause in
> the Uyuni PR and start again from step 2. If only the product branch needs a
> change, publish that backport manually, as in
> [Backporting to the product branches](../manual-steps/README.md#backporting-to-the-product-branches).

1. Set the Uyuni PR number, the bumped package, and the backport options. Leave
   `BACKPORT_OPTS` empty after approval:

   ```bash
   PR=12345                            # Uyuni PR number
   PACKAGE=dompurify                   # bumped package, used for validation
   BACKPORT_OPTS=--allow-unapproved    # empty after approval
   ```

2. Set the target branch:

   ```bash
   TARGET=Manager-5.1
   ```

3. Change to your Uyuni clone:

   ```bash
   cd ~/Work/uyuni
   ```

4. Check out the branch of the Uyuni PR:

   ```bash
   gh pr checkout "$PR"
   ```

5. Derive the backport branch name. It is the name that the script creates:

   ```bash
   BACKPORT="backport/uyuni-$PR-$(git branch --show-current \
     | tr -d '\n' | tr -cs 'A-Za-z0-9._-' '-')-to-$TARGET"
   ```

6. Build the backport locally, without pushing it:

   ```bash
   git backport "$TARGET" --no-push $BACKPORT_OPTS
   ```

   The script resolves the usual conflict in `npm.licenses.hash.txt`
   automatically. For other conflicts, see
   [Resolving a cherry-pick conflict](REFERENCE.md#resolving-a-cherry-pick-conflict).

7. Change to your Spacewalk clone:

   ```bash
   cd ~/Work/spacewalk
   ```

8. Check out the backport branch:

   ```bash
   git switch "$BACKPORT"
   ```

9. Validate the backport:

   ```bash
   npm-dependency validate "$PACKAGE"
   ```

10. Build Storybook:

    ```bash
    npm --prefix web run build-storybook
    ```

11. Confirm that npm reports no known vulnerability for the package. The output
    must be *no known vulnerabilities*:

    ```bash
    npm --prefix web audit --package-lock-only --json \
      | jq --raw-output --arg p "$PACKAGE" \
        '.vulnerabilities[$p] // "no known vulnerabilities"'
    ```

12. Optionally, double-check that all is good. Check the license hash, the
    backport commits, and that the validation changed no tracked files:

    ```bash
    [ "$(sha1sum web/package-lock.json | awk '{print $1}')" = \
      "$(cat web/html/src/vendors/npm.licenses.hash.txt)" ] \
      && echo "license hash OK" || echo "license hash MISMATCH"
    ```

    ```bash
    git diff --check "origin/$TARGET...HEAD"
    ```

    ```bash
    git status --short
    ```

    The status output must be empty, apart from untracked files marked `??`.

13. Switch the Spacewalk clone back to the target branch. The script does not
    rebuild a branch that is checked out:

    ```bash
    git switch "$TARGET"
    ```

14. Change back to your Uyuni clone:

    ```bash
    cd ~/Work/uyuni
    ```

15. Publish the backport. The script pushes the branch and opens a draft PR
    titled `5.1 - <Uyuni PR title>`. Its description links to the Uyuni PR, so
    you do not need to change the Uyuni PR:

    ```bash
    git backport "$TARGET" $BACKPORT_OPTS
    ```

16. Repeat from step 2 with `TARGET=Manager-5.2`.

## Updating backports after review changes

If the Uyuni PR changes during the review, update both backports: run
[Backporting to the product branches](#backporting-to-the-product-branches)
again, with the same steps and the same variables.

Step 4 checks out the updated PR branch, and the script rebuilds each backport
from it. When you publish, the script replaces the remote branch with
`--force-with-lease`, which fails if someone else pushed to it in the meantime.
It also updates the existing Spacewalk PR instead of opening a new one.

## Getting the reviews

Ask for reviews when CI passes on the Uyuni PR. This section sets its own
variables, so you can start it in a new terminal.

1. Set the Uyuni PR number:

   ```bash
   PR=12345
   ```

2. Mark the Uyuni PR ready for review. GitHub then requests a review from the
   frontend squad (`uyuni-project/frontend`):

   ```bash
   gh pr ready "$PR" --repo uyuni-project/uyuni
   ```

3. Request a review from your team's security champion. Replace
   `GITHUB_LOGIN` with their GitHub login:

   ```bash
   gh pr edit "$PR" --repo uyuni-project/uyuni --add-reviewer GITHUB_LOGIN
   ```

4. Wait for both approvals.

5. List the Spacewalk PRs of the backports:

   ```bash
   gh pr list --repo SUSE/spacewalk --search "head:backport/uyuni-$PR-"
   ```

6. Mark each Spacewalk PR ready for review. Replace `NUMBER` with a PR number
   from the list:

   ```bash
   gh pr ready NUMBER --repo SUSE/spacewalk
   ```

7. Wait until a reviewer merges the PRs after approval. Both repositories
   allow only **Create a merge commit**, so squash and rebase merges are not
   possible.

## Special cases

| Situation | What to do |
| --- | --- |
| The script reports uncommitted changes in Uyuni | Commit or stash your work, then run it again. |
| *Local HEAD is not the current PR HEAD* | Run `gh pr checkout "$PR"` to get the current PR head. |
| *Review decision is not APPROVED* | Wait for approval, or use `--allow-unapproved` if you are sure that the PR is merged as it is. |
| The backport branch *is checked out* | Switch the Spacewalk clone to the target branch. |
| A cherry-pick stops with a conflict | Follow the commands that the script prints. See [Resolving a cherry-pick conflict](REFERENCE.md#resolving-a-cherry-pick-conflict). |
| A cherry-pick reports an empty commit | The change exists on the target already. Run `git cherry-pick --skip` in the printed worktree. |
| npm reports that the package is not declared directly | The package is transitive. See the note in [Bumping and validating](#bumping-and-validating). |
| The PR shows no frontend checks | The license files are not part of the PR. Regenerate them, commit them, and push. |
| GitHub marks a commit as *Unverified* | Set up commit signing, see [Requirements](#requirements). Then re-sign your commits with `git rebase --force-rebase --gpg-sign origin/master` and push with `git push --force-with-lease`. |
| GitHub reports conflicts with `master` | Rebase with `git rebase origin/master`. Resolve conflicts as in [Resolving backport conflicts](../manual-steps/README.md#resolving-backport-conflicts), with `git rebase --continue` instead of `git cherry-pick --continue`. Then push with `git push --force-with-lease`. |
