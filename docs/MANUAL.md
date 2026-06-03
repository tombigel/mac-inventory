# Mac Setup Snapshot Manual

## Name

`mac-setup` - snapshot and restore reinstallable macOS software, shell tooling, developer tooling, selected dotfiles, and optional iCloud Drive or GitHub Gist storage.

## Synopsis

```bash
mac-setup <command> [options]
mac-setup backup [options]
mac-setup prepare [options]
mac-setup restore [options]
mac-setup continue [options]
mac-setup status [options]
mac-setup list [options]
mac-setup doctor [options]
mac-setup wizard [options]
mac-setup config generate [options]
mac-setup gist pull [options]
mac-setup gist push [options]
mac-setup help
mac-setup --help
mac-setup -h
```

Calling `mac-setup` without arguments opens the guided wizard in an interactive terminal and prints help otherwise.

## Description

`mac-setup` is a Bash CLI for preparing a Mac rebuild. It creates a YAML setup snapshot of installed software and selected user configuration, then uses that snapshot to run an additive restore.

Restore is additive-only in v1. It installs, copies, checks, and reports. It does not uninstall packages, delete applications, clean directories, or remove software that is not in the snapshot.

## Common Usage

### Save This Mac To iCloud Drive

Check backup prerequisites and account state:

```bash
mac-setup doctor
```

Generate a starter config if you want to review or customize sources:

```bash
mac-setup config generate -o mac-setup.config.yml
```

Wizard menus are defined by the tracked `mac-setup.wizard.yml` file in the repo. Edit it when you want to customize guided menus.

Create or update the default iCloud Drive setup snapshot:

```bash
mac-setup backup
```

The default iCloud bundle is:

```text
~/Library/Mobile Documents/com~apple~CloudDocs/Mac Setup Snapshot/
```

macOS may ask the app running this command, such as Terminal, iTerm, or Codex, for permission to access iCloud Drive. If access is denied, allow iCloud Drive access in System Settings > Privacy & Security > Files & Folders.

### Restore After Formatting

On the fresh Mac, install only enough to clone this repo. If `git` prompts for Xcode Command Line Tools, accept that prompt.

```bash
git clone https://github.com/tombigel/mac-setup-snapshot.git
cd mac-setup-snapshot
```

Run a dry-run restore from the iCloud Drive bundle first:

```bash
./bin/mac-setup restore --appstore-login=pause --dry-run
```

Then run the real additive restore:

```bash
./bin/mac-setup restore --appstore-login=pause
```

`restore` runs `prepare` automatically unless `--skip-prepare=true` is passed.

## Commands

### `backup`

Create a setup snapshot file from the current Mac.

```bash
mac-setup backup
mac-setup backup -i mac-setup.backup.yml
mac-setup backup --target local
mac-setup backup --target github --gist-create=true --github-login=interactive
mac-setup backup --update
mac-setup backup --apps=false --versions=false
mac-setup backup --check-manual-brew=true --manual-brew-match=ask
mac-setup backup --gist-create=true --gist-push
```

By default, backup includes App Store apps, Homebrew, npm globals, pip, pipx, Oh My Zsh, Xcode, dotfiles, and manual apps.

Backup and restore print a welcome message, the next step, progress for enabled sections, and a friendly terminal summary by default. In an interactive terminal, progress updates in place and uses terminal-palette ANSI styling: bold headings, dim secondary text, green success, red alerts, and yellow dry-run markers. Manual app scanning also updates the current app being checked when Homebrew cask matching is enabled. Non-TTY output, CI, `TERM=dumb`, `NO_COLOR`, `--quiet`, and `--verbose` use plain stable output. Use `--quiet` to suppress the welcome, progress, and default summary. Use `--verbose` for command start/status lines, captured output counts, app indexing details, App Store parsing decisions, manual app matching decisions, and raw summary counts.

For local and iCloud backups, backup also writes `backup-list.md` and `README.md` next to `mac-setup.backup.yml`. The list is generated from the completed snapshot using the same renderer as `mac-setup list --format md`; it does not include copied dotfile contents or raw command output. The README contains restore instructions and a file map for the backup folder.

Use `--dry-run` to print the snapshot that would be generated without writing it. In dry-run mode, the command reports where `backup-list.md` and `README.md` would be written but does not create them.

### `restore`

Restore from an existing setup snapshot file.

```bash
mac-setup restore
mac-setup restore -i mac-setup.backup.yml --dry-run
mac-setup restore --source local -i mac-setup.backup.yml --dry-run
mac-setup restore --source github -g abc123 --dry-run
mac-setup restore -S brew
mac-setup restore --skip-existing=true
mac-setup restore --overwrite=true -S dotfiles
mac-setup restore --appstore-login=pause
mac-setup restore --report reports/restore.md --report-format md
mac-setup restore -g abc123 --gist-pull --dry-run
```

Restore checks existing installations first. By default, existing items are skipped. Dotfiles are skipped unless `--overwrite=true` is used; when overwriting, the current file is backed up first.

Restore runs `prepare` first unless `--skip-prepare=true` is passed.

`--dry-run` prevents installs, downloads, Gist writes, snapshot writes, backup-list/README writes, dotfile copies, overwrites, shell changes, and license acceptance. If `--report <path>` is explicitly passed, only that report artifact is written.

Mac App Store backup and restore require `mas` plus a signed-in App Store app when the App Store source is enabled. The CLI never asks for Apple ID credentials and cannot automate Apple sign-in. By default, it tries to make `mas` usable and then fails until App Store sign-in is available. Use `--apps=false` or `--appstore-login=skip` only when you explicitly want to omit App Store apps.

### `ignore`

Mark one restore-relevant snapshot entry as ignored while keeping it recorded.

```bash
mac-setup ignore brew_cask:visual-studio-code
mac-setup ignore appstore:123456789
mac-setup ignore "Visual Studio Code" --source local -i mac-setup.backup.yml
mac-setup ignore brew_cask:visual-studio-code --dry-run
```

Ignored entries remain visible in `mac-setup.backup.yml`, `backup-list.md`, and `list --format md`, but restore skips them. The command edits the selected source snapshot: iCloud by default, local when `--source local` or `--inventory` is passed, and GitHub Gist when `--source github -g <id>` is passed. GitHub source edits pull before changing the local snapshot and push after a successful non-dry-run edit.

The command first matches exact `ref` values, then exact or normalized app names, IDs, bundle IDs, cask names, and app path basenames. If no entry matches, it exits `1`. If multiple entries match, it exits `2`, prints the candidate refs, and changes nothing.

In dry-run mode, the command prints the entry and files that would be changed without writing the snapshot, config, backup-list, README, or Gist.

### `unignore`

Clear an ignored snapshot-entry rule.

```bash
mac-setup unignore brew_cask:visual-studio-code
mac-setup unignore appstore:123456789 --source local -i mac-setup.backup.yml
```

`unignore` clears the snapshot `ignored` marker and removes the persisted config rule for the matched ref.

### `prepare`

Check and install clean-Mac prerequisites before restore.

```bash
mac-setup prepare
mac-setup prepare --dry-run
mac-setup prepare --check-only=true
mac-setup prepare --caffeinate=false
```

Prerequisite order:

1. Xcode Command Line Tools.
2. Homebrew.
3. `yq`.
4. `mas`, when App Store or Xcode restore is enabled.
5. `pipx`, when pipx restore is enabled.
6. GitHub auth, when Gist sync is enabled.
7. App Store access through `mas list`, when `mas` is needed.

### `continue`

Resume an interrupted `prepare` or `restore` workflow from the resume checklist.

```bash
mac-setup continue
mac-setup continue --dry-run
mac-setup continue --resume-file ~/.mac-setup/resume.yml
```

### `status`

Print the current resume checklist.

```bash
mac-setup status
mac-setup status --resume-file ~/.mac-setup/resume.yml
```

### `list`

List setup snapshot sections.

```bash
mac-setup list
mac-setup list -i mac-setup.backup.yml
mac-setup list -S brew
mac-setup list -S manual_apps
mac-setup list --format md
mac-setup list --format yaml
mac-setup list --format json
```

Without `--inventory` or `--source local`, `list` reads the default source endpoint, which is iCloud Drive unless config changes it.

Formats:

- `table`: default, prints section names or selected section labels.
- `md`: prints a human-readable Markdown summary with tables.
- `yaml`: prints the full setup snapshot or selected YAML sections.
- `json`: converts the setup snapshot to JSON with `yq`.

### `doctor`

Check local readiness.

```bash
mac-setup doctor
mac-setup doctor --command-timeout 5
```

Checks include:

- `brew`
- `yq`
- `mas`
- `npm`
- `pip3`
- `pipx`
- GitHub/Gist authentication
- App Store access through `mas list`
- Oh My Zsh installation
- Xcode Command Line Tools
- selected developer directory
- Xcode license and first-launch status where detectable

### `config generate`

Generate a starter YAML config.

```bash
mac-setup config generate
mac-setup config generate -o mac-setup.config.yml
mac-setup config generate --output ./config.yml
mac-setup config generate --dry-run
```

If no output path is provided, the default is `mac-setup.config.yml`.

If the target file already exists, interactive mode prompts before overwriting. Non-interactive mode fails conservatively unless `--yes` allows the write.

### `wizard`

Start a guided backup or restore flow.

```bash
mac-setup wizard
mac-setup --wizard-config ./mac-setup.wizard.yml wizard
```

The wizard uses numbered menus and comma/range source selection such as `1,3-5`, `all`, or `none`. Backup keeps the user config in the selected backup folder. If `mac-setup.config.yml` is missing there, the wizard generates it by default. If it already exists, the wizard asks whether to create a new timestamped config, overwrite the existing config, or use the existing config. Restore offers to use an existing config when one is found, and choosing no runs that restore without config. It compiles choices into the existing `backup` or `restore` flags and then runs that command, preserving additive restore, dry-run, endpoint, skip-existing, and prompt safety behavior.

The wizard dry-run prompt defaults to no for backup and yes for restore.

The wizard requires an interactive terminal. Use normal `backup` or `restore` commands for scripts and automation. Running `mac-setup` with no arguments opens the wizard only when stdin is a TTY; non-interactive no-args still prints help.

## Endpoint Options

`--target icloud|local|github`

Backup endpoint. Default: `icloud`.

- `icloud`: write the setup snapshot bundle to iCloud Drive.
- `local`: write `mac-setup.backup.yml`, `backup-list.md`, `README.md`, optional config, and copied `files/` in the current directory or explicit paths.
- `github`: write locally and push snapshot/config to GitHub Gist.

`--source icloud|local|github`

Restore endpoint. Default: `icloud`.

- `icloud`: read the setup snapshot bundle from iCloud Drive.
- `local`: read from current directory or explicit paths.
- `github`: pull snapshot/config from GitHub Gist before restore.

`--icloud-folder <name>`

iCloud Drive folder name. Default: `Mac Setup Snapshot`.

`--icloud-root <path>`

iCloud Drive root path. Default: `~/Library/Mobile Documents/com~apple~CloudDocs`.

The iCloud endpoint stores `mac-setup.backup.yml`, `backup-list.md`, `README.md`, optional `mac-setup.config.yml`, copied `files/`, and `metadata.yml` in one bundle folder. Before overwriting an existing bundle, backup moves current bundle files into `history/YYYYMMDDTHHMMSSZ/`. `ignore` and `unignore` update the selected source in place and regenerate the readable files for local and iCloud snapshots.

If iCloud Drive is missing or inaccessible, interactive commands offer local/GitHub fallback where possible. Non-interactive commands fail clearly unless a non-iCloud endpoint is explicit.

### `gist pull`

Download setup snapshot and config files from a GitHub Gist.

```bash
mac-setup gist pull -g abc123
mac-setup gist pull --gist-id abc123 --inventory mac-setup.backup.yml --config mac-setup.config.yml
mac-setup gist pull -g abc123 --github-login=interactive
```

Pull currently prefers authenticated `gh` usage. Existing local files are backed up before replacement.

### `gist push`

Upload setup snapshot and/or config files to a GitHub Gist.

```bash
mac-setup gist push -g abc123
mac-setup gist push --gist-create=true
mac-setup gist push -g abc123 --github-token-env GITHUB_TOKEN
mac-setup gist push -g abc123 --github-login=interactive
```

Secret Gists are the default. Public Gist upload requires explicit `--gist-visibility public` and confirmation policy.

Before upload, files are scanned for common secret patterns. Tokens are masked in logs and are not written to snapshot or config files.

## Global Options

### Files

`--config <path>`, `-c <path>`

Config file path. Default: `mac-setup.config.yml`.

`--wizard-config <path>`

Wizard config file path. Default: `mac-setup.wizard.yml`.

`--inventory <path>`, `-i <path>`

Setup snapshot file path. Default: `mac-setup.backup.yml`.

`--output <path>`, `-o <path>`

Output path for `backup` and `config generate`. For backup, this is an alias for `--inventory`.

### Source Selection

Boolean source options accept `true` or `false`.

```bash
mac-setup backup --apps=false --brew=true
mac-setup restore -B false -N true
```

Available source flags:

- `--apps true|false`, `-A true|false`: Mac App Store apps through `mas`.
- `--brew true|false`, `-B true|false`: Homebrew taps, formulae, and casks.
- `--npm true|false`, `-N true|false`: global npm packages.
- `--pip true|false`, `-P true|false`: pip packages from `pip3`.
- `--pipx true|false`, `-Q true|false`: pipx packages.
- `--oh-my-zsh true|false`, `-O true|false`: Oh My Zsh state and `.zshrc` reference.
- `--xcode true|false`, `-X true|false`: Xcode and Command Line Tools state.
- `--dotfiles true|false`, `-D true|false`: configured dotfiles.
- `--manual-apps true|false`, `-M true|false`: apps from `/Applications` and `~/Applications`.

### Prompt And Execution Policy

`--interactive true|false`, `-I true|false`

Enable or disable prompts. Defaults to true when running in an interactive terminal.

The wizard ignores non-interactive stdin and fails clearly instead of guessing choices. Use explicit backup/restore flags for automation.

`--yes`, `-y`

Accept safe prompts. This does not silently approve suspicious path restores, destructive actions, public Gist publication, or unexpected privilege escalation.

`--no`, `-n`

Reject optional prompts.

`--dry-run`, `-d`

Print planned work without side effects.

An explicit `--report <path>` may still write the requested report artifact during dry-run. The default `backup-list.md` and `README.md` files are not written during dry-run.

`--verbose`, `-v`

Print more detailed command and failure information.

`--quiet`, `-q`

Reduce output.

`--help`, `-h`

Show help.

`--command-timeout <seconds>`, `-t <seconds>`

Set timeout for external package-manager commands. Default: `30`.

Use `0` to disable the wrapper timeout.

```bash
mac-setup backup -t 10
mac-setup restore --command-timeout 5 --dry-run
```

Homebrew commands are invoked with these environment variables where possible:

```bash
HOMEBREW_NO_AUTO_UPDATE=1
HOMEBREW_NO_ANALYTICS=1
HOMEBREW_NO_INSTALL_CLEANUP=1
HOMEBREW_NO_ENV_HINTS=1
```

`--skip-prepare true|false`

Skip restore preflight. Default: `false` for `restore`.

`--prepare-only`

Reserved for workflows that should stop after prepare.

`--pause-after-prepare true|false`

Pause after prepare completes. Default: `false`.

`--caffeinate true|false`

Use `caffeinate` to reduce sleep interruptions during `prepare`, `restore`, and `continue`. Defaults to enabled for interactive long workflows.

`--resume-file <path>`

Resume checklist path. Default: `~/.mac-setup/resume.yml`.

`--reset-resume`

Remove stale resume state after confirmation.

When an interactive `prepare` or `restore` finds existing resume state, answering `yes` continues the interrupted workflow. Answering `no` replaces the stale resume state and starts the newly requested workflow.

`--check-only true|false`

Check prerequisites without installing. Used by prepare-style checks.

### Report Options

`--report <path>`, `-r <path>`

Write an end-of-process report to a file instead of only printing the terminal summary.

`--report-format text|md|yaml|json`, `-j text|md|yaml|json`

Report file format. Default: `text`.

`--skip-report`, `-R`

Suppress the final terminal summary. Errors and warnings still print through normal command output.

Reports include command, status, dry-run state, setup snapshot path, duration, snapshot counts where available, and warnings or manual actions such as missing App Store authentication. Reports must not include secrets, tokens, copied dotfile contents, or raw command output.

## Backup Options

`--update`, `-u`

Merge into an existing setup snapshot by preserving unselected sections where supported.

`--check-manual-brew true|false`, `-C true|false`

Try to match manually installed `.app` bundles to Homebrew casks during backup. Default: `true`.

`--manual-brew-match ask|never|all`

Manual app matching policy.

- `ask`: prompt per candidate. If approved, add the cask to the Homebrew snapshot section and remove that app from `manual_apps`.
- `never`: record the cask candidate but keep the app in `manual_apps`.
- `all`: accept all detected candidates, add casks, and remove matched apps from `manual_apps`.

In non-interactive mode, `ask` behaves like `never` unless `--yes` is set; with `--yes`, it behaves like `all`.

Manual app backup automatically omits apps already represented by App Store receipts and apps already represented by installed Homebrew casks. Installed cask matching runs before candidate lookup and normalizes punctuation differences, so app names such as `VLC.app` and cask tokens such as `firefox@nightly` can be matched. Standalone apps that are not already installed as casks are still checked for Homebrew cask replacement candidates. Candidate tokens are recorded only after `brew info --cask <candidate>` confirms they are installable casks. Valid candidates are recorded in `brew_cask_candidate` when `manual_brew_match: never`, prompted under `ask`, and moved into the Homebrew cask snapshot when accepted. Cask candidates are matched from one Homebrew cask catalog lookup where possible, with per-app `brew search --casks <name>` fallback when the catalog lookup is unavailable or does not contain a match.

Homebrew cask snapshot rows include the installable cask token in `name`. When a matching `.app` bundle is found, backup also records `display_name`, `path`, and `app_version` so Markdown reports can show the real app name and location without changing restore behavior.

During restore, manual apps with a recorded `brew_cask_candidate` are offered as Homebrew cask installs instead of being treated as plain manual-only items. Restore verifies each candidate with `brew info --cask` before prompting or installing, so stale or invalid candidates are skipped with a warning. Interactive restore prompts per valid candidate. `--yes` installs valid candidate casks automatically, `--no` skips them, and non-interactive restore reports the candidate with instructions to rerun interactively or pass `--yes`. Manual apps without candidates still produce manual restore warnings.

`--versions true|false`, `-V true|false`

Record versions where supported. Default: `true`.

Version lookups can require external package-manager calls. Use `--versions=false` for faster, less network-sensitive backups.

`--dotfiles-path <path>`, `-F <path>`

Add a dotfile path to the setup snapshot. Repeatable.

```bash
mac-setup backup -F ~/.zshrc -F ~/.config/git/config
```

Dotfile backup is allowlist-only. Paths must resolve under `$HOME`. Missing allowlist entries are skipped, so the setup snapshot and copied `files/` folder only record dotfiles that exist at backup time.

The default dotfile allowlist is:

- `~/.zshrc`
- `~/.zprofile`
- `~/.zshenv`
- `~/.bashrc`
- `~/.bash_profile`
- `~/.profile`
- `~/.gitconfig`
- `~/.gitignore_global`
- `~/.editorconfig`
- `~/.hushlogin`
- `~/.inputrc`
- `~/.vimrc`
- `~/.ideavimrc`
- `~/.tmux.conf`
- `~/.screenrc`
- `~/.asdfrc`
- `~/.tool-versions`
- `~/.default-npm-packages`
- `~/.ripgreprc`
- `~/.config/git/config`
- `~/.config/starship.toml`
- `~/.config/bat/config`
- `~/.config/direnv/direnvrc`
- `~/.config/atuin/config.toml`
- `~/.config/zellij/config.kdl`
- `~/.config/ghostty/config`
- `~/.config/wezterm/wezterm.lua`
- `~/.config/alacritty/alacritty.toml`
- `~/.config/kitty/kitty.conf`
- `~/.config/fish/config.fish`
- `~/.config/nvim/init.lua`
- `~/.config/nvim/init.vim`
- `~/.config/helix/config.toml`
- `~/.config/lazygit/config.yml`
- `~/.ssh/config`

Common additional candidates include `~/.config/gh/config.yml`, `~/.npmrc`, `~/.pypirc`, `~/.netrc`, `~/.docker/config.json`, `~/.kube/config`, cloud CLI config under `~/.aws`, `~/.azure`, or `~/.config/gcloud`, and selected files under `~/.config`, `~/.ssh`, or `~/.gnupg`. Review each file before adding it; many common developer dotfiles can contain tokens, private hostnames, registry credentials, or encryption metadata. `~/.ssh/config` is included by default for restore usefulness, but it can contain private host aliases; remove it from generated config if that is too sensitive for your backup.

## Restore Options

`--skip-existing true|false`, `-s true|false`

Skip already installed items. Default: `true`.

`--overwrite true|false`, `-w true|false`

Allow overwrite/reinstall behavior where supported. Default: `false`.

For dotfiles, overwrite first backs up the existing target to:

```text
~/.mac-setup/restore-backups/<timestamp>/
```

`--use-versions true|false`, `-U true|false`

Use backed-up versions where package managers support it. Default: `false`.

Version restore is best-effort.

`--install-missing-tools true|false`, `-T true|false`

Prompt/install missing helpers such as `mas`, `yq`, and `pipx` where supported. Default: `true`.

`--login-check true|false`, `-L true|false`

Check login/auth state where detectable. Default: `true`.

`--appstore-login skip|prompt|pause|require`, `-a skip|prompt|pause|require`

Control behavior when App Store authentication is missing and `mas` is needed.

- `skip`: skip App Store inventory/restore work and continue other sections.
- `prompt`: in interactive mode, offer to open the App Store app, then fail until sign-in is available. In non-interactive mode, fails with guidance instead of skipping.
- `pause`: open/prompt when allowed, mark the workflow as blocked, and resume after sign-in with `mac-setup continue`.
- `require`: fail the workflow until App Store authentication is available.

The CLI does not accept Apple ID credentials and does not attempt to automate Apple sign-in.

`--section <name>`, `-S <name>`

Limit restore or list to a section. Repeatable.

Valid sections:

- `apps`
- `brew`
- `npm`
- `pip`
- `pipx`
- `oh_my_zsh`
- `xcode`
- `dotfiles`
- `manual_apps`

## List Options

`--section <name>`, `-S <name>`

Limit output to a section. Repeatable.

`--format table|yaml|json|md`, `-f table|yaml|json|md`

Output format. Default: `table`.

`--installed-only`, `-e`

Reserved for installed-only filtering.

`--missing-only`, `-m`

Reserved for missing-only filtering.

## Gist Options

`--gist-id <id>`, `-g <id>`

Existing Gist ID.

`--gist-create true|false`

Create a new Gist when no ID is provided.

`--gist-visibility secret|public`

Gist visibility. Default: `secret`.

`--gist-file <name>`

Setup snapshot filename inside the Gist. Default: `mac-setup.backup.yml`.

`--gist-config-file <name>`

Config filename inside the Gist. Default: `mac-setup.config.yml`.

`--gist-pull`

Pull from Gist before running `backup`, `restore`, or `list`.

`--gist-push`

Push to Gist after a successful command.

`--github-login interactive|gh|token|none`

GitHub authentication mode. Default: `gh`.

Auth resolution order:

1. Explicit `--github-token`.
2. Token from `--github-token-env`.
3. Existing `gh auth status`.
4. Interactive `gh auth login`, when allowed.

`--github-token <token>`

Token for non-interactive Gist API access.

Prefer `--github-token-env`; CLI args can appear in shell history and process listings.

`--github-token-env <name>`

Environment variable containing the token. Default: `GITHUB_TOKEN`.

## Short Option Chaining

No-argument short flags can be chained Git-style.

```bash
mac-setup restore -dyq
```

Equivalent to:

```bash
mac-setup restore --dry-run --yes --quiet
```

Value-taking short options must be standalone or last in a chain.

Valid:

```bash
mac-setup backup -i mac-setup.backup.yml
mac-setup backup -dqS brew
mac-setup restore -t 10
```

Invalid:

```bash
mac-setup backup -diq inventory.yml
```

`-i` requires a value and appears before the end of the chain.

## Config File

Generate a starter config:

```bash
mac-setup config generate -o mac-setup.config.yml
```

Example:

```yaml
version: 1
defaults:
  interactive: true
  install_missing_tools: true
  record_versions: true
  restore_versions: false
  skip_existing: true
  overwrite: false
  command_timeout: 30
  caffeinate: true
  resume_file: ~/.mac-setup/resume.yml

storage:
  default_target: icloud
  default_source: icloud
  icloud_folder: "Mac Setup Snapshot"
  github_backend: gist

sources:
  apps: true
  brew: true
  npm: true
  pip: true
  pipx: true
  oh_my_zsh: true
  xcode: true
  dotfiles: true
  manual_apps: true

prepare:
  install_xcode_cli: prompt
  install_homebrew: prompt
  install_yq: prompt
  install_mas: prompt
  install_pipx: prompt
  pause_after_manual_steps: true

backup:
  check_manual_brew: true
  manual_brew_match: ask
  dotfiles:
    - ~/.zshrc
    - ~/.zprofile
    - ~/.zshenv
    - ~/.bashrc
    - ~/.bash_profile
    - ~/.profile
    - ~/.gitconfig
    - ~/.gitignore_global
    - ~/.editorconfig
    - ~/.hushlogin
    - ~/.inputrc
    - ~/.vimrc
    - ~/.ideavimrc
    - ~/.tmux.conf
    - ~/.screenrc
    - ~/.asdfrc
    - ~/.tool-versions
    - ~/.default-npm-packages
    - ~/.ripgreprc
    - ~/.config/git/config
    - ~/.config/starship.toml
    - ~/.config/bat/config
    - ~/.config/direnv/direnvrc
    - ~/.config/atuin/config.toml
    - ~/.config/zellij/config.kdl
    - ~/.config/ghostty/config
    - ~/.config/wezterm/wezterm.lua
    - ~/.config/alacritty/alacritty.toml
    - ~/.config/kitty/kitty.conf
    - ~/.config/fish/config.fish
    - ~/.config/nvim/init.lua
    - ~/.config/nvim/init.vim
    - ~/.config/helix/config.toml
    - ~/.config/lazygit/config.yml
    - ~/.ssh/config

restore:
  appstore_login: prompt
  ignored_items:
    - ref: "brew_cask:visual-studio-code"
      name: "Visual Studio Code"
  dotfiles_mode: skip_existing
  oh_my_zsh_mode: install_if_missing
  xcode:
    install_command_line_tools: true
    install_xcode_app: prompt
    accept_license: prompt

reports:
  path: ""
  format: text
  skip: false
```

CLI flags override config defaults for the current run. `ignore` adds refs to `restore.ignored_items`; backup reapplies those refs to matching rows so future snapshots keep the same restore exclusions visible.

## Wizard Config File

Default path when running from this repo:

```text
mac-setup.wizard.yml
```

Example:

```yaml
version: 1
wizard:
  flows:
    backup:
      enabled: true
      label: "Create or update a setup snapshot"
      default_target: icloud
      prompts:
        dry_run: true
        storage: true
        config: true
        sources: true
        manual_brew_match: true
      sources:
        - id: apps
          label: "App Store apps"
          default: true
        - id: brew
          label: "Homebrew"
          default: true
        - id: npm
          label: "npm globals"
          default: true
        - id: pip
          label: "pip packages"
          default: true
        - id: pipx
          label: "pipx packages"
          default: true
        - id: oh_my_zsh
          label: "Oh My Zsh"
          default: true
        - id: xcode
          label: "Xcode"
          default: true
        - id: dotfiles
          label: "dotfiles"
          default: true
        - id: manual_apps
          label: "manual apps"
          default: true

    restore:
      enabled: true
      label: "Restore from a setup snapshot"
      default_source: icloud
      prompts:
        dry_run: true
        storage: true
        use_config: true
        sources: true
        appstore_login: true
      sources:
        - id: apps
          label: "App Store apps"
          default: true
        - id: brew
          label: "Homebrew"
          default: true
```

The wizard config is committed to the repo and is not generated by normal commands. It is declarative and allowlisted. It can enable or disable the built-in backup/restore flows, relabel them, choose default local/iCloud/GitHub storage, show or hide known prompts, including backup config handling and restore config use, and reorder/relabel/default known sources. Unsupported flow IDs, source IDs, prompt IDs, and enum values are ignored with warnings. It cannot define arbitrary shell commands, hooks, custom restore steps, or executable behavior.

## Setup Snapshot File

Default path:

```text
mac-setup.backup.yml
```

For local and iCloud backups, `backup-list.md` is generated next to `mac-setup.backup.yml` as a readable Markdown summary of the snapshot, and `README.md` is generated with restore instructions.

High-level sections:

```yaml
version: 1
created_at: "..."
updated_at: "..."
host: {}
apps:
  status: ok
  items:
    - id: "123456789"
      ref: "appstore:123456789"
      name: "Example App"
      ignored: false
manual_apps: {}
brew: {}
npm: {}
pip: {}
pipx: {}
oh_my_zsh: {}
xcode: {}
dotfiles: {}
```

Generated setup snapshot files and copied dotfiles are ignored by Git by default.

Restore rows use stable `ref` values:

- `appstore:<id>` for Mac App Store rows.
- `brew_tap:<tap>` for Homebrew tap rows.
- `brew_formula:<formula>` for Homebrew formula rows.
- `brew_cask:<cask>` for Homebrew cask rows.
- `npm:<package>`, `pip:<package>`, and `pipx:<package>` for package rows.
- `dotfile:<normalized-path>-<short-hash>` for dotfile rows.
- `manual:<bundle_id>` for manual app rows with bundle IDs.
- `manual:<normalized-name>-<short-hash>` for manual app rows without bundle IDs.
- `oh_my_zsh:state` and `xcode:state` for section-level restore state.

Ignored rows keep their normal fields plus `ignored: true` and `ignored_at`. They remain in list output and generated Markdown, but restore skips them.

## Dotfiles

Default allowlist:

- `~/.zshrc`
- `~/.gitconfig`
- `~/.gitignore_global`
- `~/.ssh/config`

Backup copies allowlisted files into a setup-snapshot-adjacent `files/` directory.

Restore only writes under `$HOME`, rejects unsafe paths, skips existing files by default, and backs up existing files before overwrite.

## Oh My Zsh

Backup records install state, path, theme, plugins, and `.zshrc` reference.

Restore installs Oh My Zsh only when missing unless overwrite policy allows reinstall. The installer uses unattended-safe flags:

```bash
RUNZSH=no CHSH=no KEEP_ZSHRC=yes
```

`.zshrc` is restored only through the dotfiles flow.

## Xcode

Backup records:

- Command Line Tools state.
- selected developer directory.
- Xcode.app presence and version where detectable.
- license and first-launch status where detectable.
- App Store ID `497799835`.

Restore uses:

```bash
xcode-select --install
```

for missing Command Line Tools.

For Xcode.app, restore uses:

```bash
mas install 497799835
```

when Xcode restore is enabled. `mas` and App Store sign-in are required by default; pass `--xcode=false` or `--appstore-login=skip` only when you explicitly want to skip App Store-backed Xcode restore.

Apple ID login and Xcode account state cannot be fully automated. If App Store authentication is missing, `--appstore-login` determines whether Xcode App Store restore is explicitly skipped, prompts and blocks, pauses for resume, or fails immediately.

## Process Reports

By default, workflow commands print a friendly terminal summary:

```text
Mac Setup Snapshot summary
  restore completed in 12s.
  Mode: dry-run
  Snapshot: mac-setup.backup.yml
  Next step: Review the dry-run output. Run without --dry-run when you are ready to restore.
```

Use `--verbose` to include raw inventory counts in the terminal summary. Use `--report <path>` to write a structured report file. Use `--skip-report` when embedding output in another script and the summary would be noisy.

Backup summaries include an `Open folder` `file://` link for the folder that contains the generated snapshot, readable list, and restore notes. ANSI styling, live progress, summary success/failure colors, and clickable links are human-terminal only. Structured reports and non-TTY output stay plain and stable for scripts.

## Exit Status

- `0`: command completed successfully.
- `1`: command failed.
- `2`: usage or argument parse error.
- `124`: internal external-command timeout code, usually converted into a warning for optional snapshot sources.

## Files

- `mac-setup.backup.yml`: default setup snapshot.
- `backup-list.md`: default human-readable Markdown summary generated from local and iCloud backups.
- `README.md`: restore instructions generated into local and iCloud backup folders.
- `mac-setup.config.yml`: default config.
- `mac-setup.wizard.yml`: tracked wizard menu config.
- `files/`: copied dotfiles next to the setup snapshot.
- `~/.mac-setup/restore-backups/<timestamp>/`: dotfile restore backups.
- `~/.mac-setup/resume.yml`: default prepare/restore resume checklist.
- `docs/PLAN.md`: implementation plan.
- `docs/PROMPT.md`: prompt history.
- `docs/MANUAL.md`: this manual.
- report files: optional user-selected output from `--report`; do not commit reports unless intentionally reviewed.

## Environment

`GITHUB_TOKEN`

Default token environment variable for Gist API access.

`HOMEBREW_*`

The CLI sets Homebrew environment flags for its own Homebrew invocations to reduce unrelated operations.

`TMPDIR`

Used for temporary command output, downloaded installers, and timeout wrappers.

## Safety Notes

- Do not commit generated setup snapshots or copied dotfiles unless you intentionally reviewed them.
- Prefer secret Gists over public Gists.
- Prefer `--github-token-env` over `--github-token`.
- Run `restore --dry-run` first on a newly formatted Mac.
- Use `--versions=false` when you want a faster snapshot without remote version lookups.
- Use `--command-timeout` to keep package-manager hangs bounded.
- Use `mac-setup continue` after interrupting a prepare or restore workflow.

## AI Contributor Notes

AI coding agents should read the repo-local guidance before changing behavior:

- `AGENTS.md`
- `CLAUDE.md`
- `.github/copilot-instructions.md`
- `docs/AI.md`
- `ai/codex-skill/SKILL.md`

When implementing changes, keep restore additive-only, preserve `--dry-run` behavior, avoid `eval`, avoid direct `curl | sh`, quote variables, keep resume/report state free of secrets and copied file contents, and test package-manager flows with mocked commands rather than real installs.

## Examples

Fast snapshot without App Store or remote version lookups:

```bash
mac-setup backup --apps=false --versions=false -t 10
```

Full dry-run restore from GitHub Gist:

```bash
mac-setup restore -g abc123 --gist-pull --dry-run
```

Only restore Homebrew:

```bash
mac-setup restore -S brew --dry-run
mac-setup restore -S brew
```

Backup selected dotfiles:

```bash
mac-setup backup --dotfiles=true -F ~/.zshrc -F ~/.gitconfig
```

Create and upload to a secret GitHub Gist:

```bash
mac-setup backup --gist-create=true --gist-push --github-login=interactive
```
