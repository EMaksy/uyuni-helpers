# Bumping and backporting with the helper scripts

Two scripts automate the repetitive parts of the workflow:

- `uyuni-npm-dependency.sh` (`npm-dependency`) bumps a package and runs all
  validation commands.
- `uyuni-backport.sh` (`git backport`) applies the Uyuni PR to a Spacewalk
  product branch, pushes it, and opens a draft PR.

Copy each command block as a whole. Each part starts by setting the variables
it needs, so you can start any part in a new terminal. For the background of
each step, see the [manual steps](../manual-steps/README.md). For all script
options, see the [script reference](REFERENCE.md).

- [Bumping and backporting with the helper scripts](#bumping-and-backporting-with-the-helper-scripts)
  - [Requirements](#requirements)
  - [Installing the scripts](#installing-the-scripts)
  - [Bumping a dependency](#bumping-a-dependency)
    - [Choosing the package and version](#choosing-the-package-and-version)
    - [Setting the variables](#setting-the-variables)
    - [Creating the branch](#creating-the-branch)
      - [Option A: Dependabot security update](#option-a-dependabot-security-update)
      - [Option B: Your own branch](#option-b-your-own-branch)
    - [Bumping and validating](#bumping-and-validating)
    - [Adding the changelog](#adding-the-changelog)
    - [Committing and opening the draft PR](#committing-and-opening-the-draft-pr)
  - [Backporting to the product branches](#backporting-to-the-product-branches)
  - [Updating backports after review changes](#updating-backports-after-review-changes)
  - [Getting the reviews](#getting-the-reviews)
  - [Special cases](#special-cases)

## Requirements

You need the following:

- Access to the Dependabot alerts of `uyuni-project/uyuni`, and push access to
  `uyuni-project/uyuni` and `SUSE/spacewalk`.
- Git, the GitHub CLI (`gh`), `jq`, `sha1sum`, Node.js 22, and npm 10 or later.
- Clones of both repositories in `~/Work/uyuni` and `~/Work/spacewalk`. If your
  clones are in another place, adjust these paths in the commands. The backport
  script looks for Spacewalk next to your Uyuni clone. For another location,
  see [Configuration](REFERENCE.md#configuration).

Set up your machine once:

1. Check that Git signs your commits, as Uyuni requires. The command must print
   `true`. Otherwise, set up signing as described in
   [GitHub: Signing commits](https://docs.github.com/en/authentication/managing-commit-signature-verification/signing-commits).

   ```bash
   git config --get commit.gpgsign
   ```

2. Log in to GitHub:

   ```bash
   gh auth login --hostname github.com
   ```

## Installing the scripts

1. Clone this repository:

   ```bash
   git clone https://github.com/EMaksy/uyuni-helpers.git ~/Work/uyuni-helpers
   ```

2. Register the `git backport` and `npm-dependency` commands:

   ```bash
   git config --global alias.backport \
     '!bash ~/Work/uyuni-helpers/automated-scripts/uyuni-backport.sh'
   cat >> ~/.bashrc <<'EOF'
   alias npm-dependency='bash ~/Work/uyuni-helpers/automated-scripts/uyuni-npm-dependency.sh'
   EOF
   source ~/.bashrc
   ```

3. Check that both commands print their usage. Use `git backport -h`: for
   aliases, Git intercepts `--help`.

   ```bash
   git backport -h
   npm-dependency --help
   ```

## Bumping a dependency

This part creates the Uyuni change, from the branch to the draft PR. Bump one
package per branch and PR.

### Choosing the package and version

1. List the packages with open npm alerts, sorted by their number of alerts.
   Choose critical or high severity first, then the package with the most
   alerts:

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

2. List the open alerts of your package. The columns are alert number,
   severity, CVE, and first fixed version. The highest fixed version fixes all
   alerts:

   ```bash
   PACKAGE=dompurify
   gh api --method GET --paginate \
     repos/uyuni-project/uyuni/dependabot/alerts \
     --raw-field state=open --raw-field ecosystem=npm \
     --raw-field package="$PACKAGE" --raw-field per_page=100 \
     --jq '.[] | [.number, .security_advisory.severity,
       (.security_advisory.cve_id // "no CVE"),
       (.security_vulnerability.first_patched_version.identifier // "none")]
       | @tsv'
   ```

Before you bump, confirm the fix in the advisory, on GitHub, and on npm. Check
how Uyuni uses the package, and find the `bsc#` number of each CVE, as
described in [Choosing the target version](../manual-steps/README.md#choosing-the-target-version).

### Setting the variables

1. Set the values for this bump. For `AUTHOR`, use the identifier of your
   earlier changelog files, usually your GitHub or SUSE user name:

   ```bash
   PACKAGE=dompurify                      # package to bump
   OLD=3.4.15                             # current version
   VERSION=3.4.17                         # new version
   REFS="CVE-2026-104844, bsc#1284190"    # CVE and bsc# pairs, or empty
   AUTHOR=jdoe                            # your changelog identifier
   ```

2. Derive the branch name, the changelog file, and the PR title. Copy this
   block unchanged:

   ```bash
   SLUG=$(echo "$PACKAGE" | sed 's#^@##; s#/#-#g')
   BRANCH="bump-$SLUG-$VERSION"
   CHANGES="web/spacewalk-web.changes.$AUTHOR.$SLUG-${VERSION//./-}"
   TITLE="Bump $PACKAGE from $OLD to $VERSION in /web${REFS:+ ($REFS)}"
   printf '%s\n' "$BRANCH" "$CHANGES" "$TITLE"
   ```

### Creating the branch

Use a Dependabot security update if possible. Otherwise, create your own
branch. Follow only one of the two options.

#### Option A: Dependabot security update

On one of the package's alert pages, click **Create Dependabot security update**. When Dependabot has opened the PR,
check it out. Replace `12345` with the PR number:

```bash
PR=12345
cd ~/Work/uyuni
gh pr checkout "$PR"
BRANCH=$(git branch --show-current)
```

#### Option B: Your own branch

Create the branch from the current `master`. The status output must be empty:

```bash
cd ~/Work/uyuni
git status --short
git fetch origin master
git switch --create "$BRANCH" origin/master
```

### Bumping and validating

1. Bump and validate the package. The script installs the packages, then runs
   the unit tests, TypeScript, lint, the `package.json` order check, and the
   production build. It stops at the first failure.

   - For option B, bump the package:

     ```bash
     cd ~/Work/uyuni
     npm-dependency bump "$PACKAGE" "$VERSION"
     ```

   - For option A, Dependabot has bumped it already. Validate it:

     ```bash
     cd ~/Work/uyuni
     npm-dependency validate "$PACKAGE"
     ```

2. After a bump, the build step stops with *changes to license and/or spec
   files haven't been committed*. This is expected. Stage the regenerated files
   and validate again:

   ```bash
   git add web/html/src/vendors/ web/spacewalk-web.spec
   npm-dependency validate "$PACKAGE"
   ```

3. Build Storybook, which the CI builds too, and confirm that the vulnerability
   is gone. The last output must be *no known vulnerabilities*:

   ```bash
   npm --prefix web run build-storybook &&
   npm --prefix web audit --package-lock-only --json \
     | jq --raw-output --arg p "$PACKAGE" \
       '.vulnerabilities[$p] // "no known vulnerabilities"'
   ```

   If it lists advisories instead, open them. Either the new version does not
   fix all of them, or a dependency of the package is still vulnerable.

The npm script bumps only packages that `package.json` declares. For a
transitive package, bump it as described in
[Option B: Your own branch](../manual-steps/README.md#option-b-your-own-branch), then run
`npm-dependency validate "$PACKAGE"`.

### Adding the changelog

1. Create the changelog file with the version line, and open it:

   ```bash
   cd ~/Work/uyuni
   echo "- Update $PACKAGE from version $OLD to $VERSION" > "$CHANGES"
   ${EDITOR:-vi} "$CHANGES"
   ```

2. Add one entry per CVE. Indent continuation lines with two spaces:

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

### Committing and opening the draft PR

1. Optional: Double-check that the license hash matches the lockfile:

   ```bash
   cd ~/Work/uyuni
   [ "$(sha1sum web/package-lock.json | awk '{print $1}')" = \
     "$(cat web/html/src/vendors/npm.licenses.hash.txt)" ] \
     && echo "license hash OK" || echo "license hash MISMATCH"
   ```

2. Review the change. Expect `package.json`, the lockfile, the license files,
   and the changelog file. The lockfile may change only the package and its own
   dependencies:

   ```bash
   cd ~/Work/uyuni
   git status --short
   git diff HEAD -- web/package.json web/package-lock.json
   ```

3. Commit the change:

   ```bash
   git add web/package.json web/package-lock.json \
     web/html/src/vendors/ web/spacewalk-web.spec "$CHANGES"
   git commit --message "Bump $PACKAGE from $OLD to $VERSION"
   ```

4. Push and open the draft PR:

   - For option B, push your branch and create the PR. When `gh` asks for the
     description, name the fixed advisories and the checks that passed:

     ```bash
     git push --set-upstream origin "$BRANCH"
     gh pr create --repo uyuni-project/uyuni --draft \
       --base master --head "$BRANCH" --title "$TITLE"
     ```

   - For option A, push to the Dependabot branch, then make the PR a draft and
     set its title:

     ```bash
     git push
     gh pr ready "$PR" --undo
     gh pr edit "$PR" --title "$TITLE"
     ```

5. Wait for CI:

   ```bash
   PR=$(gh pr view --json number --jq .number)
   gh pr checks "$PR" --repo uyuni-project/uyuni --watch
   ```

   All checks must pass. The list must contain `changelog_test` and the four
   frontend checks: `frontend_build`, `frontend_lint`, `frontend_unit_tests`,
   and `frontend_typescript_compilation`. The frontend checks run only when
   files in `web/html/src/` change. If they are missing, the license files are
   not part of the PR.

## Backporting to the product branches

When CI passes on the Uyuni PR, backport it to each product branch, currently
`Manager-5.1` and `Manager-5.2`. For each branch, build the backport locally,
validate it, then publish it.

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

1. Set the values for the backport. Leave `BACKPORT_OPTS` empty after approval:

   ```bash
   PR=12345                            # Uyuni PR number
   PACKAGE=dompurify                   # bumped package
   BACKPORT_OPTS=--allow-unapproved    # empty after approval
   ```

2. Build the backport locally, without pushing it. The script resolves the usual
   conflict in `npm.licenses.hash.txt` itself. For other conflicts, see
   [Resolving a cherry-pick conflict](REFERENCE.md#resolving-a-cherry-pick-conflict):

   ```bash
   TARGET=Manager-5.1
   cd ~/Work/uyuni
   gh pr checkout "$PR"
   BACKPORT="backport/uyuni-$PR-$(git branch --show-current \
     | tr -d '\n' | tr -cs 'A-Za-z0-9._-' '-')-to-$TARGET"
   git backport "$TARGET" --no-push $BACKPORT_OPTS
   ```

3. Validate the backport in your Spacewalk clone. When all checks pass, the last
   line is *All checks passed*:

   ```bash
   cd ~/Work/spacewalk &&
   git switch "$BACKPORT" &&
   npm-dependency validate "$PACKAGE" &&
   npm --prefix web run build-storybook &&
   echo "All checks passed"
   ```

4. Confirm that the vulnerability is gone. The output must be
   *no known vulnerabilities*:

   ```bash
   npm --prefix web audit --package-lock-only --json \
     | jq --raw-output --arg p "$PACKAGE" \
       '.vulnerabilities[$p] // "no known vulnerabilities"'
   ```

5. Optional: Double-check the license hash, the backport commits, and that
   the validation changed no tracked files. The status output may list only
   untracked files, marked `??`:

   ```bash
   [ "$(sha1sum web/package-lock.json | awk '{print $1}')" = \
     "$(cat web/html/src/vendors/npm.licenses.hash.txt)" ] \
     && echo "license hash OK" || echo "license hash MISMATCH"
   git diff --check "origin/$TARGET...HEAD"
   git status --short
   ```

6. Publish the backport. The script pushes the branch and opens a draft PR
   titled `5.1 - <Uyuni PR title>`, which links to the Uyuni PR. It does not
   rebuild a branch that is checked out, so switch Spacewalk back first:

   ```bash
   git switch "$TARGET"
   cd ~/Work/uyuni
   git backport "$TARGET" $BACKPORT_OPTS
   ```

7. Repeat from step 2 with `TARGET=Manager-5.2`.

## Updating backports after review changes

If the Uyuni PR changes during the review, run
[Backporting to the product branches](#backporting-to-the-product-branches)
again. Step 2 checks out the updated PR branch, and the script rebuilds each
backport from it. When you publish, the script replaces the remote branch with
`--force-with-lease` and updates the existing Spacewalk PR.

## Getting the reviews

Ask for reviews when CI passes on the Uyuni PR.

1. Mark the Uyuni PR ready for review. GitHub then requests a review from the
   frontend squad (`uyuni-project/frontend`):

   ```bash
   PR=12345
   gh pr ready "$PR" --repo uyuni-project/uyuni
   ```

2. Request a review from your team's security champion. Replace
   `GITHUB_LOGIN` with their GitHub login:

   ```bash
   gh pr edit "$PR" --repo uyuni-project/uyuni --add-reviewer GITHUB_LOGIN
   ```

3. After both approvals, mark all Spacewalk PRs of the backports ready:

   ```bash
   for n in $(gh pr list --repo SUSE/spacewalk \
       --search "head:backport/uyuni-$PR-" --json number --jq '.[].number'); do
     gh pr ready "$n" --repo SUSE/spacewalk
   done
   ```

4. Wait until a reviewer merges the PRs. Both repositories allow only
   **Create a merge commit**.

## Special cases

| Situation | What to do |
| --- | --- |
| The script reports uncommitted changes in Uyuni | Commit or stash your work, then run it again. |
| *Local HEAD is not the current PR HEAD* | Run `gh pr checkout "$PR"` to get the current PR head. |
| *Review decision is not APPROVED* | Wait for approval, or use `--allow-unapproved` if you are sure that the PR is merged as it is. |
| The backport branch *is checked out* | Switch the Spacewalk clone to the target branch. |
| A cherry-pick stops with a conflict | Follow the commands that the script prints. See [Resolving a cherry-pick conflict](REFERENCE.md#resolving-a-cherry-pick-conflict). |
| A cherry-pick reports an empty commit | The change exists on the target already. Run `git cherry-pick --skip` in the printed worktree. |
| npm reports that the package is not declared directly | The package is transitive. See the note at the end of [Bumping and validating](#bumping-and-validating). |
| The PR shows no frontend checks | The license files are not part of the PR. Regenerate them, commit them, and push. |
| GitHub marks a commit as *Unverified* | Set up commit signing, then re-sign with `git rebase --force-rebase --gpg-sign origin/master` and push with `git push --force-with-lease`. |
| GitHub reports conflicts with `master` | Run `git rebase origin/master`. Resolve conflicts as in [Resolving backport conflicts](../manual-steps/README.md#resolving-backport-conflicts), with `git rebase --continue` instead of `git cherry-pick --continue`. Push with `git push --force-with-lease`. |
