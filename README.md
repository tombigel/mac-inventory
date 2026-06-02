# Mac Setup Snapshot

Mac Setup Snapshot captures the parts of a Mac setup that are easy to lose before a format: package-manager installs, App Store apps, shell setup, developer tools, selected dotfiles, and manually installed applications. It saves that setup state to a reachable endpoint, then uses it to rebuild a fresh Mac.

Restore is intentionally additive: it installs, copies, checks, and reports. It does not uninstall packages, delete applications, or clean directories.

## Usage Docs

- Start with the [manual and full command reference](docs/MANUAL.md) for restore flows, endpoint behavior, config, and safety details.
- See the [development plan](docs/PLAN.md) for design scope and roadmap.
- See [AI agent change guidance](docs/AI.md) before changing behavior with a coding assistant.

## Install

Clone the repository and run the script directly:

```bash
git clone https://github.com/tombigel/mac-setup-snapshot.git
cd mac-setup-snapshot
./bin/mac-setup --help
```

For convenience, add `bin/` to your `PATH`.

## Common Usage

### Before Formatting: Save This Mac To iCloud Drive

iCloud Drive is the default because it is usually available again immediately after reinstalling macOS and signing in with Apple ID.

First, check that the required tools and account state are ready:

```bash
mac-setup doctor
```

Generate a starter config if you want to choose exactly what setup state is captured:

```bash
mac-setup config generate -o mac-setup.config.yml
```

Create or update the setup bundle in iCloud Drive:

```bash
mac-setup backup
```

The default bundle path is:

```text
~/Library/Mobile Documents/com~apple~CloudDocs/Mac Setup Snapshot/
```

macOS may ask the app running this command, such as Terminal, iTerm, or Codex, for permission to access iCloud Drive. If access is denied, allow iCloud Drive access in System Settings > Privacy & Security > Files & Folders.

### After Formatting: Restore From iCloud Drive

On the fresh Mac, sign in to iCloud Drive, then install only enough to clone this repo. If `git` prompts for Xcode Command Line Tools, accept that prompt.

```bash
git clone https://github.com/tombigel/mac-setup-snapshot.git
cd mac-setup-snapshot
```

Preview the rebuild from the iCloud Drive bundle:

```bash
./bin/mac-setup restore --appstore-login=pause --dry-run
```

Then run the additive restore:

```bash
./bin/mac-setup restore --appstore-login=pause
```

`restore` runs `prepare` automatically unless `--skip-prepare=true` is passed. `prepare` checks or installs clean-Mac prerequisites such as Xcode Command Line Tools, Homebrew, `yq`, `mas`, `pipx`, GitHub auth, and App Store access readiness.

If the process is interrupted, inspect or resume it:

```bash
mac-setup status
mac-setup continue
```

## Commands

- `backup`: capture the current Mac setup state.
- `prepare`: check/install clean-Mac prerequisites before restore.
- `restore`: rebuild from saved setup state.
- `continue`: resume an interrupted prepare/restore workflow.
- `status`: show the current resume checklist.
- `list`: inspect saved setup sections.
- `doctor`: check tools, login state, Xcode state, GitHub auth, and readiness.
- `config generate`: generate starter config.
- `gist pull`: download setup state/config from a GitHub Gist.
- `gist push`: upload setup state/config to a GitHub Gist.

No arguments, `help`, `--help`, and `-h` show help.

## Restore Notes

Mac App Store backup and restore depend on `mas` and an active App Store sign-in. The CLI never asks for Apple ID credentials and cannot automate Apple sign-in. By default, enabled App Store work is required: the CLI tries to install/check `mas`, prompts to open the App Store when interactive, and fails until sign-in is available. Use `--apps=false` or `--appstore-login=skip` only when you explicitly want to omit App Store apps.

Every `backup`, `prepare`, `restore`, `continue`, and Gist workflow emits a final process report unless `--skip-report` is used. To write a report file:

```bash
mac-setup restore --dry-run --report reports/restore.md --report-format md
mac-setup backup --report reports/backup.yml --report-format yaml
```

## Captured Setup State

By default, `backup` captures:

- Mac App Store apps through `mas`.
- Homebrew taps, formulae, and casks.
- Global npm packages.
- pip and pipx packages.
- Oh My Zsh install state, theme, plugins, and `.zshrc` reference.
- Xcode Command Line Tools and Xcode.app state.
- Explicitly allowlisted dotfiles and config files.
- Manual apps from `/Applications` and `~/Applications`.

Disable categories with flags such as `--apps=false`, `--brew=false`, or `--dotfiles=false`.

## Examples

```bash
mac-setup backup -udq
mac-setup backup --check-manual-brew=true --manual-brew-match=ask
mac-setup backup --check-manual-brew=true --manual-brew-match=all -y

mac-setup list -S brew
mac-setup list -f md
mac-setup list -f yaml

mac-setup restore -dyq
mac-setup restore -s true
mac-setup restore -w true -S brew
mac-setup restore -U true -y -I false
mac-setup restore --appstore-login=pause
mac-setup restore --skip-report

mac-setup backup --target local
mac-setup backup --target github --gist-create=true --github-login=interactive
mac-setup restore --source github -g abc123 --dry-run
mac-setup gist push -g abc123 --github-token-env GITHUB_TOKEN
```

## Short Flags

No-argument short flags can be chained:

```bash
mac-setup restore -dyq
```

That is equivalent to:

```bash
mac-setup restore --dry-run --yes --quiet
```

Value-taking short options must be standalone or last in a chain:

```bash
mac-setup backup -i mac-setup.yml
mac-setup backup -B=false
```

## Safety

- `--dry-run` prevents operational writes, uploads, downloads, installs, upgrades, overwrites, license acceptance, and shell changes. If `--report <path>` is explicitly passed, only that report artifact is written.
- Dotfile restore defaults to skip existing files.
- Explicit dotfile overwrite first backs up the existing file to `~/.mac-setup/restore-backups/<timestamp>/`.
- Remote installers are downloaded to temp files and executed only after policy allows it; the implementation does not use direct `curl | sh`.
- Gist uploads run secret checks and default to secret Gists.
- CLI token arguments are supported for automation, but `--github-token-env` or `gh auth login` is safer.
- External package-manager commands are run with a configurable timeout:

```bash
mac-setup backup --command-timeout 10
mac-setup restore -t 10 --dry-run
```

Homebrew calls are run with auto-update, analytics, install cleanup, and env hints disabled for the invoked command where possible.

## AI Agent Notes

AI coding agents should read `AGENTS.md`, `CLAUDE.md`, `.github/copilot-instructions.md`, `docs/AI.md`, and `ai/codex-skill/SKILL.md` before changing behavior. Keep restore additive-only, preserve dry-run safety, avoid `eval` and direct `curl | sh`, do not commit generated snapshots/reports/dotfiles, and use mocked package-manager commands in tests.

## Development

Expected checks:

```bash
find bin lib -type f \( -name '*.sh' -o -name 'mac-setup' \) -print0 | xargs -0 -n1 bash -n
shellcheck bin/mac-setup lib/*.sh lib/sources/*.sh
bats test
```

The tests use mocked package-manager commands so they can run without installing or changing real applications.
