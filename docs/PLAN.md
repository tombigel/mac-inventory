# mac-setup OSS Project Plan

## Summary

Create a public GitHub repo at `tombigel/mac-setup-snapshot` containing a Bash-first macOS setup snapshot and additive restore CLI.

Defaults:

- Runtime: Bash.
- Config/snapshot format: YAML.
- YAML parser: `yq` v4.
- Test framework: `bats-core`.
- Static check: `shellcheck`.
- Remote sync: default iCloud Drive endpoint, with optional GitHub Gist input/output.
- Restore policy: additive-only by default; no uninstall/delete behavior in v1.

## CLI Scope

Commands:

- `backup`: create or update setup snapshot.
- `prepare`: check/install clean-Mac prerequisites before restore.
- `restore`: restore from setup snapshot.
- `continue`: resume interrupted prepare/restore workflows.
- `status`: show the current resume checklist.
- `list`: list snapshot sections or installed/missing items.
- `doctor`: check tools, login/auth state, Xcode state, GitHub auth state, and readiness.
- `config generate`: generate starter config.
- `gist pull`: download snapshot/config from a Gist.
- `gist push`: upload snapshot/config to a Gist.
- `help`, `--help`, `-h`: show help.
- No args: show help.

Main options:

- `--config`, `-c`
- `--inventory`, `-i`
- `--target icloud|local|github`
- `--source icloud|local|github`
- `--apps`, `-A`
- `--brew`, `-B`
- `--npm`, `-N`
- `--pip`, `-P`
- `--pipx`, `-Q`
- `--oh-my-zsh`, `-O`
- `--xcode`, `-X`
- `--dotfiles`, `-D`
- `--manual-apps`, `-M`
- `--interactive`, `-I`
- `--yes`, `-y`
- `--no`, `-n`
- `--dry-run`, `-d`
- `--verbose`, `-v`
- `--quiet`, `-q`
- `--help`, `-h`
- `--command-timeout`, `-t`
- `--report`, `-r`
- `--report-format`, `-j`
- `--skip-report`, `-R`
- `--skip-prepare`, `--prepare-only`, `--pause-after-prepare`
- `--caffeinate`, `--resume-file`, `--reset-resume`, `--check-only`

Short-option behavior:

- No-arg short flags chain Git-style, for example `mac-setup restore -dyq`.
- Value options may use `-i file.yml`, `-B true`, `-B=false`, or long equivalents.
- A value-consuming short option may appear only at the end of a chain.

Backup options:

- `--update`, `-u`
- `--check-manual-brew=true|false`, `-C true|false`
- `--manual-brew-match=ask|never|all`
- `--versions=true|false`, `-V true|false`
- `--dotfiles-path <path>`, `-F <path>`
- `--output <path>`, `-o <path>`

Restore options:

- `--skip-existing=true|false`, `-s true|false`
- `--overwrite=true|false`, `-w true|false`
- `--use-versions=true|false`, `-U true|false`
- `--install-missing-tools=true|false`, `-T true|false`
- `--login-check=true|false`, `-L true|false`
- `--appstore-login=skip|prompt|pause|require`, `-a skip|prompt|pause|require`
- `--section <name>`, `-S <name>`

Gist options:

- `--gist-id <id>`, `-g <id>`
- `--gist-create=true|false`
- `--gist-visibility secret|public`
- `--gist-file <name>`
- `--gist-config-file <name>`
- `--gist-pull`
- `--gist-push`
- `--github-login=interactive|gh|token|none`
- `--github-token <token>`
- `--github-token-env <name>`

List options:

- `--section <name>`, `-S <name>`
- `--format table|yaml|json|md`, `-f table|yaml|json|md`
- `--installed-only`, `-e`
- `--missing-only`, `-m`

## Inventory, Config, And Safety

Use two YAML files:

- Config: source enablement, restore policy, matching policy, dotfile allowlist.
- Inventory: generated machine state.

Inventory includes host metadata, normalized currently installed App Store apps with matched paths when available, Homebrew taps/top-level formulae/casks, npm/pip/pipx packages, Oh My Zsh state, Xcode and Command Line Tools state, explicit allowlisted dotfiles that exist at backup time, and manual apps with optional Homebrew cask candidates. App-like restore rows include stable refs such as `appstore:<id>`, `brew_cask:<cask>`, and `manual:<bundle_id>` so commands can target them safely. Homebrew casks keep the installable cask token and may include matched app display name, path, and app version for reports.

Local and iCloud backups also generate `backup-list.md` and `README.md` next to `mac-setup.yml`. The list is derived from the YAML snapshot and must not include copied dotfile contents, secrets, or raw command output. The README contains restore instructions and a backup folder file map.

Manual app matching:

- If `--check-manual-brew=true`, default `--manual-brew-match=ask`.
- App Store apps and already-installed Homebrew casks are excluded from `manual_apps`; installed cask matching runs before migration-candidate search and normalizes punctuation differences in cask names. Standalone apps that are not already installed as casks are still searched for replacement cask candidates, but candidate tokens must resolve with `brew info --cask`.
- `ask`: prompt per candidate. If approved, add cask to brew inventory and remove app from `manual_apps`.
- `never`: record candidates but leave app in `manual_apps`.
- `all`: accept all candidates, add casks, and remove matched apps from `manual_apps`.
- Restore prompts to install recorded `brew_cask_candidate` values for manual apps by default; non-interactive restore reports them unless `--yes` is passed.
- Non-interactive `ask` behaves like `never` unless `--yes` is set, then it behaves like `all`.
- `ignore`/`unignore` toggle app-like entries without deleting them. Ignored rows stay visible in the snapshot and Markdown list, are persisted through `restore.ignored_apps` config refs, and are skipped during restore.

Safety rules:

- Restore is additive-only in v1.
- Restore runs prepare preflight by default unless `--skip-prepare=true`.
- Prepare/restore create durable resume state under `~/.mac-setup/resume.yml`.
- `--dry-run` prevents snapshot writes, backup-list/README writes, iCloud history moves, Gist writes, dotfile copies, downloads, installs, upgrades, license acceptance, overwrites, and shell changes.
- Never execute YAML/config/inventory content with `eval` or command substitution.
- Do not implement arbitrary user-defined restore hooks in v1.
- Do not use direct `curl | sh`.
- Dotfile restore defaults to `skip_existing`; explicit overwrite first backs up the target.
- Dotfile backup uses explicit allowlists only and scans for common secret patterns.
- Dotfile restore is confined to `$HOME`.
- `--yes` accepts safe install/upload prompts only.
- External package-manager commands should avoid unrelated work where possible. Homebrew commands run with auto-update, analytics, cleanup, and env hints disabled for the invoked command. Commands that do not provide immediate-fail flags are wrapped with a configurable timeout.
- Prefer `--github-token-env` or `gh` auth over `--github-token`.
- Public repo preparation excludes copied dotfiles, setup snapshots, Gist payloads, and secrets by default.

## Implementation Plan

Create:

```text
bin/mac-setup
lib/args.sh
lib/common.sh
lib/config.sh
lib/inventory.sh
lib/gist.sh
lib/safety.sh
lib/workflow.sh
lib/sources/*.sh
test/
docs/PLAN.md
docs/PROMPT.md
README.md
LICENSE
```

Behavior:

- Parse CLI flags first, merge config defaults second, then command defaults.
- `config generate -o <path>` writes starter YAML config.
- `doctor` checks local package managers, Gist auth, App Store login, Oh My Zsh, and Xcode state.
- Default backup/restore uses the iCloud Drive `Mac Setup Snapshot` bundle when available.
- `prepare` checks Xcode CLT, Homebrew, yq, mas, pipx, GitHub auth, and App Store login in order.
- Gist auth order: explicit token, token env var, `gh auth status`, then interactive `gh auth login` if allowed.
- Gist operations prefer `gh gist`; token fallback uses the GitHub REST API.
- `backup` gathers enabled sources, records versions, writes YAML atomically, and supports `--update`.
- `restore` runs endpoint preflight, prepare preflight, loads the setup snapshot, checks existing installs, then skips/prompts/overwrites according to flags.
- Oh My Zsh restore installs only when missing and uses `RUNZSH=no CHSH=no KEEP_ZSHRC=yes`.
- `.zshrc` restore is handled only through dotfiles.
- Xcode CLT restore uses `xcode-select --install` when missing.

## Tests

Use `bats-core` with mocked commands on `PATH`.

Required coverage:

- Help/no-args behavior.
- Long and short option parsing, including chained flags and invalid chains.
- Config generation.
- Gist auth and dry-run behavior.
- Safety helpers.
- Backup setup snapshot generation for every source.
- Manual app cask matching.
- Restore dry-run and existing detection.
- Prepare dry-run, resume/continue/status, caffeinate, and restore preflight behavior.
- Oh My Zsh and Xcode detection.
- Prompt policy.
- Dotfile copy/restore policy.

Acceptance commands:

```bash
shellcheck bin/mac-setup lib/**/*.sh
bats test
```

## Commit And Push Plan

Use staged task commits:

1. `docs: add project plan and prompt history`
2. `chore: scaffold bash cli project`
3. `feat: add argument parsing and config generation`
4. `feat: add safety helpers`
5. `feat: add gist sync support`
6. `feat: add backup inventory sources`
7. `feat: add restore and doctor workflows`
8. `test: cover cli inventory safety gist and restore behavior`
9. `docs: complete usage examples`

After tests pass, create the public GitHub repo and push `main`.
