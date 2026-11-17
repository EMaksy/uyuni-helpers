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
6. Run the npm validation and confirm that the vulnerability is gone. The build
   regenerates the license files.
7. Review `package.json`, `package-lock.json`, and how Uyuni uses the package.
8. Open a draft PR and wait until CI passes.
9. Backport the change to `Manager-5.1` and `Manager-5.2` in `SUSE/spacewalk`.
   Resolve conflicts there, and validate locally before you push.
10. Wait for the reviews by the security champion and the frontend squad. A
    reviewer then merges the PRs.

## Choosing a guide

All three guides cover the same workflow. Work through the manual steps once,
even if you use the scripts or an agent later.

| Guide | Use it to |
| --- | --- |
| [Manual steps](manual-steps/README.md) | Understand every step and run each command yourself |
| [Automated scripts](automated-scripts/README.md) | Validate the bump and create the backports with two helper scripts |
| [Agentic skills](agentic-skills/README.md) | Let an AI agent research, prepare, and backport, while you check the result |

## Good to know

- **License files are generated.** `web/html/src/vendors/npm.licenses.hash.txt`
  is the SHA-1 of the lockfile, so every bump changes it. The production build
  regenerates it together with `npm.licenses.txt`. Never edit them by hand.
- **Frontend CI needs the license files.** The frontend checks run only when
  files in `web/html/src/` change. A Dependabot PR has none until you push the
  regenerated license files.
- **One package per PR.** Small changes are easier to review and to backport.
- **Draft first.** Keep PRs as drafts until CI passes.
- **Copy and paste.** The commands use shell variables. Each part of a guide
  sets the variables it needs, so you can paste the commands unchanged.

## Requirements

You need access to the Dependabot alerts of `uyuni-project/uyuni`, and push
access to `uyuni-project/uyuni` and `SUSE/spacewalk`. You also need Git set up
to sign your commits, the GitHub CLI, `jq`, Node.js 22, and npm 10 or later.
For details, see the [manual requirements](manual-steps/README.md#requirements).

## Repository layout

```text
uyuni-helpers/
├── manual-steps/         # guide: the workflow by hand
├── automated-scripts/    # guide, reference, and the two helper scripts
├── agentic-skills/       # guide and the skills for AI agents
└── LICENSE               # MIT License
```

## More information

- [Uyuni changelog guidelines](https://github.com/uyuni-project/uyuni/wiki/Contributing#changelogs)
- [GitHub: Viewing and updating Dependabot alerts](https://docs.github.com/en/code-security/dependabot/dependabot-alerts/viewing-and-updating-dependabot-alerts)
- [SUSE CVE database](https://www.suse.com/security/cve/)

## License

This repository is available under the [MIT License](LICENSE). You can use,
change, and share it freely, as long as you keep the license notice.
