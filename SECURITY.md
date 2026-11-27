# Security Policy

## Supported Versions

Security fixes apply to the latest commit on the `main` branch.

| Branch / Version | Supported |
| :--- | :--- |
| `main` (latest) | Yes |
| Older commits | No |

## Reporting a Vulnerability

Because these scripts invoke privileged commands (`sudo`, `pacman`, `paru`/`yay`, `timeshift`, `fstrim`), please **do not** open a public GitHub issue for security vulnerabilities.

Instead, report vulnerabilities privately through GitHub Security Advisories:

- **Private Advisory**: [Report a vulnerability on GitHub](https://github.com/priyankparan/System-Scripts/security/advisories/new)

### What to Include
- Script name and line/function affected (`Scripts/update.sh` or `Scripts/sysedit.sh`)
- Steps or inputs that trigger the issue (e.g. quoting/globbing bug, unintended path deletion, privilege escalation)
- Expected vs. actual behavior

### Response Timeline
- **Acknowledgment**: Within 72 hours
- **Triage & Fix**: Target within 7 days for confirmed high-severity issues

## Security Design Principles
- All destructive or privileged operations print the exact command before execution.
- User data directories, browser profiles, configs, and Trash are excluded from cleanup.
- No secrets, tokens, or personal identifiers are stored in the repository.
