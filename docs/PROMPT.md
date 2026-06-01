# Prompt History

This project was requested as a small open-source Bash CLI to inventory and restore a Mac after formatting.

## Original Request

The tool should inventory installed App Store apps, Homebrew formulae/casks, global npm packages, pip packages, manual installs, and important user settings such as `.zshrc`, global Git config, and global Git ignore.

It should support:

- Backup and restore modes.
- Checks for missing tools such as `mas`, Homebrew, pip, npm, and prompts to install them.
- Login handling where possible, especially `mas`.
- Per-source CLI options and config support.
- Config generation.
- Help output on `--help`, `-h`, or no params.
- Restore checks for existing apps, with skip/overwrite behavior.
- Manual app matching to Homebrew casks during inventory.
- Interactive and non-interactive modes.
- Version tracking and optional version restore.
- Inventory update mode.
- Dry-run and listing modes.
- Tests.

## Tweaks Added During Planning

- Support Oh My Zsh backup/restore.
- If Oh My Zsh is missing during restore, install it with unattended-safe flags: `RUNZSH=no CHSH=no KEEP_ZSHRC=yes`.
- Support Xcode Command Line Tools, Xcode app checks, Xcode login/account checks where detectable, and Xcode installation guidance.
- Add single-letter aliases for main options.
- Support chained no-argument short flags such as `-dyq`.
- Add explicit `config generate` support.
- Save the plan and prompt history in the repo.
- Create a public GitHub repository at `tombigel/mac-inventory`.
- Commit and push in task/stage commits.
- Add a safety model.
- Manual app to Homebrew cask matching defaults to interactive `ask`, with `never` and `all` modes.
- Add GitHub Gist input/output for config and inventory, with interactive `gh` login or token/env credentials.
- Use parallel subagents when implementation can be safely split, while keeping integration in the main thread.
- Add a clean-Mac bootstrap flow with prerequisite installation, resume/continue support, optional caffeinate, clean verbose UX, and AI-agent repo guidance.
- Improve signed-out App Store handling so `mas` operations do not repeatedly hang or fail unclearly.
- Add end-of-process reports, plus a `--skip-report` flag and report file/format options.
- Update README/manual AI usage notes so coding agents know how to use the repo safely.
