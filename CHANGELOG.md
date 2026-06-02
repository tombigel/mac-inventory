# Changelog

## Unreleased

### Added

- Added `bin/mac-setup` as the CLI entrypoint for Mac Setup Snapshot.
- Added README and manual common usage flows for checking backup readiness, saving a setup snapshot to iCloud Drive, and restoring from iCloud after formatting.
- Added iCloud Drive as the default backup and restore endpoint, with explicit local and GitHub/Gist endpoint options.
- Added iCloud endpoint preflight checks, macOS privacy guidance, endpoint metadata, and timestamped iCloud history for replaced snapshots.
- Added config keys for default storage endpoints and the iCloud bundle folder name.
- Added endpoint Bats coverage and a manual iCloud endpoint smoke-test script.
- Added `list --format md` for a human-readable Markdown setup snapshot summary.
- Added default per-section backup progress output with elapsed time and item counts when available.
- Added friendlier default backup/restore welcome messages, progress bars, next-step hints, and terminal summaries.
- Added default `backup-list.md` generation for local and iCloud backups.
- Added default backup-folder `README.md` generation with restore instructions for local and iCloud backups.
- Added richer `backup --verbose` diagnostics for command captures, app indexing, App Store parsing, and manual app matching.
- Added stable app refs for App Store apps, Homebrew casks, and manual apps.
- Added `ignore` and `unignore` commands to keep app entries in the snapshot while excluding them from restore.

### Changed

- Renamed user-facing docs, defaults, generated filenames, Gist filenames, reports, and runtime state paths to Mac Setup Snapshot / `mac-setup`.
- Moved the README manual and usage documentation links near the top of the file.
- Updated common usage docs to show iCloud-first backup and restore, with GitHub/Gist as an explicit developer option.
- Updated GitHub/Gist dry-run flows so they report intended work without requiring GitHub authentication first.
- Changed App Store handling to require working `mas` and App Store authentication by default whenever the App Store source is enabled, instead of silently skipping App Store apps.
- Replaced the invalid `mas account` readiness check with real `mas list` access checks.
- Changed the stale resume prompt so declining to continue starts a fresh requested workflow instead of aborting.
- Changed `list` to use the source endpoint flow, so it defaults to the iCloud setup snapshot like `restore`.
- Changed generated config and defaults so manual app Homebrew cask matching is enabled by default.
- Changed App Store backup to normalize and de-duplicate `mas list` output before writing the snapshot.
- Changed manual app backup to omit apps already represented by App Store receipts or installed Homebrew casks.
- Changed readable app lists to show stable refs and ignored state for app-like restore rows.
- Changed backup to reapply persisted ignored-app config rules to fresh snapshots.

### Fixed

- Preserved explicit snapshot paths when iCloud endpoint defaults are active.
- Fixed validation failures from shellcheck and host-dependent Bats fixtures.
- Enforced the documented `yq v4` requirement instead of accepting any `yq` binary on `PATH`.
- Made App Store inventory failures abort backup unless the user explicitly disables App Store work.
- Applied generated config keys for manual app matching, version recording, and missing-tool installation policy.
- Kept verbose logs out of generated YAML by writing verbose output to stderr.
- Avoided apparent backup hangs by matching manual apps against one Homebrew cask catalog lookup and printing per-app manual scan progress.
- Fixed App Store rows with shared MAS names by preferring matched local bundle names and versions in the snapshot.
- Fixed manual app de-duplication so installed Homebrew casks such as `vlc` are excluded before cask candidate search.
- Fixed manual app cask matching for cask tokens that differ from app names by punctuation, such as `firefox@nightly`.
- Added matched app display name, path, and app version metadata to Homebrew cask snapshot rows for human-readable lists.
- Kept not-yet-installed Homebrew cask replacement candidate search for standalone manual apps, with per-app search fallback.
- Changed restore so manual apps with `brew_cask_candidate` prompt for Homebrew cask installation by default, install with `--yes`, and remain manual-only only when no candidate exists or the user skips.
- Added matched app paths to App Store snapshot rows and Markdown list output.
- Tightened manual app cask candidates by requiring `brew info --cask` to resolve before recording, prompting, or installing a candidate.
- Honored generated config `backup.dotfiles` lists and documented default and recommended dotfile candidates.
- Expanded the default low-risk dotfile allowlist for common shell, Git, editor, terminal, and CLI presentation configs.
- Changed dotfile backup to skip missing allowlist entries instead of recording `exists: false` rows.
- Cleaned tracked temporary files after successful command runs.

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
- Added resumable workflow state with a YAML checklist under `~/.mac-setup/resume.yml`.
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
- Ignored interrupted backup temp files via `mac-setup.yml.tmp.*`.

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
