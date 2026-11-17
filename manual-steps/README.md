# Bumping and backporting npm dependencies by hand

This guide fixes an npm security alert in Uyuni step by step, without scripts
or AI. It also backports the fix to the SUSE Manager product branches. Work
through it once by hand: the [scripts](../automated-scripts/README.md) and the
[AI agent](../agentic-skills/README.md) automate the same steps.

Copy each command block as a whole. Each part starts by setting the variables
it needs, so you can start any part in a new terminal.

- [Bumping and backporting npm dependencies by hand](#bumping-and-backporting-npm-dependencies-by-hand)
  - [Requirements](#requirements)
  - [Finding the alerts to fix](#finding-the-alerts-to-fix)
  - [Choosing the target version](#choosing-the-target-version)
  - [Bumping the dependency](#bumping-the-dependency)
    - [Setting the variables](#setting-the-variables)
    - [Creating the branch](#creating-the-branch)
      - [Option A: Dependabot security update](#option-a-dependabot-security-update)
      - [Option B: Your own branch](#option-b-your-own-branch)
    - [Regenerating the license files](#regenerating-the-license-files)
    - [Adding the changelog](#adding-the-changelog)
    - [Validating the change](#validating-the-change)
    - [Committing and opening the draft PR](#committing-and-opening-the-draft-pr)
  - [Backporting to the product branches](#backporting-to-the-product-branches)
    - [Resolving backport conflicts](#resolving-backport-conflicts)
  - [Getting the reviews](#getting-the-reviews)
  - [Troubleshooting](#troubleshooting)
  - [Lessons learned](#lessons-learned)
  - [More information](#more-information)

## Requirements

You need the following:

- Access to the Dependabot alerts of `uyuni-project/uyuni`, and push access to
  `uyuni-project/uyuni` and `SUSE/spacewalk`.
- Git, the GitHub CLI (`gh`), `jq`, Node.js 22, and npm 10 or later.
- Clones of both repositories in `~/Work/uyuni` and `~/Work/spacewalk`. If your
  clones are in another place, adjust these paths in the commands.

Set up your machine once:

1. Check that Git signs your commits, as Uyuni requires. The command must print
   `true`. Otherwise, set up signing as described in
   [GitHub: Signing commits](https://docs.github.com/en/authentication/managing-commit-signature-verification/signing-commits).

   ```bash
   git config --get commit.gpgsign
   ```

2. Clone both repositories, if you do not have them yet:

   ```bash
   git clone git@github.com:uyuni-project/uyuni.git ~/Work/uyuni
   git clone git@github.com:SUSE/spacewalk.git ~/Work/spacewalk
   ```

3. Log in to GitHub:

   ```bash
   gh auth login --hostname github.com
   ```

## Finding the alerts to fix

Fix the most severe alerts first, and prefer a package that causes several
alerts: one bump can close all of them. Bump one package per branch and PR.

1. Open the [open npm alerts of Uyuni](https://github.com/uyuni-project/uyuni/security/dependabot?q=is%3Aopen+ecosystem%3Anpm).
2. Look for **Critical** alerts first, then **High**.
3. Open the **Package** filter. The number next to each package is its count of
   open alerts.

The same overview in a terminal lists each package with its number of alerts
and their severities:

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

The output is similar to this:

```text
5       dompurify       critical,high,low
5       fast-uri        low,medium
```

## Choosing the target version

Choose the smallest version that fixes every open alert of the package. A small
step keeps the risk of breaking changes low.

1. List the open alerts of the package. Replace `dompurify` with your package:

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

   The columns are alert number, severity, CVE, and first fixed version. The
   highest fixed version fixes all alerts, here `3.4.17`:

   ```text
   593     critical        no CVE  3.4.17
   547     low     no CVE  3.4.16
   ```

2. Check that npm publishes this version, and show the version that Uyuni uses
   now:

   ```bash
   cd ~/Work/uyuni
   VERSION=3.4.17
   npm view "$PACKAGE@$VERSION" version
   npm --prefix web ls "$PACKAGE" --all --package-lock-only
   ```

   The first command prints the version if it exists. In the tree, a package at
   the top level is a *direct* dependency. A package that appears only below
   another package is a *transitive* dependency.

3. Confirm the fix and its impact:

   - Open each advisory from its alert page, and find the fix in the package's
     GitHub releases or changelog.
   - Find where Uyuni uses the package. For a major version bump, check the
     release notes for breaking changes that affect these places.
   - Open each CVE in the [SUSE CVE database](https://www.suse.com/security/cve/)
     and note its SUSE Bugzilla (`bsc#`) number.

An AI assistant can speed up this research, see
[Researching the next bump](../agentic-skills/README.md#researching-the-next-bump).
Verify every result in the sources.

| Situation | What to do |
| --- | --- |
| No fixed version exists | Do not bump. Report the exposure to the security champion. |
| The alert has no CVE yet | Write only the version line in the changelog. Name the GHSA in the PR description and ask the security champion. |
| A CVE has no SUSE Bugzilla entry | Ask Security for one before you write the changelog. |
| An open PR already fixes the alert | Continue on that PR instead of opening a new one. |

## Bumping the dependency

This part creates the Uyuni change, from the branch to the draft PR.

### Setting the variables

1. Set the values for this bump. Take `OLD` from the tree in the previous
   section. For `AUTHOR`, use the identifier of your earlier changelog files,
   usually your GitHub or SUSE user name:

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

Use a Dependabot security update if possible: Dependabot then creates the
branch and the bump for you. Otherwise, create your own branch. Follow only one
of the two options.

#### Option A: Dependabot security update

1. On one of the package's alert pages, click
   **Create Dependabot security update**. If a PR exists already, the alert
   links to it. If Dependabot posts an error instead, use option B.

2. Check out the PR. Replace `12345` with the PR number. The diff must show
   `$VERSION` or higher:

   ```bash
   PR=12345
   cd ~/Work/uyuni
   gh pr checkout "$PR"
   BRANCH=$(git branch --show-current)
   git diff origin/master...HEAD -- web/package.json
   ```

Dependabot changes only `package.json` and the lockfile. Continue with
[Regenerating the license files](#regenerating-the-license-files). After you
push your own commit, Dependabot no longer rebases this branch.

#### Option B: Your own branch

1. Create the branch from the current `master`. The status output must be
   empty:

   ```bash
   cd ~/Work/uyuni
   git status --short
   git fetch origin master
   git switch --create "$BRANCH" origin/master
   ```

2. Show where `package.json` declares the package:

   ```bash
   jq --arg p "$PACKAGE" '{dependencies: .dependencies[$p],
     devDependencies: .devDependencies[$p], overrides: .overrides[$p]}
     | with_entries(select(.value != null))' web/package.json
   ```

   Each entry is one declaration, for example `"dependencies": "3.4.15"`. If
   the output is `{}`, the package is transitive: follow *Bumping a transitive
   package* below instead of steps 3 and 4.

3. Set the new version in every declaration that step 2 shows. Use the entry
   names from the output, and keep a leading `^` or `~`. For the example above,
   run:

   ```bash
   npm --prefix web pkg set "dependencies.$PACKAGE=$VERSION"
   ```

   If step 2 also shows `overrides`, set both entries in one command instead:

   ```bash
   npm --prefix web pkg set "dependencies.$PACKAGE=$VERSION" \
     "overrides.$PACKAGE=$VERSION"
   ```

4. Update the lockfile and check the result. Every occurrence of the package
   must show `$VERSION` or higher:

   ```bash
   npm --prefix web install --package-lock-only --ignore-scripts
   npm --prefix web ls "$PACKAGE" --all --package-lock-only
   ```

<details>
<summary><b>Bumping a transitive package</b></summary>

A transitive package has no entry in `package.json`. Update it within the range
that its parent allows, then check the result. Every occurrence must show
`$VERSION` or higher:

```bash
npm --prefix web update "$PACKAGE" --package-lock-only --ignore-scripts
npm --prefix web ls "$PACKAGE" --all --package-lock-only
```

If it stays below `$VERSION`, the parent limits it. Add an override, as Uyuni
does for packages such as `brace-expansion`, and update the lockfile again:

```bash
npm --prefix web pkg set "overrides.$PACKAGE=$VERSION"
npm --prefix web install --package-lock-only --ignore-scripts
```

</details>

<details>
<summary><b>Why not <code>npm install</code> or <code>npm update</code>?</b></summary>

npm's standard way to bump a direct dependency is
`npm install "$PACKAGE@$VERSION" --save-exact`. In Uyuni, it has two pitfalls:

- It fails with `EOVERRIDE` for packages that Uyuni also lists in `overrides`
  with a copied version, for example `bootstrap`, `lodash`, and `moment`. npm
  accepts an override for a direct dependency only if both have exactly the
  same version.
- Without `--save-exact`, it turns an exact version such as `"3.4.15"` into a
  range such as `"^3.4.17"`.

The other npm commands do not fit either:

- `npm update` stays within the declared range and does not change
  `package.json`. It cannot move an exact version, and for a range it takes the
  newest version, not the smallest fix.
- `npm audit fix` changes many packages at once, but each PR bumps only one.

`npm pkg set` followed by `npm install --package-lock-only` works in every case.
The [npm script](../automated-scripts/README.md) uses the same approach.

</details>

Never edit `package-lock.json` by hand.

### Regenerating the license files

The production build generates the license files from the installed packages.
Never edit them by hand:

- `web/html/src/vendors/npm.licenses.hash.txt` is the SHA-1 of the lockfile,
  so every bump changes it.
- `npm.licenses.txt` and `npm.licenses.structured.js` in the same directory
  list the license texts and types.
- The build also fills the `License:` line in `web/spacewalk-web.spec`.

1. Install the packages and run the build:

   ```bash
   cd ~/Work/uyuni
   npm --prefix web ci
   npm --prefix web run build
   ```

   After a bump, the build stops with *changes to license and/or spec files
   haven't been committed*. This is expected.

2. Stage the regenerated files and build again. The build now passes:

   ```bash
   git add web/html/src/vendors/ web/spacewalk-web.spec
   npm --prefix web run build
   ```

If the `License:` line in the spec file changed, check that the package's
license really changed, and mention it in the PR description.

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

### Validating the change

1. Run the same checks as the frontend CI. The commands stop at the first
   failure. When all pass, the last line is *All checks passed*:

   ```bash
   cd ~/Work/uyuni &&
   npm --prefix web ci &&
   npm --prefix web run test &&
   npm --prefix web run tsc &&
   npm --prefix web run lint:production &&
   npm --prefix web run sort-package -- --check &&
   npm --prefix web run build &&
   npm --prefix web run build-storybook &&
   git diff --check HEAD &&
   echo "All checks passed"
   ```

2. Confirm that the vulnerability is gone. npm checks the same GitHub
   advisories as Dependabot. The output must be *no known vulnerabilities*:

   ```bash
   npm --prefix web audit --package-lock-only --json \
     | jq --raw-output --arg p "$PACKAGE" \
       '.vulnerabilities[$p] // "no known vulnerabilities"'
   ```

   If it lists advisories instead, open them. Either the new version does not
   fix all of them, or a dependency of the package is still vulnerable.

### Committing and opening the draft PR

1. Review the change. Expect `package.json`, the lockfile, the license files,
   and the changelog file. The lockfile may change only the package and its own
   dependencies:

   ```bash
   cd ~/Work/uyuni
   git status --short
   git diff HEAD -- web/package.json web/package-lock.json
   ```

2. Commit the change:

   ```bash
   git add web/package.json web/package-lock.json \
     web/html/src/vendors/ web/spacewalk-web.spec "$CHANGES"
   git commit --message "Bump $PACKAGE from $OLD to $VERSION"
   ```

3. Push and open the draft PR:

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

4. Wait for CI:

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

When CI passes on the Uyuni PR, backport the change to each product branch in
`SUSE/spacewalk`, currently `Manager-5.1` and `Manager-5.2`.

> [!IMPORTANT]
> **Your local validation is the main check for a backport**
>
> The product branches run little CI. `Manager-5.1` runs no frontend checks,
> and `Manager-5.2` runs only the build, the unit tests, and TypeScript.
> Validate every backport completely before you push it.

1. Set the values for the backport:

   ```bash
   PR=12345              # Uyuni PR number
   PACKAGE=dompurify     # bumped package
   VERSION=3.4.17        # new version
   ```

2. Read the branch and the title of the Uyuni PR. Copy this block unchanged:

   ```bash
   BRANCH=$(gh pr view "$PR" --repo uyuni-project/uyuni \
     --json headRefName --jq .headRefName)
   TITLE=$(gh pr view "$PR" --repo uyuni-project/uyuni \
     --json title --jq .title)
   ```

3. Set the target branch and create the backport branch. The status output
   must be empty:

   ```bash
   TARGET=Manager-5.1
   BACKPORT="backport/uyuni-$PR-$(printf '%s' "$BRANCH" \
     | tr -cs 'A-Za-z0-9._-' '-')-to-$TARGET"
   cd ~/Work/spacewalk
   git status --short
   git fetch origin "$TARGET"
   git fetch https://github.com/uyuni-project/uyuni.git "pull/$PR/head"
   git switch --create "$BACKPORT" "origin/$TARGET"
   ```

4. Apply the commits of the Uyuni PR. If Git reports a conflict, see
   [Resolving backport conflicts](#resolving-backport-conflicts):

   ```bash
   git cherry-pick $(gh pr view "$PR" --repo uyuni-project/uyuni \
     --json commits --jq '.commits[].oid')
   ```

5. Validate the backport. When all checks pass, the last line is
   *All checks passed*:

   ```bash
   cd ~/Work/spacewalk &&
   npm --prefix web ci &&
   npm --prefix web run test &&
   npm --prefix web run tsc &&
   npm --prefix web run lint:production &&
   npm --prefix web run sort-package -- --check &&
   npm --prefix web run build &&
   npm --prefix web run build-storybook &&
   git diff --check "origin/$TARGET...HEAD" &&
   echo "All checks passed"
   ```

   If the build stops because it regenerated license files, add them to the
   backport commit, then run the validation again:

   ```bash
   git add web/html/src/vendors/ web/spacewalk-web.spec
   git commit --amend --no-edit
   ```

6. Confirm that the vulnerability is gone. The output must be
   *no known vulnerabilities*:

   ```bash
   npm --prefix web audit --package-lock-only --json \
     | jq --raw-output --arg p "$PACKAGE" \
       '.vulnerabilities[$p] // "no known vulnerabilities"'
   ```

7. Push the branch and open the draft PR. When `gh` asks for the description,
   add a line `Backport of` with the link to the Uyuni PR:

   ```bash
   git push --set-upstream origin "$BACKPORT"
   gh pr create --repo SUSE/spacewalk --draft \
     --base "$TARGET" --head "$BACKPORT" --title "${TARGET#Manager-} - $TITLE"
   ```

8. Repeat from step 3 with `TARGET=Manager-5.2`.

### Resolving backport conflicts

During a cherry-pick, `--ours` is the target branch and `--theirs` is the Uyuni
commit. Resolve conflicts like this:

| Conflicting file | Resolution |
| --- | --- |
| `web/package.json`, `web/package-lock.json` | Take the target version, then repeat steps 2–4 of [option B](#option-b-your-own-branch). Never merge the lockfile by hand. |
| License files, `web/spacewalk-web.spec` | Take the target version, then regenerate them as in [Regenerating the license files](#regenerating-the-license-files). |
| Any other file | Resolve it by hand so that it fits the target branch. |

1. List the conflicting files:

   ```bash
   git diff --name-only --diff-filter=U
   ```

2. Take the target version of a conflicting generated file, for example the
   lockfile. Then repeat the npm steps from the table:

   ```bash
   git checkout --ours web/package-lock.json
   ```

3. Stage the resolved files and continue:

   ```bash
   git add --update
   git cherry-pick --continue
   ```

If Git reports an empty commit, its change exists on the target already. Skip
it with `git cherry-pick --skip`.

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

If the Uyuni PR changes during the review, update both backports: repeat
[Backporting to the product branches](#backporting-to-the-product-branches).
In step 3, use `git switch --force-create`, and in step 7, push with
`git push --force-with-lease`.

## Troubleshooting

| Problem | Solution |
| --- | --- |
| The build stops with *changes to license and/or spec files haven't been committed* | Expected after a bump. Stage the files and build again, see [Regenerating the license files](#regenerating-the-license-files). |
| The build fails with *Currently installed … does not satisfy expected version* | Run `npm --prefix web ci`, then build again. |
| `npm ci` claims that no `package-lock.json` exists, although it is there | The message hides the real error, usually an override that conflicts with a direct dependency. Run `npm --prefix web install --package-lock-only --ignore-scripts` to see it. Restore both files with `git restore web/package.json web/package-lock.json`, then repeat steps 2–4 of [option B](#option-b-your-own-branch). |
| Dependabot posts an error on the alert | The package is often transitive or limited by its parent. Use option B. |
| Pushing to the Dependabot branch fails | You need write access to `uyuni-project/uyuni`. Otherwise, use option B. |
| The PR shows no frontend checks | The license files are not part of the PR. Regenerate them, commit them, and push. |
| `changelog_test` fails | Check the line length and the `bsc#` numbers, then check *Re-run test "changelog_test"* in the PR description. |
| GitHub marks a commit as *Unverified* | Set up commit signing, then re-sign with `git rebase --force-rebase --gpg-sign origin/master` and push with `git push --force-with-lease`. |
| GitHub reports conflicts with `master` | Run `git rebase origin/master`. Resolve conflicts as in [Resolving backport conflicts](#resolving-backport-conflicts), with `git rebase --continue` instead of `git cherry-pick --continue`. Push with `git push --force-with-lease`. |
| The cherry-pick fails on a merge commit | The Uyuni PR contains a merge commit. Rebase the Uyuni branch on `master` instead of merging `master` into it. |

## Lessons learned

- `npm update` on a transitive package can choose a newer version than the
  minimum fix. Always check the resolved version in the lockfile.
- A direct dependency can also be pinned in `overrides`. Update both.
- A core tool bump can require a companion bump. For example, `@babel/core`
  7.29.6 required `@babel/helpers` 7.29.2.
- A successful install is not enough. The build and the unit tests can reveal
  API changes.
- License file changes can be much larger than the bump itself, when one
  transitive package replaces another.
- An alert can receive its CVE after it was opened. Check the advisory and the
  SUSE CVE page again before you write the changelog.

## More information

- [Open npm alerts of Uyuni](https://github.com/uyuni-project/uyuni/security/dependabot?q=is%3Aopen+ecosystem%3Anpm)
- [Uyuni changelog guidelines](https://github.com/uyuni-project/uyuni/wiki/Contributing#changelogs)
- [How to branch and merge properly in Uyuni](https://github.com/uyuni-project/uyuni/wiki/How-to-branch-and-merge-properly)
- [GitHub: Viewing and updating Dependabot alerts](https://docs.github.com/en/code-security/dependabot/dependabot-alerts/viewing-and-updating-dependabot-alerts)
- [SUSE CVE database](https://www.suse.com/security/cve/)
- [npm: overrides](https://docs.npmjs.com/cli/configuring-npm/package-json#overrides)
