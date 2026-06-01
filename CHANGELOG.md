# Changelog

## Unreleased

No unreleased changes yet.

## 0.5.0 - 2026-06-01

### Added

- Added App Store login policy via `--appstore-login skip|prompt|pause|require` and `-a`.
- Added final process reports for workflow commands, with optional `--report <path>`, `--report-format text|md|yaml|json`, and `--skip-report`.
- Added config keys for App Store login policy and reports.
- Added README/manual AI usage notes for safe agent changes.

### Changed

- App Store backup now records a clear skipped status when `mas` is missing, App Store is signed out, or `mas list` fails.
- App Store and Xcode restore now check App Store sign-in before running `mas list` or `mas install`, avoiding repeated slow signed-out `mas` calls.
- Markdown, YAML, JSON, and text reports summarize command status, dry-run state, duration, inventory counts, and manual blockers.

### Fixed

- Fixed report rendering edge cases for Markdown output and missing App Store inventory sections.

## 0.4.0 - 2026-06-01

### Added

- Added clean-Mac bootstrap commands: `prepare`, `continue`, and `status`.
- Added restore preflight through `prepare` unless `--skip-prepare=true`.
- Added resumable workflow state with a YAML checklist under `~/.mac-inventory/resume.yml`.
- Added clean step output before prepare/restore actions, including why the step is needed and how to resume after interruption.
- Added optional `caffeinate` support for long interactive workflows.
- Added AI-agent repo guidance: `AGENTS.md`, `CLAUDE.md`, `.github/copilot-instructions.md`, `docs/AI.md`, and `ai/codex-skill/SKILL.md`.

## 0.3.0 - 2026-06-01

### Added

- Added a man-page-style Markdown manual at `docs/MANUAL.md` covering commands, options, config, files, safety, exit codes, and examples.
- Added configurable external command timeout via `--command-timeout <seconds>` and `-t <seconds>`.

### Fixed

- Routed Homebrew, `mas`, and npm version lookup calls through bounded command helpers so slow package-manager commands fail with clearer timeout warnings.
- Reduced unrelated Homebrew work during invoked commands by setting `HOMEBREW_NO_AUTO_UPDATE`, `HOMEBREW_NO_ANALYTICS`, `HOMEBREW_NO_INSTALL_CLEANUP`, and `HOMEBREW_NO_ENV_HINTS`.

## 0.2.0 - 2026-06-01

### Added

- Added a real-machine backup/restore report.

### Fixed

- Preserved command failure exit codes from `backup`, `restore`, `list`, `doctor`, `config generate`, and Gist commands instead of masking failures at the end of the CLI entrypoint.
- Fixed literal `~` expansion for dotfile paths so `~/.zshrc`, `~/.gitconfig`, `~/.gitignore_global`, and `~/.ssh/config` resolve under `$HOME`.
- Replaced invalid `brew leaves --versions` usage with `brew leaves` plus `brew list --versions <formula>` for compatibility with the installed Homebrew CLI.
- Ignored interrupted backup temp files via `mac-inventory.yml.tmp.*`.

## 0.1.0 - 2026-06-01

### Added

- Created the initial Bash CLI with `backup`, `restore`, `list`, `doctor`, `config generate`, `gist pull`, and `gist push`.
- Added YAML inventory/config support with `yq`.
- Added source modules for Homebrew, Mac App Store, npm, pip, pipx, Oh My Zsh, Xcode, dotfiles, and manual apps.
- Added GitHub Gist sync support with `gh` or token-based authentication.
- Added safety helpers for dry-run enforcement, token masking, secret warnings, path confinement, and downloaded installer execution.
- Added Bats test coverage for CLI parsing, config generation, safety behavior, Gist dry-run, and restore dry-run paths.
- Added project docs, prompt history, implementation plan, usage examples, and a real-machine backup/restore report.

### Known Issues

- npm remote version lookup can still be slow before timeout; version recording should remain optional.
- Xcode.app version detection can report an unusable `mdls` error even when the app directory is present.
