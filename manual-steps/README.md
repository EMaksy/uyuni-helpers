# Bumping and backporting npm dependencies by hand

This guide shows how to fix an npm security alert in Uyuni without helper
scripts or AI. You find the alert, choose the version, and bump the dependency.
Then you regenerate the license files, add a changelog, validate, and open a
draft pull request (PR). Finally, you backport the fix to the SUSE Manager
product branches.

Work through this guide by hand at least once. The
[scripts](../automated-scripts/README.md) and the [AI agent](../agentic-skills/README.md)
automate the same steps, and you need to understand what they do.

- [Bumping and backporting npm dependencies by hand](#bumping-and-backporting-npm-dependencies-by-hand)
  - [Requirements](#requirements)
  - [Finding the alerts to fix](#finding-the-alerts-to-fix)
  - [Choosing the target version](#choosing-the-target-version)
  - [Bumping the dependency](#bumping-the-dependency)
    - [Setting the variables](#setting-the-variables)
    - [Creating the Uyuni change](#creating-the-uyuni-change)
      - [Using a Dependabot security update](#using-a-dependabot-security-update)
      - [Bumping manually](#bumping-manually)
    - [Regenerating the license files](#regenerating-the-license-files)
    - [Adding the changelog](#adding-the-changelog)
    - [Validating the change](#validating-the-change)
    - [Reviewing and committing](#reviewing-and-committing)
    - [Opening the draft pull request](#opening-the-draft-pull-request)
  - [Backporting to the product branches](#backporting-to-the-product-branches)
    - [Resolving backport conflicts](#resolving-backport-conflicts)
  - [Getting the reviews](#getting-the-reviews)
  - [Troubleshooting](#troubleshooting)
  - [Lessons learned](#lessons-learned)
  - [More information](#more-information)

## Requirements

You need the following access and tools:

- Access to the Dependabot alerts of `uyuni-project/uyuni`. GitHub shows them
  only to users with write access or a security role.
- Push access to `uyuni-project/uyuni` and to `SUSE/spacewalk`.
- Git, the GitHub CLI (`gh`), and `jq`.
- Node.js and npm in the versions from `engines` in `web/package.json`,
  currently Node.js 22 and npm 10 or later.

All commands assume this directory layout:

```text
~/Work/
├── uyuni/        # clone of uyuni-project/uyuni
└── spacewalk/    # clone of SUSE/spacewalk
```

If you do not have the clones yet, create them:

```bash
git clone git@github.com:uyuni-project/uyuni.git ~/Work/uyuni
```

```bash
git clone git@github.com:SUSE/spacewalk.git ~/Work/spacewalk
```

Log in to GitHub with the GitHub CLI:

```bash
gh auth login --hostname github.com
```

## Finding the alerts to fix

Dependabot lists the vulnerable npm packages of the Uyuni frontend. Fix the
most severe alerts first, and prefer packages that cause several alerts: one
bump can close all of them.

1. Open the [open npm alerts of Uyuni](https://github.com/uyuni-project/uyuni/security/dependabot?q=is%3Aopen+ecosystem%3Anpm).
2. Look for alerts with **Critical** severity first, then **High**.
3. Open the **Package** filter. The number next to each package is its count of
   open alerts.
4. Choose one package. Bump one dependency at a time: one package per branch
   and per PR.

You can get the same overview in the terminal. This command lists each package
with its number of open alerts and their severities:

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

Example output:

```text
5       dompurify       critical,high,low
5       fast-uri        low,medium
2       serialize-javascript    high,low
```

## Choosing the target version

Choose the smallest version that fixes every open alert of the package. A small
step keeps the risk of breaking changes low.

1. Store the package name in a variable:

   ```bash
   PACKAGE=dompurify
   ```

2. List the open alerts of the package with the first fixed version of each:

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

   The columns are alert number, severity, CVE, and first fixed version.
   Example output:

   ```text
   593     critical        no CVE  3.4.17
   592     high    no CVE  3.4.17
   547     low     no CVE  3.4.16
   ```

3. Take the highest fixed version. It is the smallest version that fixes all
   alerts. Store it:

   ```bash
   VERSION=3.4.17
   ```

4. Confirm that npm publishes this version. The command prints the version if
   it exists:

   ```bash
   npm view "$PACKAGE@$VERSION" version
   ```

5. Confirm the fix in the primary sources. Open each advisory from its alert
   page, then check the package's GitHub releases or changelog for the fix.

6. Show the current version and how the package enters the dependency tree:

   ```bash
   npm --prefix ~/Work/uyuni/web ls "$PACKAGE" --all
   ```

   A package at the top level is a *direct* dependency. A package that appears
   only below another package is a *transitive* dependency.

7. Store the current version:

   ```bash
   OLD=3.4.15
   ```

8. Find where Uyuni uses the package, to confirm that no code changes are
   needed. For a major version bump, read the release notes between both versions. Check
   whether breaking changes affect the code locations you found.

9. For each CVE, open its page in the
   [SUSE CVE database](https://www.suse.com/security/cve/) and note the SUSE
   Bugzilla (`bsc#`) number.

10. Store the CVE and Bugzilla references for the PR title. Leave the value
    empty if the alerts have no CVE:

    ```bash
    REFS="CVE-2026-104844, bsc#1284190"
    ```

> [!TIP]
> **Research faster with AI**
>
> An AI assistant can summarize the advisories and find the release that
> contains the fix. Verify every claim against the advisory, the GitHub
> repository, and npm. See [Researching with an agent](../agentic-skills/README.md#researching-the-next-bump).

These cases need special handling:

| Situation | What to do |
| --- | --- |
| No fixed version exists | Do not bump. Report the exposure to the security champion. |
| The alert has no CVE yet | Write only the version line in the changelog. Name the GHSA in the PR description and ask the security champion. |
| A CVE has no SUSE Bugzilla entry | Ask Security for one before you write the changelog. |
| An open PR already fixes the alert | Continue on that PR instead of opening a new one. |

## Bumping the dependency

This part creates the Uyuni change, from the branch to the draft PR. It
starts by setting the variables that all its steps use, so you can start it
in a new terminal.

### Setting the variables

The commands use shell variables, so you can copy and paste them unchanged.
All steps of this part use the variables from this section.

1. Set the values that you found in the previous section, and your changelog
   identifier. For `AUTHOR`, use the same identifier as in your earlier
   changelog files, usually your GitHub or SUSE user name:

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
> Variables exist only in the current terminal. In a new terminal, set them
> again.

### Creating the Uyuni change

Try a Dependabot security update first: Dependabot then creates the branch and
the bump for you. If Dependabot cannot do it, bump the package manually.

#### Using a Dependabot security update

1. Open one of the package's alerts.
2. Click **Create Dependabot security update** at the top of the alert page. If
   a PR exists already, the alert links to it instead.
3. Wait until Dependabot opens the PR. If Dependabot posts an error on the
   alert, continue with [Bumping manually](#bumping-manually).
4. Store the PR number:

   ```bash
   PR=12345
   ```

5. Change to your Uyuni clone:

   ```bash
   cd ~/Work/uyuni
   ```

6. Check out the PR:

   ```bash
   gh pr checkout "$PR"
   ```

7. Use the Dependabot branch as your branch:

   ```bash
   BRANCH=$(git branch --show-current)
   ```

8. Check that Dependabot chose at least `$VERSION`:

   ```bash
   git diff origin/master...HEAD -- web/package.json
   ```

Dependabot changes only `package.json` and the lockfile. You add the license
files and the changelog in the next sections.

> [!NOTE]
> After you push your own commit to a Dependabot branch, Dependabot no longer
> rebases that branch automatically.

#### Bumping manually

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

5. Show how `package.json` declares the package, including `overrides`:

   ```bash
   grep --line-number "\"$PACKAGE\"" web/package.json
   ```

6. Update the package with the command that matches the declaration.

   - Exact version, for example `"3.4.15"`:

     ```bash
     npm --prefix web install "$PACKAGE@$VERSION" --save-exact \
       --package-lock-only --ignore-scripts
     ```

   - Range, for example `"^3.4.15"`:

     ```bash
     npm --prefix web install "$PACKAGE@$VERSION" \
       --package-lock-only --ignore-scripts
     ```

   - Transitive only, with no entry in `package.json`:

     ```bash
     npm --prefix web update "$PACKAGE" --package-lock-only --ignore-scripts
     ```

7. Check the resolved version in the lockfile:

   ```bash
   npm --prefix web ls "$PACKAGE" --all --package-lock-only
   ```

> [!IMPORTANT]
> **Overrides must match**
>
> If the package also appears in `overrides`, npm fails or keeps the old
> version. Set the override to the new version first, then run the install
> command again:
>
> ```bash
> npm --prefix web pkg set "overrides.$PACKAGE=$VERSION"
> ```
>
> If `npm update` cannot reach the fixed version of a transitive package, the
> parent package limits it. Add the same override, as Uyuni already does for
> packages such as `brace-expansion`. Then run
> `npm --prefix web install --package-lock-only --ignore-scripts`.

Never edit `package-lock.json` by hand.

### Regenerating the license files

The production build generates the license files from the installed packages.
Never edit them by hand.

| File | Content |
| --- | --- |
| `web/html/src/vendors/npm.licenses.hash.txt` | SHA-1 of `web/package-lock.json`. It is unique for every lockfile, so every bump changes it. |
| `web/html/src/vendors/npm.licenses.txt` | License texts of all packages, with name and version |
| `web/html/src/vendors/npm.licenses.structured.js` | List of all license types |
| `web/spacewalk-web.spec` | `License:` line of the `spacewalk-html` package, filled from the list |

When the hash no longer matches the lockfile, the build regenerates all of
these files.

1. Install exactly what the lockfile specifies:

   ```bash
   npm --prefix web ci
   ```

2. Run the production build:

   ```bash
   npm --prefix web run build
   ```

   After a dependency change, the build can stop with *It seems changes to
   license and/or spec files haven't been committed*. This is expected.

3. Stage the regenerated files:

   ```bash
   git add web/html/src/vendors/ web/spacewalk-web.spec
   ```

4. Run the build again. It now finishes without errors:

   ```bash
   npm --prefix web run build
   ```

If `web/spacewalk-web.spec` changed, a package changed its license. Check that
the new license is correct and mention it in the PR description.

### Adding the changelog

Every bump needs a changelog fragment in `web/`. It lists the version change and
one entry per CVE with its SUSE Bugzilla number.

1. Create the fragment with the version line:

   ```bash
   echo "- Update $PACKAGE from version $OLD to $VERSION" > "$CHANGES"
   ```

2. Add one entry per CVE with a text editor:

   ```bash
   ${EDITOR:-vi} "$CHANGES"
   ```

   The finished fragment looks like this:

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

Follow these rules:

- Indent continuation lines with two spaces.
- Keep every line at 67 characters or less, including wrapped CVE summaries.
- Add one entry for each CVE, and verify each `bsc#` number.
- Keep the version line, even when CVE entries are present.

### Validating the change

Run the same checks as the frontend CI. Run each command from `~/Work/uyuni`
and fix any failure before you continue.

1. Install exactly what the lockfile specifies:

   ```bash
   npm --prefix web ci
   ```

2. Check the installed version and its place in the tree:

   ```bash
   npm --prefix web ls "$PACKAGE" --all
   ```

3. Run the unit tests:

   ```bash
   npm --prefix web run test
   ```

4. Check the TypeScript types:

   ```bash
   npm --prefix web run tsc
   ```

5. Run the production lint:

   ```bash
   npm --prefix web run lint:production
   ```

6. Check the key order in `package.json`:

   ```bash
   npm --prefix web run sort-package -- --check
   ```

7. Run the production build:

   ```bash
   npm --prefix web run build
   ```

8. Check for whitespace errors in your changes:

   ```bash
   git diff --check HEAD
   ```

If Storybook uses the package, also build Storybook:

```bash
npm --prefix web run build-storybook
```

### Reviewing and committing

Review the complete change before you commit it.

1. List the changed files:

   ```bash
   git status --short
   ```

2. Review the declaration change:

   ```bash
   git diff HEAD -- web/package.json
   ```

3. Review the lockfile change:

   ```bash
   git diff HEAD -- web/package-lock.json
   ```

Check that:

- every declaration, override, and lockfile entry uses the new version;
- the lockfile changes only the package and its own dependencies;
- the license files and the changelog fragment are included;
- nothing under `web/html/src/dist/` is included.

4. Stage the change:

   ```bash
   git add web/package.json web/package-lock.json \
     web/html/src/vendors/ web/spacewalk-web.spec "$CHANGES"
   ```

5. Commit it:

   ```bash
   git commit --message "Bump $PACKAGE from $OLD to $VERSION"
   ```

### Opening the draft pull request

Open the PR as a draft and wait until CI passes.

**For your own branch:**

1. Push the branch:

   ```bash
   git push --set-upstream origin "$BRANCH"
   ```

2. Create the draft PR. When `gh` asks for the description, name the fixed
   advisories and the checks that passed:

   ```bash
   gh pr create --repo uyuni-project/uyuni --draft \
     --base master --head "$BRANCH" --title "$TITLE"
   ```

3. Store the PR number:

   ```bash
   PR=$(gh pr view --json number --jq .number)
   ```

**For a Dependabot branch:**

1. Push your commit to the Dependabot branch:

   ```bash
   git push
   ```

2. Convert the PR to a draft:

   ```bash
   gh pr ready "$PR" --undo
   ```

3. Add the CVE and Bugzilla references to the title:

   ```bash
   gh pr edit "$PR" --title "$TITLE"
   ```

**For both:** wait for CI. All checks must pass, including `changelog_test`
and `frontend_checks`:

```bash
gh pr checks "$PR" --repo uyuni-project/uyuni --watch
```

## Backporting to the product branches

When CI passes on the Uyuni PR, backport the change to each maintained product
branch in `SUSE/spacewalk`. Currently these are `Manager-5.1` and `Manager-5.2`.
This section sets its own variables, so you can start it in a new terminal.

1. Set the Uyuni PR number and the bumped package:

   ```bash
   PR=12345              # Uyuni PR number
   PACKAGE=dompurify     # bumped package, used for validation
   VERSION=3.4.17        # new version, used to resolve conflicts
   ```

2. Read the branch name and the title of the Uyuni PR:

   ```bash
   BRANCH=$(gh pr view "$PR" --repo uyuni-project/uyuni \
     --json headRefName --jq .headRefName)
   TITLE=$(gh pr view "$PR" --repo uyuni-project/uyuni \
     --json title --jq .title)
   ```

3. Set the target branch and derive the backport branch name. The name is the
   same as the one the backport script creates:

   ```bash
   TARGET=Manager-5.1
   BACKPORT="backport/uyuni-$PR-$(printf '%s' "$BRANCH" \
     | tr -cs 'A-Za-z0-9._-' '-')-to-$TARGET"
   ```

4. Change to your Spacewalk clone:

   ```bash
   cd ~/Work/spacewalk
   ```

5. Check that the working tree is clean:

   ```bash
   git status --short --branch
   ```

6. Fetch the target branch:

   ```bash
   git fetch origin "$TARGET"
   ```

7. Fetch the commits of the Uyuni PR:

   ```bash
   git fetch https://github.com/uyuni-project/uyuni.git "pull/$PR/head"
   ```

8. Create the backport branch from the target branch:

   ```bash
   git switch --create "$BACKPORT" "origin/$TARGET"
   ```

9. Apply the commits of the Uyuni PR in order:

   ```bash
   git cherry-pick $(gh pr view "$PR" --repo uyuni-project/uyuni \
     --json commits --jq '.commits[].oid')
   ```

   If Git reports a conflict, resolve it as described in
   [Resolving backport conflicts](#resolving-backport-conflicts).

10. Validate the backport with steps 1–7 of
    [Validating the change](#validating-the-change). Product branches have
    their own dependency trees, so a passing Uyuni PR does not prove that the
    backport works. Then check the backport commits for whitespace errors:

    ```bash
    git diff --check "origin/$TARGET...HEAD"
    ```

    If the build regenerated license files, stage them and add them to the
    last commit:

    ```bash
    git add web/html/src/vendors/ web/spacewalk-web.spec
    ```

    ```bash
    git commit --amend --no-edit
    ```

11. Push the backport branch:

    ```bash
    git push --set-upstream origin "$BACKPORT"
    ```

12. Create the draft PR. When `gh` asks for the description, add a line
    `Backport of` followed by the link to the Uyuni PR:

    ```bash
    gh pr create --repo SUSE/spacewalk --draft \
      --base "$TARGET" --head "$BACKPORT" --title "${TARGET#Manager-} - $TITLE"
    ```

13. Repeat from step 3 with `TARGET=Manager-5.2`.

14. Add both Spacewalk PR links to the `Port(s):` line of the Uyuni PR
    description.

### Resolving backport conflicts

During a cherry-pick, `--ours` is the target branch and `--theirs` is the Uyuni
commit. Resolve conflicts in these files as follows:

| Conflicting file | Resolution |
| --- | --- |
| `web/package.json`, `web/package-lock.json` | Take the target branch version, then repeat the npm command from [Bumping manually](#bumping-manually). Never merge the lockfile by hand. |
| License files in `web/html/src/vendors/`, `web/spacewalk-web.spec` | Take the target branch version, then regenerate them as in [Regenerating the license files](#regenerating-the-license-files). |
| Any other file | Resolve it by hand so that it fits the target branch. |

1. List the conflicting files:

   ```bash
   git diff --name-only --diff-filter=U
   ```

2. Take the target branch version of a conflicting generated file, for example
   the lockfile:

   ```bash
   git checkout --ours web/package-lock.json
   ```

3. Repeat the npm command and regenerate the license files as described in the
   table.

4. Stage the resolved files:

   ```bash
   git add --update
   ```

5. Continue the cherry-pick:

   ```bash
   git cherry-pick --continue
   ```

   If Git reports the commit as empty, its change already exists on the target
   branch. Skip it:

   ```bash
   git cherry-pick --skip
   ```

## Getting the reviews

Ask for reviews when CI passes on the Uyuni PR. This section sets its own
variables, so you can start it in a new terminal.

1. Set the Uyuni PR number:

   ```bash
   PR=12345
   ```

2. Mark the Uyuni PR ready for review:

   ```bash
   gh pr ready "$PR" --repo uyuni-project/uyuni
   ```

   GitHub then requests a review from the frontend squad
   (`uyuni-project/frontend`), because the PR changes files in `web/html/`.

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

If the Uyuni PR changes during the review, update both backports. Repeat
[Backporting to the product branches](#backporting-to-the-product-branches)
with two changes: in step 8, use `git switch --force-create`, and in step 11,
push with `git push --force-with-lease`.

## Troubleshooting

| Problem | Solution |
| --- | --- |
| The build stops with *changes to license and/or spec files haven't been committed* | Expected after a bump. Stage the files and build again, see [Regenerating the license files](#regenerating-the-license-files). |
| The build fails with *Currently installed … does not satisfy expected version* | Run `npm --prefix web ci`, then build again. |
| `npm ci` fails because the lockfile does not match `package.json` | Repeat the npm command from [Bumping manually](#bumping-manually). |
| Dependabot posts an error on the alert | The package is often transitive or blocked by a parent package. Bump it manually. |
| Pushing to the Dependabot branch fails | You need write access to `uyuni-project/uyuni`. Otherwise, bump manually on your own branch. |
| `changelog_test` fails | Check the line length and the `bsc#` numbers. Then check *Re-run test "changelog_test"* in the PR description. |
| The cherry-pick fails on a merge commit | The Uyuni PR contains a merge commit. Rebase the Uyuni branch on `master` instead of merging `master` into it. |

## Lessons learned

These points come from earlier bumps:

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
