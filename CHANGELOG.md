# Changelog

## Unreleased

### Added

- Added configurable external command timeout via `--command-timeout <seconds>` and `-t <seconds>`.
- Created the initial Bash CLI with `backup`, `restore`, `list`, `doctor`, `config generate`, `gist pull`, and `gist push`.
- Added YAML inventory/config support with `yq`.
- Added source modules for Homebrew, Mac App Store, npm, pip, pipx, Oh My Zsh, Xcode, dotfiles, and manual apps.
- Added GitHub Gist sync support with `gh` or token-based authentication.
- Added safety helpers for dry-run enforcement, token masking, secret warnings, path confinement, and downloaded installer execution.
- Added Bats test coverage for CLI parsing, config generation, safety behavior, Gist dry-run, and restore dry-run paths.
- Added project docs, prompt history, implementation plan, usage examples, and a real-machine backup/restore report.

### Fixed

- Routed Homebrew, `mas`, and npm version lookup calls through bounded command helpers so slow package-manager commands fail with clearer timeout warnings.
- Reduced unrelated Homebrew work during invoked commands by setting `HOMEBREW_NO_AUTO_UPDATE`, `HOMEBREW_NO_ANALYTICS`, `HOMEBREW_NO_INSTALL_CLEANUP`, and `HOMEBREW_NO_ENV_HINTS`.
- Preserved command failure exit codes from `backup`, `restore`, `list`, `doctor`, `config generate`, and Gist commands instead of masking failures at the end of the CLI entrypoint.
- Fixed literal `~` expansion for dotfile paths so `~/.zshrc`, `~/.gitconfig`, `~/.gitignore_global`, and `~/.ssh/config` resolve under `$HOME`.
- Replaced invalid `brew leaves --versions` usage with `brew leaves` plus `brew list --versions <formula>` for compatibility with the installed Homebrew CLI.
- Ignored interrupted backup temp files via `mac-inventory.yml.tmp.*`.

### Known Issues

- npm remote version lookup can still be slow before timeout; version recording should remain optional.
- Xcode.app version detection can report an unusable `mdls` error even when the app directory is present.
