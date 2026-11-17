# Automating the workflow with an AI agent

An AI agent can do the research, prepare the bump, and backport it for you. It
follows the skills in this directory and uses the
[automated scripts](../automated-scripts/README.md). You stay responsible for
the result: you check the agent's work, watch CI, and get the reviews.

The agent automates the [manual steps](../manual-steps/README.md). Read that
guide first, so you can judge what the agent does.

- [Automating the workflow with an AI agent](#automating-the-workflow-with-an-ai-agent)
  - [Requirements](#requirements)
  - [Making the skills available](#making-the-skills-available)
  - [Researching the next bump](#researching-the-next-bump)
  - [Preparing the bump](#preparing-the-bump)
  - [Backporting with the agent](#backporting-with-the-agent)
  - [Checking the agent's work](#checking-the-agents-work)
  - [Tips](#tips)

## Requirements

You need the following:

- An AI agent that can run commands and edit files in your clones, for example
  Claude Code, GitHub Copilot in agent mode, or Gemini CLI.
- Access to the Dependabot alerts of `uyuni-project/uyuni`, and push access to
  `uyuni-project/uyuni` and `SUSE/spacewalk`. The agent works with your Git and
  GitHub CLI logins.
- Git, the GitHub CLI (`gh`), `jq`, Node.js 22, and npm 10 or later.
- Clones of both repositories in `~/Work/uyuni` and `~/Work/spacewalk`. If
  your clones are in another place, adjust these paths in the requests.
- Git set up to sign your commits, because the agent commits with your Git
  configuration. Check it with `git config --get commit.gpgsign`, which prints
  `true`. To set it up, see
  [GitHub: Signing commits](https://docs.github.com/en/authentication/managing-commit-signature-verification/signing-commits).
- The scripts, installed as described in
  [Installing the scripts](../automated-scripts/README.md#installing-the-scripts).
  The skills call them.

## Making the skills available

A skill is a Markdown file with instructions for the agent: what to check,
which commands to run, and when to stop and ask.

| Skill | Purpose |
| --- | --- |
| [`uyuni-npm-security-bump`](uyuni-npm-security-bump/SKILL.md) | Research an alert, choose the version, bump the package, add the changelog, regenerate the license files, validate, and prepare the PR |
| [`uyuni-backport`](uyuni-backport/SKILL.md) | Build, validate, and publish the backports, and resolve conflicts |

Every agent can use a skill when you name its file in the request. All example
requests in this guide do that.

Claude Code can also find the skills automatically. To enable this, link them
into your personal skills directory:

1. Create the directory:

   ```bash
   mkdir -p ~/.claude/skills
   ```

2. Link the security bump skill:

   ```bash
   ln -s ~/Work/uyuni-helpers/agentic-skills/uyuni-npm-security-bump \
     ~/.claude/skills/
   ```

3. Link the backport skill:

   ```bash
   ln -s ~/Work/uyuni-helpers/agentic-skills/uyuni-backport \
     ~/.claude/skills/
   ```

For other agents, check their documentation for skill or instruction file
support.

## Researching the next bump

Let the agent find the next package to bump and the version that fixes it. Start
the agent in `~/Work/uyuni` and send this request:

```text
Read ~/Work/uyuni-helpers/agentic-skills/uyuni-npm-security-bump/SKILL.md
List the open npm Dependabot alerts of uyuni-project/uyuni, grouped by package,
with their severities. Recommend the next package: critical first, then the one
that closes the most alerts. For that package, find the smallest version that
fixes all its alerts, and confirm the fix in the advisories, the GitHub
releases, and npm. Find the SUSE Bugzilla number of each CVE. Show where Uyuni
uses the package and whether the bump needs code changes.
Do not change any files. Link every source.
```

Open the source links and check the result before you continue. Compare it with
[Choosing the target version](../manual-steps/README.md#choosing-the-target-version).

## Preparing the bump

Let the agent prepare the bump for one package. Replace `PACKAGE` and `VERSION`
in the request:

```text
Read and follow
~/Work/uyuni-helpers/agentic-skills/uyuni-npm-security-bump/SKILL.md
to bump PACKAGE to VERSION in ~/Work/uyuni.
Use a Dependabot security update if one exists, otherwise create the branch
from origin/master. Add the changelog, regenerate the license files, and run
the validation. Do not commit or push. Report each check and its result.
```

When the agent asks you to create a Dependabot security update, click
**Create Dependabot security update** on the alert page.

Review the result as in
[Committing and opening the draft PR](../manual-steps/README.md#committing-and-opening-the-draft-pr).
Then commit, push, and open the draft PR yourself. Alternatively, let the agent
do it:

```text
Commit the reviewed files, push the branch, and open a draft Uyuni PR.
Then wait for CI and report the result of every check.
```

## Backporting with the agent

When CI passes on the Uyuni PR, let the agent backport it. The agent builds and
validates each backport locally before it publishes it. Replace `NUMBER` with
the Uyuni PR number:

```text
Read and follow
~/Work/uyuni-helpers/agentic-skills/uyuni-backport/SKILL.md
to backport Uyuni PR #NUMBER to Manager-5.1 and then Manager-5.2.
Build and validate each backport locally before you publish it.
```

Before the Uyuni PR is approved, add this line, but only if you are sure that
the PR is merged as it is:

```text
Use --allow-unapproved.
```

If the backport stops with a conflict, ask the agent to resolve it. Replace
`PATH` with the worktree path that the script printed:

```text
The backport stopped with a conflict in the worktree PATH. Resolve it as
described in the "Recover conflicts" section of the uyuni-backport skill.
Explain each resolution before you continue the cherry-pick.
```

## Checking the agent's work

The agent makes mistakes, and it can be confident about them. Check these
points yourself:

- The chosen version fixes every alert of the package. Open the advisory links.
- Every CVE and `bsc#` number matches the
  [SUSE CVE database](https://www.suse.com/security/cve/). Never accept a
  number that you cannot find there.
- `package.json` and the lockfile change only the package and its own
  dependencies.
- The regenerated license files are part of the commit.
- No changelog line is longer than 67 characters.
- `npm audit` reports no known vulnerability for the package anymore.
- CI passes on the Uyuni PR, and the list contains `changelog_test` and the
  four `frontend_*` checks. These run only when the license files are part of
  the PR.
- The agent validated each backport locally, including Storybook. The product
  branches run little CI, so this is the main check.
- Each Spacewalk PR targets the right branch, is a draft, and has a title such
  as `5.1 - Bump …`.

The agent's checks do not replace the reviews by the security champion and the
frontend squad. Get them as in [Getting the reviews](../manual-steps/README.md#getting-the-reviews).

## Tips

- Bump one package per request. Smaller changes are easier to review.
- Say which external steps the agent may perform: commit, push, or open a PR.
  The skills do nothing external unless you ask.
- If the agent cannot run commands, for example in a web chat, paste the skill
  and the command output. Then run the commands it suggests yourself.
- If the agent gets stuck, continue by hand with the
  [manual guide](../manual-steps/README.md) or the [scripts](../automated-scripts/README.md).
