## Summary

<!-- Describe what this PR changes and why. -->

## Affected Files
- [ ] `Scripts/update.sh`
- [ ] `Scripts/sysedit.sh`
- [ ] Documentation / Workflows

## Checklist
- [ ] Every executed command uses `run` / `run_or_warn` for full terminal transparency
- [ ] No personal identifiers, tokens, or hardcoded local usernames/paths added
- [ ] `bash -n Scripts/*.sh` passes locally
- [ ] `shellcheck -S warning Scripts/*.sh` passes locally
- [ ] `./Scripts/update.sh --help` and `./Scripts/sysedit.sh --help` succeed
