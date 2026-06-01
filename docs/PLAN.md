# mac-inventory OSS Project Plan

## Summary

Create a public GitHub repo at `tombigel/mac-inventory` containing a Bash-first macOS backup/restore inventory CLI.

Defaults:

- Runtime: Bash.
- Config/inventory format: YAML.
- YAML parser: `yq` v4.
- Test framework: `bats-core`.
- Static check: `shellcheck`.
- Remote sync: optional GitHub Gist input/output.
- Restore policy: additive-only by default; no uninstall/delete behavior in v1.

## CLI Scope

Commands:

- `backup`: create or update inventory.
- `restore`: restore from inventory.
- `list`: list inventory or installed/missing items.
- `doctor`: check tools, login/auth state, Xcode state, GitHub auth state, and readiness.
- `config generate`: generate starter config.
- `gist pull`: download inventory/config from a Gist.
- `gist push`: upload inventory/config to a Gist.
- `help`, `--help`, `-h`: show help.
- No args: show help.

Main options:

- `--config`, `-c`
- `--inventory`, `-i`
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

Short-option behavior:

- No-arg short flags chain Git-style, for example `mac-inventory restore -dyq`.
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
- `--format table|yaml|json`, `-f table|yaml|json`
- `--installed-only`, `-e`
- `--missing-only`, `-m`

## Inventory, Config, And Safety

Use two YAML files:

- Config: source enablement, restore policy, matching policy, dotfile allowlist.
- Inventory: generated machine state.

Inventory includes host metadata, App Store apps, Homebrew taps/formulae/casks, npm/pip/pipx packages, Oh My Zsh state, Xcode and Command Line Tools state, explicit allowlisted dotfiles, and manual apps with optional Homebrew cask candidates.

Manual app matching:

- If `--check-manual-brew=true`, default `--manual-brew-match=ask`.
- `ask`: prompt per candidate. If approved, add cask to brew inventory and remove app from `manual_apps`.
- `never`: record candidates but leave app in `manual_apps`.
- `all`: accept all candidates, add casks, and remove matched apps from `manual_apps`.
- Non-interactive `ask` behaves like `never` unless `--yes` is set, then it behaves like `all`.

Safety rules:

- Restore is additive-only in v1.
- `--dry-run` prevents inventory writes, Gist writes, dotfile copies, downloads, installs, upgrades, license acceptance, overwrites, and shell changes.
- Never execute YAML/config/inventory content with `eval` or command substitution.
- Do not implement arbitrary user-defined restore hooks in v1.
- Do not use direct `curl | sh`.
- Dotfile restore defaults to `skip_existing`; explicit overwrite first backs up the target.
- Dotfile backup uses explicit allowlists only and scans for common secret patterns.
- Dotfile restore is confined to `$HOME`.
- `--yes` accepts safe install/upload prompts only.
- External package-manager commands should avoid unrelated work where possible. Homebrew commands run with auto-update, analytics, cleanup, and env hints disabled for the invoked command. Commands that do not provide immediate-fail flags are wrapped with a configurable timeout.
- Prefer `--github-token-env` or `gh` auth over `--github-token`.
- Public repo preparation excludes copied dotfiles, inventories, Gist payloads, and secrets by default.

## Implementation Plan

Create:

```text
bin/mac-inventory
lib/args.sh
lib/common.sh
lib/config.sh
lib/inventory.sh
lib/gist.sh
lib/safety.sh
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
- Gist auth order: explicit token, token env var, `gh auth status`, then interactive `gh auth login` if allowed.
- Gist operations prefer `gh gist`; token fallback uses the GitHub REST API.
- `backup` gathers enabled sources, records versions, writes YAML atomically, and supports `--update`.
- `restore` loads inventory, checks existing installs, then skips/prompts/overwrites according to flags.
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
- Backup inventory generation for every source.
- Manual app cask matching.
- Restore dry-run and existing detection.
- Oh My Zsh and Xcode detection.
- Prompt policy.
- Dotfile copy/restore policy.

Acceptance commands:

```bash
shellcheck bin/mac-inventory lib/**/*.sh
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
