# mac-inventory Manual

## Name

`mac-inventory` - inventory and restore reinstallable macOS software, shell tooling, developer tooling, selected dotfiles, and optional GitHub Gist storage.

## Synopsis

```bash
mac-inventory <command> [options]
mac-inventory backup [options]
mac-inventory restore [options]
mac-inventory list [options]
mac-inventory doctor [options]
mac-inventory config generate [options]
mac-inventory gist pull [options]
mac-inventory gist push [options]
mac-inventory help
mac-inventory --help
mac-inventory -h
```

Calling `mac-inventory` without arguments prints help.

## Description

`mac-inventory` is a Bash CLI for preparing a Mac rebuild. It creates a YAML inventory of installed software and selected user configuration, then uses that inventory to run an additive restore.

Restore is additive-only in v1. It installs, copies, checks, and reports. It does not uninstall packages, delete applications, clean directories, or remove software that is not in the inventory.

## Commands

### `backup`

Create an inventory file from the current Mac.

```bash
mac-inventory backup
mac-inventory backup -i mac-inventory.yml
mac-inventory backup --update
mac-inventory backup --apps=false --versions=false
mac-inventory backup --check-manual-brew=true --manual-brew-match=ask
mac-inventory backup --gist-create=true --gist-push
```

By default, backup includes App Store apps, Homebrew, npm globals, pip, pipx, Oh My Zsh, Xcode, dotfiles, and manual apps.

Use `--dry-run` to print the inventory that would be generated without writing it.

### `restore`

Restore from an existing inventory file.

```bash
mac-inventory restore
mac-inventory restore -i mac-inventory.yml --dry-run
mac-inventory restore -S brew
mac-inventory restore --skip-existing=true
mac-inventory restore --overwrite=true -S dotfiles
mac-inventory restore -g abc123 --gist-pull --dry-run
```

Restore checks existing installations first. By default, existing items are skipped. Dotfiles are skipped unless `--overwrite=true` is used; when overwriting, the current file is backed up first.

`--dry-run` prevents installs, downloads, Gist writes, dotfile copies, overwrites, shell changes, and license acceptance.

### `list`

List inventory sections.

```bash
mac-inventory list
mac-inventory list -i mac-inventory.yml
mac-inventory list -S brew
mac-inventory list -S manual_apps
mac-inventory list --format yaml
mac-inventory list --format json
```

Formats:

- `table`: default, prints section names or selected section labels.
- `yaml`: prints the full inventory or selected YAML sections.
- `json`: converts inventory to JSON with `yq`.

### `doctor`

Check local readiness.

```bash
mac-inventory doctor
mac-inventory doctor --command-timeout 5
```

Checks include:

- `brew`
- `yq`
- `mas`
- `npm`
- `pip3`
- `pipx`
- GitHub/Gist authentication
- App Store `mas account`
- Oh My Zsh installation
- Xcode Command Line Tools
- selected developer directory
- Xcode license and first-launch status where detectable

### `config generate`

Generate a starter YAML config.

```bash
mac-inventory config generate
mac-inventory config generate -o mac-inventory.config.yml
mac-inventory config generate --output ./config.yml
mac-inventory config generate --dry-run
```

If no output path is provided, the default is `mac-inventory.config.yml`.

If the target file already exists, interactive mode prompts before overwriting. Non-interactive mode fails conservatively unless `--yes` allows the write.

### `gist pull`

Download inventory and config files from a GitHub Gist.

```bash
mac-inventory gist pull -g abc123
mac-inventory gist pull --gist-id abc123 --inventory mac-inventory.yml --config mac-inventory.config.yml
mac-inventory gist pull -g abc123 --github-login=interactive
```

Pull currently prefers authenticated `gh` usage. Existing local files are backed up before replacement.

### `gist push`

Upload inventory and/or config files to a GitHub Gist.

```bash
mac-inventory gist push -g abc123
mac-inventory gist push --gist-create=true
mac-inventory gist push -g abc123 --github-token-env GITHUB_TOKEN
mac-inventory gist push -g abc123 --github-login=interactive
```

Secret Gists are the default. Public Gist upload requires explicit `--gist-visibility public` and confirmation policy.

Before upload, files are scanned for common secret patterns. Tokens are masked in logs and are not written to inventory or config files.

## Global Options

### Files

`--config <path>`, `-c <path>`

Config file path. Default: `mac-inventory.config.yml`.

`--inventory <path>`, `-i <path>`

Inventory file path. Default: `mac-inventory.yml`.

`--output <path>`, `-o <path>`

Output path for `backup` and `config generate`. For backup, this is an alias for `--inventory`.

### Source Selection

Boolean source options accept `true` or `false`.

```bash
mac-inventory backup --apps=false --brew=true
mac-inventory restore -B false -N true
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
mac-inventory backup -t 10
mac-inventory restore --command-timeout 5 --dry-run
```

Homebrew commands are invoked with these environment variables where possible:

```bash
HOMEBREW_NO_AUTO_UPDATE=1
HOMEBREW_NO_ANALYTICS=1
HOMEBREW_NO_INSTALL_CLEANUP=1
HOMEBREW_NO_ENV_HINTS=1
```

## Backup Options

`--update`, `-u`

Merge into an existing inventory by preserving unselected sections where supported.

`--check-manual-brew true|false`, `-C true|false`

Try to match manually installed `.app` bundles to Homebrew casks during backup.

`--manual-brew-match ask|never|all`

Manual app matching policy.

- `ask`: prompt per candidate. If approved, add the cask to Homebrew inventory and remove that app from `manual_apps`.
- `never`: record the cask candidate but keep the app in `manual_apps`.
- `all`: accept all detected candidates, add casks, and remove matched apps from `manual_apps`.

In non-interactive mode, `ask` behaves like `never` unless `--yes` is set; with `--yes`, it behaves like `all`.

`--versions true|false`, `-V true|false`

Record versions where supported. Default: `true`.

Version lookups can require external package-manager calls. Use `--versions=false` for faster, less network-sensitive backups.

`--dotfiles-path <path>`, `-F <path>`

Add a dotfile path to inventory. Repeatable.

```bash
mac-inventory backup -F ~/.zshrc -F ~/.config/git/config
```

Dotfile backup is allowlist-only. Paths must resolve under `$HOME`.

## Restore Options

`--skip-existing true|false`, `-s true|false`

Skip already installed items. Default: `true`.

`--overwrite true|false`, `-w true|false`

Allow overwrite/reinstall behavior where supported. Default: `false`.

For dotfiles, overwrite first backs up the existing target to:

```text
~/.mac-inventory/restore-backups/<timestamp>/
```

`--use-versions true|false`, `-U true|false`

Use backed-up versions where package managers support it. Default: `false`.

Version restore is best-effort.

`--install-missing-tools true|false`, `-T true|false`

Prompt/install missing helpers such as `mas`, `yq`, and `pipx` where supported. Default: `true`.

`--login-check true|false`, `-L true|false`

Check login/auth state where detectable. Default: `true`.

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

Inventory filename inside the Gist. Default: `mac-inventory.yml`.

`--gist-config-file <name>`

Config filename inside the Gist. Default: `mac-inventory.config.yml`.

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
mac-inventory restore -dyq
```

Equivalent to:

```bash
mac-inventory restore --dry-run --yes --quiet
```

Value-taking short options must be standalone or last in a chain.

Valid:

```bash
mac-inventory backup -i mac-inventory.yml
mac-inventory backup -dqS brew
mac-inventory restore -t 10
```

Invalid:

```bash
mac-inventory backup -diq inventory.yml
```

`-i` requires a value and appears before the end of the chain.

## Config File

Generate a starter config:

```bash
mac-inventory config generate -o mac-inventory.config.yml
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
```

CLI flags override config defaults for the current run.

## Inventory File

Default path:

```text
mac-inventory.yml
```

High-level sections:

```yaml
version: 1
created_at: "..."
updated_at: "..."
host: {}
apps: []
manual_apps: {}
brew: {}
npm: {}
pip: {}
pipx: {}
oh_my_zsh: {}
xcode: {}
dotfiles: {}
```

Generated inventory files and copied dotfiles are ignored by Git by default.

## Dotfiles

Default allowlist:

- `~/.zshrc`
- `~/.gitconfig`
- `~/.gitignore_global`
- `~/.ssh/config`

Backup copies allowlisted files into an inventory-adjacent `files/` directory.

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

For Xcode.app, restore prefers:

```bash
mas install 497799835
```

when `mas` is available.

Apple ID login and Xcode account state cannot be fully automated; the CLI reports actionable warnings where possible.

## Exit Status

- `0`: command completed successfully.
- `1`: command failed.
- `2`: usage or argument parse error.
- `124`: internal external-command timeout code, usually converted into a warning for optional inventory sources.

## Files

- `mac-inventory.yml`: default inventory.
- `mac-inventory.config.yml`: default config.
- `files/`: copied dotfiles next to the inventory.
- `~/.mac-inventory/restore-backups/<timestamp>/`: dotfile restore backups.
- `docs/PLAN.md`: implementation plan.
- `docs/PROMPT.md`: prompt history.
- `docs/MANUAL.md`: this manual.

## Environment

`GITHUB_TOKEN`

Default token environment variable for Gist API access.

`HOMEBREW_*`

The CLI sets Homebrew environment flags for its own Homebrew invocations to reduce unrelated operations.

`TMPDIR`

Used for temporary command output, downloaded installers, and timeout wrappers.

## Safety Notes

- Do not commit generated inventory or copied dotfiles unless you intentionally reviewed them.
- Prefer secret Gists over public Gists.
- Prefer `--github-token-env` over `--github-token`.
- Run `restore --dry-run` first on a newly formatted Mac.
- Use `--versions=false` when you want a faster inventory without remote version lookups.
- Use `--command-timeout` to keep package-manager hangs bounded.

## Examples

Fast inventory without App Store or remote version lookups:

```bash
mac-inventory backup --apps=false --versions=false -t 10
```

Full dry-run restore from Gist:

```bash
mac-inventory restore -g abc123 --gist-pull --dry-run
```

Only restore Homebrew:

```bash
mac-inventory restore -S brew --dry-run
mac-inventory restore -S brew
```

Backup selected dotfiles:

```bash
mac-inventory backup --dotfiles=true -F ~/.zshrc -F ~/.gitconfig
```

Create and upload a secret Gist:

```bash
mac-inventory backup --gist-create=true --gist-push --github-login=interactive
```

