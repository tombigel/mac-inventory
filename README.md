# Mac Setup Snapshot

Mac Setup Snapshot captures the parts of a Mac setup that are easy to lose before a format: package-manager installs, App Store apps, shell setup, developer tools, selected dotfiles, and manually installed applications. It saves that setup state to a reachable endpoint, then uses it to rebuild a fresh Mac.

Restore is intentionally additive: it installs, copies, checks, and reports. It does not uninstall packages, delete applications, or clean directories.

## Usage Docs

- Start with the [manual and full command reference](docs/MANUAL.md) for restore flows, endpoint behavior, config, and safety details.

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

For a guided flow, run:

```bash
mac-setup wizard
```

In an interactive terminal, running `mac-setup` with no arguments opens the same wizard. In scripts and other non-interactive contexts, no arguments still print help.

The wizard asks for backup or restore, dry-run mode, storage endpoint, config handling, enabled sources, and key restore policy choices. It then runs the equivalent `backup` or `restore` command with normal safety rules.

Create or update the setup bundle in iCloud Drive:

```bash
mac-setup backup
```

Backup prints per-section progress by default and writes the YAML snapshot, a human-readable Markdown list, and restore notes. In an interactive terminal, progress updates in place and uses terminal-palette ANSI styling for headings, muted details, success, and alerts. Non-TTY output, CI, `TERM=dumb`, `NO_COLOR`, `--quiet`, and `--verbose` use plain stable output. The Markdown list is named `backup-list.md` and is generated from the completed snapshot, so it does not contain copied dotfile contents. The restore notes are written to `README.md` in the backup folder.

Manual app scanning also prints the app currently being checked when Homebrew cask matching is enabled.

Use `--verbose` during backup to show command start/status lines, captured output counts, app indexing details, App Store parsing decisions, and manual app matching decisions.

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
- `ignore`: keep an app in the snapshot but skip it during restore.
- `unignore`: restore an ignored snapshot entry again.
- `continue`: resume an interrupted prepare/restore workflow.
- `status`: show the current resume checklist.
- `list`: inspect saved setup sections.
- `doctor`: check tools, login state, Xcode state, GitHub auth, and readiness.
- `wizard`: guided backup/restore setup.
- `config generate`: generate starter config.
- `gist pull`: download setup state/config from a GitHub Gist.
- `gist push`: upload setup state/config to a GitHub Gist.

No arguments open the wizard in an interactive terminal and show help otherwise. `help`, `--help`, and `-h` always show help.

## Restore Notes

Mac App Store backup and restore depend on `mas` and an active App Store sign-in. The CLI never asks for Apple ID credentials and cannot automate Apple sign-in. By default, enabled App Store work is required: the CLI tries to install/check `mas`, prompts to open the App Store when interactive, and fails until sign-in is available. Use `--apps=false` or `--appstore-login=skip` only when you explicitly want to omit App Store apps.

App Store backup records currently installed apps from `mas list`, preferring JSON output when supported and falling back to text output. The snapshot is normalized and de-duplicated before restore/list/report output uses it. Restore entries get stable refs such as `appstore:123456789`, `brew_formula:git`, `brew_cask:visual-studio-code`, `npm:typescript`, or `manual:com.example.App` for targeting with `ignore` and `unignore`. When a `mas` row matches an installed bundle, the snapshot prefers the local bundle name, path, and version so similarly named App Store apps remain distinguishable.

Every `backup`, `prepare`, `restore`, `continue`, and Gist workflow emits a friendly terminal summary unless `--quiet` or `--skip-report` is used. Use `--verbose` when you also want raw counts in that summary. To write a structured report file:

```bash
mac-setup restore --dry-run --report reports/restore.md --report-format md
mac-setup backup --report reports/backup.yml --report-format yaml
```

Wizard menus are controlled by the tracked repo file `mac-setup.wizard.yml`. Edit that file to reorder, hide, relabel, and set defaults for known backup/restore sources and prompts, including backup config handling and restore config use. It cannot define shell commands, hooks, arbitrary steps, or executable restore behavior.

The user config is separate: backup wizard mode keeps `mac-setup.config.yml` in the selected backup folder. If it is missing, the wizard generates it by default. If it already exists, the wizard asks whether to create a new timestamped config, overwrite the existing one, or use the existing one.

Wizard dry-run defaults are intentionally different by workflow: backup defaults to a real run, while restore defaults to dry-run preview.

Useful wizard commands:

```bash
mac-setup wizard
mac-setup --wizard-config ./mac-setup.wizard.yml wizard
```

## Captured Setup State

By default, `backup` captures:

- Mac App Store apps through `mas`.
- Homebrew taps, top-level formulae from `brew leaves`, and casks. Cask snapshot rows include the cask token plus matched installed app name and path when an app bundle can be found.
- Global npm packages.
- pip and pipx packages.
- Oh My Zsh install state, theme, plugins, and `.zshrc` reference.
- Xcode Command Line Tools and Xcode.app state.
- Explicitly allowlisted dotfiles and config files that exist at backup time. Defaults include common shell, Git, editor, terminal, and low-risk CLI config files; see `docs/MANUAL.md` for the full list.
- Manual apps from `/Applications` and `~/Applications`, excluding apps already represented by App Store receipts or installed Homebrew casks. Other standalone apps are checked for not-yet-installed Homebrew cask replacement candidates and record the candidate only when `brew info --cask` confirms it is installable, unless the migration policy accepts it into the Homebrew cask list.

Disable categories with flags such as `--apps=false`, `--brew=false`, or `--dotfiles=false`.

During restore, manual apps with a recorded `brew_cask_candidate` are prompted as Homebrew cask installs by default. Non-interactive restore reports the candidate without installing; pass `--yes` to install candidate casks automatically. Manual apps without candidates still require manual restore.

Use `mac-setup ignore <ref>` to keep an app visible in the snapshot and `backup-list.md` while preventing restore from reinstalling or prompting for it. The ignore rule is also saved to config so future backups keep the same app ignored. Use `mac-setup unignore <ref>` to restore it again.

Other useful dotfiles you may want to add explicitly with `-F` include `~/.config/gh/config.yml`, `~/.npmrc`, `~/.pypirc`, `~/.netrc`, `~/.docker/config.json`, `~/.kube/config`, cloud CLI config under `~/.aws`, `~/.azure`, or `~/.config/gcloud`, and selected files under `~/.config`, `~/.ssh`, or `~/.gnupg`. Review these before backing up or sharing because many can contain tokens, hostnames, or credentials.

## Examples

```bash
mac-setup backup -udq
mac-setup backup --check-manual-brew=true --manual-brew-match=ask
mac-setup backup --check-manual-brew=true --manual-brew-match=all -y

mac-setup list -S brew
mac-setup list -f md
mac-setup list -f yaml
mac-setup ignore brew_cask:visual-studio-code
mac-setup unignore appstore:123456789

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
mac-setup backup -i mac-setup.backup.yml
mac-setup backup -B=false
```

## Safety

- `--dry-run` prevents operational writes, uploads, downloads, installs, upgrades, overwrites, license acceptance, generated backup-list/README writes, and shell changes. If `--report <path>` is explicitly passed, only that report artifact is written.
- `config generate --dry-run` reports the user config path without writing it.
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

- See the [development plan](docs/PLAN.md) for design scope and roadmap.
- See [AI agent change guidance](docs/AI.md) before changing behavior with a coding assistant.

Expected checks:

```bash
find bin lib -type f \( -name '*.sh' -o -name 'mac-setup' \) -print0 | xargs -0 -n1 bash -n
PATH="/opt/homebrew/bin:/usr/local/bin:$PATH" shellcheck bin/mac-setup lib/*.sh lib/sources/*.sh
PATH="/opt/homebrew/bin:/usr/local/bin:$PATH" /opt/homebrew/bin/bats test
```

The tests use mocked package-manager commands so they can run without installing or changing real applications.
In sandboxed agent environments, Homebrew tools may be installed but missing from the default non-interactive `PATH`; inject `/opt/homebrew/bin:/usr/local/bin` before declaring `bats`, `shellcheck`, or `yq` unavailable.
