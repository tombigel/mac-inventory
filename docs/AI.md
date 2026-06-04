# AI Contributor Guide

Use this guide when an AI coding agent works in this repo.

## Project Contract

Mac Setup Snapshot helps rebuild a Mac by creating a YAML setup snapshot and performing an additive restore. It must be safe to run on a clean Mac and clear about every action it is about to take.

## Key Workflows

- `prepare`: check/install prerequisites.
- `restore`: run prepare preflight, then restore the setup snapshot.
- `wizard restore`: guided restore; can check requirements early and optionally pause before each restore section.
- `continue`: resume from `~/.mac-setup/resume.yml`.
- `status`: inspect resume state.
- `backup`: generate setup snapshot.

Use `--appstore-login=skip|prompt|pause|require` when testing App Store flows. Never ask for or store Apple ID credentials.

Backup writes `mac-setup.backup.yml`, `backup-list.md`, and `README.md` for local and iCloud targets. The Markdown list and README must stay free of copied dotfile contents, secrets, tokens, and raw command output.

GitHub projects are opt-in. Backup records repo metadata and sanitized clone URLs only, never repository contents. Restore may clone missing repos, but must not fetch, pull, reset, clean, overwrite, or delete existing project folders.

Use `--report`, `--report-format`, and `--skip-report` when validating process-report behavior. Reports must summarize outcomes without storing secrets, copied dotfile contents, tokens, or raw command output.

## Safety Checklist

- No destructive cleanup.
- No unbounded package-manager calls.
- No direct `curl | sh`.
- No secrets in logs, docs, tests, setup snapshot examples, or resume files.
- dry-run mode must not mutate user state.
- Resume files must contain only workflow metadata.
- GitHub project URLs must be sanitized before being written to snapshots, reports, docs, or tests.

## Testing Guidance

Use Bats and mocked commands. Do not call real package managers in tests.

Managed/sandboxed agent shells may not load the user's interactive shell profile, so Homebrew tools can be installed but missing from `PATH`. On Apple Silicon Macs, run validation with Homebrew paths injected explicitly:

```bash
PATH="/opt/homebrew/bin:/usr/local/bin:$PATH" shellcheck bin/mac-setup lib/*.sh lib/sources/*.sh
PATH="/opt/homebrew/bin:/usr/local/bin:$PATH" /opt/homebrew/bin/bats test
```

If `bats` is not found by name, check standard locations before reporting it missing:

```bash
ls -l /opt/homebrew/bin/bats /usr/local/bin/bats
```

Do not assume a missing executable from plain `command -v` means the tool is not installed; first account for sandbox PATH differences. When reporting validation, include the exact command and PATH used.

Timeout tests must not run real slow commands inside full CLI flows. Avoid `sleep 5` or long-running child processes in Bats unless the test runner itself has a hard fail-timeout. Test timeout plumbing by stubbing the timeout wrapper or by direct helper-level tests that return immediately. Full `backup`/`restore` tests should mock package-manager outcomes, not exercise process-killing behavior.

Useful smoke checks:

```bash
mac-setup prepare --dry-run
mac-setup restore --source local --dry-run
mac-setup status
mac-setup continue --dry-run
```

## Risky Areas

- Dotfile restore and path confinement.
- iCloud endpoint preflight, history, and macOS privacy guidance.
- Gist upload and token handling.
- Homebrew bootstrap and installer download.
- `mas` hanging when App Store is not signed in.
- App Store inventory normalization and stale/duplicate `mas list` entries.
- Manual app de-duplication against App Store receipts and Homebrew casks, including punctuation-normalized cask names such as `firefox@nightly`.
- Not-yet-installed Homebrew cask replacement candidates for standalone manual apps, including `brew info --cask` validation to avoid fuzzy search false positives.
- Restore prompting/install behavior for manual app `brew_cask_candidate` values.
- Restore step pacing and wizard preflight choices.
- GitHub project recursive discovery, URL sanitization, and clone-missing-only restore.
- App Store login policy interactions with Xcode restore.
- Process report accuracy and secret-free output.
- Xcode CLT GUI prompts.
- Resume-state consistency after interruption.
