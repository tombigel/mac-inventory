# AI Contributor Guide

Use this guide when an AI coding agent works in this repo.

## Project Contract

`mac-inventory` helps rebuild a Mac by creating a YAML inventory and performing an additive restore. It must be safe to run on a clean Mac and clear about every action it is about to take.

## Key Workflows

- `prepare`: check/install prerequisites.
- `restore`: run prepare preflight, then restore inventory.
- `continue`: resume from `~/.mac-inventory/resume.yml`.
- `status`: inspect resume state.
- `backup`: generate inventory.

Use `--appstore-login=skip|prompt|pause|require` when testing App Store flows. Never ask for or store Apple ID credentials.

Use `--report`, `--report-format`, and `--skip-report` when validating process-report behavior. Reports must summarize outcomes without storing secrets, copied dotfile contents, tokens, or raw command output.

## Safety Checklist

- No destructive cleanup.
- No unbounded package-manager calls.
- No direct `curl | sh`.
- No secrets in logs, docs, tests, inventory examples, or resume files.
- Dry-run must not mutate user state.
- Resume files must contain only workflow metadata.

## Testing Guidance

Use Bats and mocked commands. Do not call real package managers in tests.

Useful smoke checks:

```bash
mac-inventory prepare --dry-run
mac-inventory restore --dry-run
mac-inventory status
mac-inventory continue --dry-run
```

## Risky Areas

- Dotfile restore and path confinement.
- Gist upload and token handling.
- Homebrew bootstrap and installer download.
- `mas` hanging when App Store is not signed in.
- App Store login policy interactions with Xcode restore.
- Process report accuracy and secret-free output.
- Xcode CLT GUI prompts.
- Resume-state consistency after interruption.
