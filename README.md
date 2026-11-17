# uyuni-helpers

Guides and scripts for fixing npm security alerts in Uyuni and backporting the
fixes to the SUSE Manager product branches.

## The workflow in short

Keep this workflow in mind. The guides explain every step in detail.

1. Open the [open npm alerts of Uyuni](https://github.com/uyuni-project/uyuni/security/dependabot?q=is%3Aopen+ecosystem%3Anpm).
2. Start with the critical alerts. Use the **Package** filter to find a package
   that causes several alerts.
3. Find the smallest version that fixes all alerts of that package. Confirm the
   fix in the advisory, on GitHub, and on npm. AI speeds up this research.
4. Bump one package at a time. Use a Dependabot security update if possible,
   otherwise create your own branch from `master`.
5. Add a changelog entry for the version change and for each CVE with its
   `bsc#` number.
6. Run the npm validation. The build regenerates the license files.
7. Review `package.json`, `package-lock.json`, and how Uyuni uses the package.
8. Open a draft PR and wait until CI passes.
9. Backport the change to `Manager-5.1` and `Manager-5.2` in `SUSE/spacewalk`.
   Resolve conflicts there.
10. Wait for the reviews by the security champion and the frontend squad.

## Choosing a guide

All three guides cover the same workflow. Work through the manual guide once,
even if you use the scripts or an agent later.

| Guide | Use it to |
| --- | --- |
| [1. By hand](1-manual/README.md) | Understand every step and run each command yourself |
| [2. With scripts](2-scripts/README.md) | Validate the bump and create the backports with two helper scripts |
| [3. With an AI agent](3-ai-agent/README.md) | Let an agent research, prepare, and backport, while you check the result |

## Good to know

- **License files are generated.** `web/html/src/vendors/npm.licenses.hash.txt`
  is the SHA-1 of the lockfile, so every bump changes it. The production build
  regenerates it together with `npm.licenses.txt`. Never edit them by hand.
- **One package per PR.** Small changes are easier to review and to backport.
- **Draft first.** Keep PRs as drafts until CI passes.
- **Copy and paste.** The commands use shell variables that you set once, so
  you can paste them unchanged.

## Requirements

You need access to the Dependabot alerts of `uyuni-project/uyuni`, and push
access to `uyuni-project/uyuni` and `SUSE/spacewalk`. You also need Git, the
GitHub CLI, `jq`, Node.js 22, and npm 10 or later. For details, see the
[manual requirements](1-manual/README.md#requirements).

## Repository layout

```text
uyuni-helpers/
├── 1-manual/       # guide: the workflow by hand
├── 2-scripts/      # guide, reference, and the two helper scripts
└── 3-ai-agent/     # guide and the skills for AI agents
```

## More information

- [Uyuni changelog guidelines](https://github.com/uyuni-project/uyuni/wiki/Contributing#changelogs)
- [GitHub: Viewing and updating Dependabot alerts](https://docs.github.com/en/code-security/dependabot/dependabot-alerts/viewing-and-updating-dependabot-alerts)
- [SUSE CVE database](https://www.suse.com/security/cve/)
