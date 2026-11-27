# Contributing to System-Scripts

Contributions, bug reports, and improvements are welcome. Please follow these guidelines to keep the scripts safe, transparent, and portable.

## Core Principles

1. **100% Transparency**: Every external command that modifies system state or cleans caches must be executed via `run` or `run_or_warn` so users see the exact command and live output.
2. **Safe by Default**:
   - Never touch personal directories (`~/Documents`, `~/Pictures`, `~/Downloads`, `~/Projects`, `~/Desktop`), app configs, browser logins/cookies/bookmarks, Trash, or GPU shader caches.
   - Skip uninstalled or empty ecosystems (`snap`, `flatpak`, `rustup`, `pipx`) cleanly without printing clutter.
   - Keep `update.sh` (`sysupdate`) focused on routine updates and caches; heavy/snapshot operations belong in `sysedit.sh` (`sysedit`).
3. **No Personal Info**: Never commit usernames, hostnames, emails, tokens, or machine-specific paths. Use `$HOME` or standard XDG paths.

## Local Testing Before Opening a PR

Run these checks locally before committing:

```bash
# 1. Bash syntax validation
bash -n Scripts/update.sh Scripts/sysedit.sh

# 2. ShellCheck static analysis
shellcheck -S warning Scripts/update.sh Scripts/sysedit.sh

# 3. CLI help smoke tests
./Scripts/update.sh --help
./Scripts/sysedit.sh --help
```

## Pull Request Process

1. Fork the repository and create a topic branch from `main`.
2. Keep changes focused and describe what the change does and does not touch.
3. Ensure all CI checks (`ShellCheck & Syntax`, `CodeQL`) pass on your pull request.
