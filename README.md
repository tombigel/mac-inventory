# mac-inventory

`mac-inventory` is a Bash-first macOS inventory and restore CLI for rebuilding a Mac after a format. It records reinstallable software, shell setup, developer tooling, and selected user files into YAML.

The restore model is intentionally additive: it installs, copies, checks, and reports. It does not uninstall packages, delete applications, or clean directories.

## Install

Clone the repository and run the script directly:

```bash
git clone https://github.com/tombigel/mac-inventory.git
cd mac-inventory
./bin/mac-inventory --help
```

For convenience, add `bin/` to your `PATH`.

## Quick Start

```bash
mac-inventory doctor
mac-inventory prepare --dry-run
mac-inventory prepare
mac-inventory config generate -o mac-inventory.config.yml
mac-inventory backup -i mac-inventory.yml
mac-inventory restore -i mac-inventory.yml --dry-run
mac-inventory restore -i mac-inventory.yml
```

## Commands

- `backup`: create or update an inventory.
- `prepare`: check/install clean-Mac prerequisites before restore.
- `restore`: restore from an inventory.
- `continue`: resume an interrupted prepare/restore workflow.
- `status`: show the current resume checklist.
- `list`: list inventory sections.
- `doctor`: check tools, login state, Xcode state, GitHub auth, and readiness.
- `config generate`: generate starter config.
- `gist pull`: download inventory/config from a GitHub Gist.
- `gist push`: upload inventory/config to a GitHub Gist.

No arguments, `help`, `--help`, and `-h` show help.

## Clean Mac Restore Flow

On a fresh Mac, run:

```bash
mac-inventory prepare
mac-inventory restore --dry-run
mac-inventory restore
```

`restore` runs `prepare` automatically unless `--skip-prepare=true` is passed. Long interactive prepare/restore workflows use `caffeinate` when available to reduce sleep interruptions.

If the process is interrupted, inspect or resume it:

```bash
mac-inventory status
mac-inventory continue
```

Mac App Store restore depends on `mas` and an active App Store sign-in. The CLI never asks for Apple ID credentials. Use `--appstore-login=skip|prompt|pause|require` to choose whether signed-out App Store work is skipped, prompts to open the App Store, pauses for `mac-inventory continue`, or fails until login is available.

Every `backup`, `prepare`, `restore`, `continue`, and Gist workflow emits a final process report unless `--skip-report` is used. To write a report file:

```bash
mac-inventory restore --dry-run --report reports/restore.md --report-format md
mac-inventory backup --report reports/backup.yml --report-format yaml
```

## Inventory Sources

By default, backup includes:

- Mac App Store apps through `mas`.
- Homebrew taps, formulae, and casks.
- Global npm packages.
- pip and pipx packages.
- Oh My Zsh install state, theme, plugins, and `.zshrc` reference.
- Xcode Command Line Tools and Xcode.app state.
- Explicitly allowlisted dotfiles.
- Manual apps from `/Applications` and `~/Applications`.

Disable sources with flags such as `--apps=false`, `--brew=false`, or `--dotfiles=false`.

## Examples

```bash
mac-inventory backup -udq
mac-inventory backup --check-manual-brew=true --manual-brew-match=ask
mac-inventory backup --check-manual-brew=true --manual-brew-match=all -y

mac-inventory list -S brew
mac-inventory list -f yaml

mac-inventory restore -dyq
mac-inventory restore -s true
mac-inventory restore -w true -S brew
mac-inventory restore -U true -y -I false
mac-inventory restore --appstore-login=pause
mac-inventory restore --skip-report

mac-inventory backup --gist-create=true --gist-push
mac-inventory restore -g abc123 --gist-pull --dry-run
mac-inventory gist push -g abc123 --github-token-env GITHUB_TOKEN
```

## Short Flags

No-argument short flags can be chained:

```bash
mac-inventory restore -dyq
```

That is equivalent to:

```bash
mac-inventory restore --dry-run --yes --quiet
```

Value-taking short options must be standalone or last in a chain:

```bash
mac-inventory backup -i mac-inventory.yml
mac-inventory backup -B=false
```

## Safety

- `--dry-run` prevents operational writes, uploads, downloads, installs, upgrades, overwrites, license acceptance, and shell changes. If `--report <path>` is explicitly passed, only that report artifact is written.
- Dotfile restore defaults to skip existing files.
- Explicit dotfile overwrite first backs up the existing file to `~/.mac-inventory/restore-backups/<timestamp>/`.
- Remote installers are downloaded to temp files and executed only after policy allows it; the implementation does not use direct `curl | sh`.
- Gist uploads run secret checks and default to secret Gists.
- CLI token arguments are supported for automation, but `--github-token-env` or `gh auth login` is safer.
- External package-manager commands are run with a configurable timeout:

```bash
mac-inventory backup --command-timeout 10
mac-inventory restore -t 10 --dry-run
```

Homebrew calls are run with auto-update, analytics, install cleanup, and env hints disabled for the invoked command where possible.

## AI Agent Notes

AI coding agents should read `AGENTS.md`, `CLAUDE.md`, `.github/copilot-instructions.md`, `docs/AI.md`, and `ai/codex-skill/SKILL.md` before changing behavior. Keep restore additive-only, preserve dry-run safety, avoid `eval` and direct `curl | sh`, do not commit generated inventories/reports/dotfiles, and use mocked package-manager commands in tests.

## Development

Expected checks:

```bash
shellcheck bin/mac-inventory lib/**/*.sh
bats test
```

The tests use mocked package-manager commands so they can run without installing or changing real applications.

See [docs/MANUAL.md](docs/MANUAL.md) for the full command reference, [docs/PLAN.md](docs/PLAN.md) for the implementation plan, and [docs/PROMPT.md](docs/PROMPT.md) for the prompt history.
