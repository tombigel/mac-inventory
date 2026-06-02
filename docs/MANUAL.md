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
mac-setup config generate [options]
mac-setup gist pull [options]
mac-setup gist push [options]
mac-setup help
mac-setup --help
mac-setup -h
```

Calling `mac-setup` without arguments prints help.

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
mac-setup backup -i mac-setup.yml
mac-setup backup --target local
mac-setup backup --target github --gist-create=true --github-login=interactive
mac-setup backup --update
mac-setup backup --apps=false --versions=false
mac-setup backup --check-manual-brew=true --manual-brew-match=ask
mac-setup backup --gist-create=true --gist-push
```

By default, backup includes App Store apps, Homebrew, npm globals, pip, pipx, Oh My Zsh, Xcode, dotfiles, and manual apps.

Use `--dry-run` to print the snapshot that would be generated without writing it.

### `restore`

Restore from an existing setup snapshot file.

```bash
mac-setup restore
mac-setup restore -i mac-setup.yml --dry-run
mac-setup restore --source local -i mac-setup.yml --dry-run
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

`--dry-run` prevents installs, downloads, Gist writes, snapshot writes, dotfile copies, overwrites, shell changes, and license acceptance. If `--report <path>` is explicitly passed, only that report artifact is written.

Mac App Store backup and restore require `mas` plus a signed-in App Store app when the App Store source is enabled. The CLI never asks for Apple ID credentials and cannot automate Apple sign-in. By default, it tries to make `mas` usable and then fails until App Store sign-in is available. Use `--apps=false` or `--appstore-login=skip` only when you explicitly want to omit App Store apps.

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
mac-setup list -i mac-setup.yml
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

## Endpoint Options

`--target icloud|local|github`

Backup endpoint. Default: `icloud`.

- `icloud`: write the setup snapshot bundle to iCloud Drive.
- `local`: write `mac-setup.yml`, optional config, and copied `files/` in the current directory or explicit paths.
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

The iCloud endpoint stores `mac-setup.yml`, optional `mac-setup.config.yml`, copied `files/`, and `metadata.yml` in one bundle folder. Before overwriting an existing bundle, backup moves current bundle files into `history/YYYYMMDDTHHMMSSZ/`.

If iCloud Drive is missing or inaccessible, interactive commands offer local/GitHub fallback where possible. Non-interactive commands fail clearly unless a non-iCloud endpoint is explicit.

### `gist pull`

Download setup snapshot and config files from a GitHub Gist.

```bash
mac-setup gist pull -g abc123
mac-setup gist pull --gist-id abc123 --inventory mac-setup.yml --config mac-setup.config.yml
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

`--inventory <path>`, `-i <path>`

Setup snapshot file path. Default: `mac-setup.yml`.

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

`--yes`, `-y`

Accept safe prompts. This does not silently approve suspicious path restores, destructive actions, public Gist publication, or unexpected privilege escalation.

`--no`, `-n`

Reject optional prompts.

`--dry-run`, `-d`

Print planned work without side effects.

An explicit `--report <path>` may still write the requested report artifact during dry-run.

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

Suppress the final process report. Errors and warnings still print through normal command output.

Reports include command, status, dry-run state, setup snapshot path, duration, snapshot counts where available, and warnings or manual actions such as missing App Store authentication. Reports must not include secrets, tokens, copied dotfile contents, or raw command output.

## Backup Options

`--update`, `-u`

Merge into an existing setup snapshot by preserving unselected sections where supported.

`--check-manual-brew true|false`, `-C true|false`

Try to match manually installed `.app` bundles to Homebrew casks during backup.

`--manual-brew-match ask|never|all`

Manual app matching policy.

- `ask`: prompt per candidate. If approved, add the cask to the Homebrew snapshot section and remove that app from `manual_apps`.
- `never`: record the cask candidate but keep the app in `manual_apps`.
- `all`: accept all detected candidates, add casks, and remove matched apps from `manual_apps`.

In non-interactive mode, `ask` behaves like `never` unless `--yes` is set; with `--yes`, it behaves like `all`.

`--versions true|false`, `-V true|false`

Record versions where supported. Default: `true`.

Version lookups can require external package-manager calls. Use `--versions=false` for faster, less network-sensitive backups.

`--dotfiles-path <path>`, `-F <path>`

Add a dotfile path to the setup snapshot. Repeatable.

```bash
mac-setup backup -F ~/.zshrc -F ~/.config/git/config
```

Dotfile backup is allowlist-only. Paths must resolve under `$HOME`.

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

`--format table|yaml|json`, `-f table|yaml|json`

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

Setup snapshot filename inside the Gist. Default: `mac-setup.yml`.

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
mac-setup backup -i mac-setup.yml
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
  check_manual_brew: false
  manual_brew_match: ask
  dotfiles:
    - ~/.zshrc
    - ~/.gitconfig
    - ~/.gitignore_global
    - ~/.ssh/config

restore:
  appstore_login: prompt
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

CLI flags override config defaults for the current run.

## Setup Snapshot File

Default path:

```text
mac-setup.yml
```

High-level sections:

```yaml
version: 1
created_at: "..."
updated_at: "..."
host: {}
apps:
  status: ok
  items: []
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

By default, workflow commands print a final process report:

```text
Process report
  command: restore
  status: ok
  dry_run: true
  inventory: mac-setup.yml
  duration_seconds: 12
  counts: apps=0 brew_formulae=47 brew_casks=43 npm=3 pip=4 pipx=0 manual_apps=105 dotfiles=4
  warnings/actions:
    - [warn] apps/appstore_not_logged_in: App Store access is unavailable; restore cannot use mas until App Store authentication succeeds
```

Use `--report <path>` to write the report to a file. Use `--skip-report` when embedding output in another script and the summary would be noisy.

## Exit Status

- `0`: command completed successfully.
- `1`: command failed.
- `2`: usage or argument parse error.
- `124`: internal external-command timeout code, usually converted into a warning for optional snapshot sources.

## Files

- `mac-setup.yml`: default setup snapshot.
- `mac-setup.config.yml`: default config.
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
