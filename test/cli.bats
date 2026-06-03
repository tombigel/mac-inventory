#!/usr/bin/env bats

load helpers/setup

setup() {
  make_mock_bin
  cd "$BATS_TEST_TMPDIR"
}

@test "shows help with no args" {
  run "$BIN"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage:"* ]]
  [[ "$output" == *"wizard"* ]]
}

@test "no args with captured output prints help instead of opening wizard" {
  run bash -c '"$1" | sed -n "1,8p"' _ "$BIN"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage:"* ]]
}

@test "shows help with chained short help flag" {
  run "$BIN" -h
  [ "$status" -eq 0 ]
  [[ "$output" == *"Commands:"* ]]
}

@test "rejects value-taking option in middle of short chain" {
  run "$BIN" backup -diq inventory.yml
  [ "$status" -eq 2 ]
  [[ "$output" == *"value option -i must be standalone or last in a chain"* ]]
}

@test "accepts chained no-argument flags" {
  run "$BIN" backup -d --target local --apps=false --brew=false --npm=false --pip=false --pipx=false --oh-my-zsh=false --xcode=false --dotfiles=false --manual-apps=false
  [ "$status" -eq 0 ]
  [[ "$output" == *"dry-run: would write setup snapshot"* ]]
}

@test "ignore and unignore require exactly one app ref or token" {
  run "$BIN" ignore
  [ "$status" -eq 2 ]
  [[ "$output" == *"ignore requires a ref or token"* ]]

  run "$BIN" ignore one two
  [ "$status" -eq 2 ]
  [[ "$output" == *"unexpected positional argument: two"* ]]
}

@test "generates config file" {
  run "$BIN" config generate -o generated.yml
  [ "$status" -eq 0 ]
  [ -f generated.yml ]
  grep -q "oh_my_zsh: true" generated.yml
  grep -q "xcode: true" generated.yml
  grep -q "check_manual_brew: true" generated.yml
  grep -q "ignored_items: \\[\\]" generated.yml
  grep -q "~/.editorconfig" generated.yml
  grep -q "~/.config/nvim/init.lua" generated.yml
  grep -q "~/.config/lazygit/config.yml" generated.yml
}

@test "config generate dry-run does not write config file" {
  run "$BIN" config generate -o generated.yml --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"dry-run: would write config to generated.yml"* ]]
  [ ! -f generated.yml ]
}

@test "wizard requires an interactive terminal" {
  run "$BIN" wizard
  [ "$status" -eq 2 ]
  [[ "$output" == *"wizard requires an interactive terminal"* ]]
}

@test "wizard config is committed instead of generated" {
  run "$BIN" wizard config generate -o generated-wizard.yml
  [ "$status" -eq 2 ]
  [[ "$output" == *"wizard config is committed in the repo"* ]]
  [ ! -f generated-wizard.yml ]
  grep -q "wizard:" "$PROJECT_ROOT/mac-setup.wizard.yml"
  grep -q "default_target: icloud" "$PROJECT_ROOT/mac-setup.wizard.yml"
  grep -q "default_source: icloud" "$PROJECT_ROOT/mac-setup.wizard.yml"
  grep -q "config: true" "$PROJECT_ROOT/mac-setup.wizard.yml"
  grep -q "use_config: true" "$PROJECT_ROOT/mac-setup.wizard.yml"
}

@test "non-tty output does not include ansi styling" {
  run "$BIN" backup --target local --dry-run --skip-report --apps=false --brew=false --npm=false --pip=false --pipx=false --oh-my-zsh=false --xcode=false --dotfiles=false --manual-apps=false
  [ "$status" -eq 0 ]
  [[ "$output" != *$'\033['* ]]
}

@test "backup applies generated config defaults for manual brew matching" {
  command -v yq >/dev/null 2>&1 || skip "yq is required for config application"
  app_root="$BATS_TEST_TMPDIR/Applications"
  mkdir -p "$app_root"
  make_test_app "$app_root" "Config App" "com.example.config" "1.0" false
  cat >mac-setup.config.yml <<'YAML'
version: 1
defaults:
  record_versions: false
  install_missing_tools: false
backup:
  check_manual_brew: true
  manual_brew_match: never
YAML
  mock_command brew 'while [ "$1" = "env" ] || [ "${1#HOMEBREW_}" != "$1" ]; do shift; done; case "$1 $2 $3" in "list --cask ") : ;; "search --casks /.*/") echo config-app ;; *) exit 0 ;; esac'

  run env MI_APP_DIRS="$app_root" "$BIN" backup --target local --skip-report --apps=false --brew=false --npm=false --pip=false --pipx=false --oh-my-zsh=false --xcode=false --dotfiles=false --manual-apps=true
  [ "$status" -eq 0 ]
  grep -q 'brew_cask_candidate: "config-app"' mac-setup.backup.yml
  grep -q 'selected_brew_cask: ""' mac-setup.backup.yml
}

@test "explicit manual brew matching flags override config defaults" {
  command -v yq >/dev/null 2>&1 || skip "yq is required for config application"
  app_root="$BATS_TEST_TMPDIR/Applications"
  mkdir -p "$app_root"
  make_test_app "$app_root" "Override App" "com.example.override" "1.0" false
  cat >mac-setup.config.yml <<'YAML'
version: 1
defaults:
  record_versions: false
  install_missing_tools: false
backup:
  check_manual_brew: false
  manual_brew_match: never
YAML
  mock_command brew 'while [ "$1" = "env" ] || [ "${1#HOMEBREW_}" != "$1" ]; do shift; done; case "$1 $2 $3" in "tap  ") echo homebrew/core ;; "leaves  ") : ;; "list --cask ") : ;; "list --cask --versions") : ;; "search --casks "*) echo override-app ;; "info --json=v2 --cask") printf "{\"casks\":[{\"token\":\"override-app\",\"deprecated\":false,\"disabled\":false}]}\n" ;; *) exit 0 ;; esac'

  run env MI_APP_DIRS="$app_root" "$BIN" backup --target local --skip-report --apps=false --brew=true --npm=false --pip=false --pipx=false --oh-my-zsh=false --xcode=false --dotfiles=false --manual-apps=true --check-manual-brew=true --manual-brew-match=all
  [ "$status" -eq 0 ]
  grep -q 'name: "override-app"' mac-setup.backup.yml
  grep -q 'ref: "brew_cask:override-app"' mac-setup.backup.yml
  ! grep -q 'ref: "manual_app:com.example.override' mac-setup.backup.yml
}

@test "backup applies generated config dotfile paths" {
  command -v yq >/dev/null 2>&1 || skip "yq is required for config application"
  test_home="$BATS_TEST_TMPDIR/home"
  mkdir -p "$test_home/.config/testapp"
  printf 'setting=true\n' >"$test_home/.config/testapp/config"
  cat >mac-setup.config.yml <<'YAML'
version: 1
sources:
  dotfiles: true
backup:
  dotfiles:
    - ~/.config/testapp/config
    - ~/.config/testapp/missing
YAML

  run env HOME="$test_home" "$BIN" backup --target local --skip-report --apps=false --brew=false --npm=false --pip=false --pipx=false --oh-my-zsh=false --xcode=false --manual-apps=false
  [ "$status" -eq 0 ]
  grep -q 'path: "~/.config/testapp/config"' mac-setup.backup.yml
  ! grep -q 'path: "~/.config/testapp/missing"' mac-setup.backup.yml
  [ -f "files/.config/testapp/config" ]
  [ ! -e "files/.config/testapp/missing" ]
}

@test "backup default dotfiles include expanded low-risk allowlist" {
  test_home="$BATS_TEST_TMPDIR/home"
  mkdir -p "$test_home/.config/starship" "$test_home/.config/nvim" "$test_home/.ssh"
  printf 'root=true\n' >"$test_home/.editorconfig"
  printf 'format = "$all"\n' >"$test_home/.config/starship.toml"
  printf 'vim.opt.number = true\n' >"$test_home/.config/nvim/init.lua"
  printf 'Host example\n  HostName example.test\n' >"$test_home/.ssh/config"

  run env HOME="$test_home" "$BIN" backup --target local --skip-report --apps=false --brew=false --npm=false --pip=false --pipx=false --oh-my-zsh=false --xcode=false --manual-apps=false
  [ "$status" -eq 0 ]
  grep -q 'path: "~/.editorconfig"' mac-setup.backup.yml
  grep -q 'path: "~/.config/starship.toml"' mac-setup.backup.yml
  grep -q 'path: "~/.config/nvim/init.lua"' mac-setup.backup.yml
  grep -q 'path: "~/.ssh/config"' mac-setup.backup.yml
  ! grep -q 'path: "~/.zprofile"' mac-setup.backup.yml
  ! grep -q 'exists: false' mac-setup.backup.yml
  [ -f "files/.editorconfig" ]
  [ -f "files/.config/starship.toml" ]
  [ -f "files/.config/nvim/init.lua" ]
  [ -f "files/.ssh/config" ]
}

@test "backup emits mocked brew and npm inventory" {
  app_root="$BATS_TEST_TMPDIR/Applications"
  mkdir -p "$app_root"
  make_test_app "$app_root" "Visual Studio Code" "com.microsoft.VSCode" "1.2.3" false
  mock_command brew 'while [ "$1" = "env" ] || [ "${1#HOMEBREW_}" != "$1" ]; do shift; done; case "$1 $2" in "tap ") echo homebrew/core ;; "leaves ") echo git ;; "list --versions") echo "git 2.0" ;; "list --cask") echo "visual-studio-code 1.0" ;; *) exit 0 ;; esac'
  mock_command npm 'if [ "$1" = "list" ]; then printf "%s\n" /prefix /prefix/lib/node_modules/typescript; elif [ "$1" = "view" ]; then echo 5.0.0; fi'

  run env MI_APP_DIRS="$app_root" "$BIN" backup --target local --apps=false --pip=false --pipx=false --oh-my-zsh=false --xcode=false --dotfiles=false --manual-apps=false
  [ "$status" -eq 0 ]
  grep -q 'ref: "brew_tap:homebrew/core"' mac-setup.backup.yml
  grep -q 'name: "git"' mac-setup.backup.yml
  grep -q 'ref: "brew_formula:git"' mac-setup.backup.yml
  grep -q 'name: "visual-studio-code"' mac-setup.backup.yml
  grep -q 'display_name: "Visual Studio Code"' mac-setup.backup.yml
  grep -q "path: \"$app_root/Visual Studio Code.app\"" mac-setup.backup.yml
  grep -q 'app_version: "1.2.3"' mac-setup.backup.yml
  grep -q 'name: "typescript"' mac-setup.backup.yml
  grep -q 'ref: "npm:typescript"' mac-setup.backup.yml
  grep -q '| git | 2.0 | false | brew_formula:git |' backup-list.md
  grep -q '| visual-studio-code | Visual Studio Code | '"$app_root"'/Visual Studio Code.app | 1.0 | false | brew_cask:visual-studio-code |' backup-list.md
}

@test "backup shows section progress by default and quiet suppresses it" {
  mock_command brew 'while [ "$1" = "env" ] || [ "${1#HOMEBREW_}" != "$1" ]; do shift; done; case "$1 $2" in "tap ") echo homebrew/core ;; "leaves ") echo git ;; "list --versions") echo "git 2.0" ;; "list --cask") echo "visual-studio-code 1.0" ;; *) exit 0 ;; esac'

  run "$BIN" backup --target local --skip-report --apps=false --brew=true --npm=false --pip=false --pipx=false --oh-my-zsh=false --xcode=false --dotfiles=false --manual-apps=false
  [ "$status" -eq 0 ]
  [[ "$output" == *"Mac Setup Snapshot"* ]]
  [[ "$output" == *"Backup starting"* ]]
  [[ "$output" == *"Next step: Homebrew"* ]]
  [[ "$output" == *"backup: brew..."* ]]
  [[ "$output" == *"[############] 1/1"* ]]
  [[ "$output" == *"backup: brew done"* ]]

  run "$BIN" backup --target local --skip-report --quiet --apps=false --brew=true --npm=false --pip=false --pipx=false --oh-my-zsh=false --xcode=false --dotfiles=false --manual-apps=false
  [ "$status" -eq 0 ]
  [[ "$output" != *"Backup starting"* ]]
  [[ "$output" != *"backup: brew..."* ]]
  [[ "$output" != *"backup: brew done"* ]]
}

@test "backup default summary is friendly and verbose keeps counts" {
  run "$BIN" backup --target local --apps=false --brew=false --npm=false --pip=false --pipx=false --oh-my-zsh=false --xcode=false --dotfiles=false --manual-apps=false
  [ "$status" -eq 0 ]
  [[ "$output" == *"Mac Setup Snapshot summary"* ]]
  [[ "$output" == *"backup completed"* ]]
  [[ "$output" == *"Open folder: file://"* ]]
  [[ "$output" == *"Next step:"* ]]
  [[ "$output" != *"Counts:"* ]]

  run "$BIN" backup --target local --verbose --apps=false --brew=false --npm=false --pip=false --pipx=false --oh-my-zsh=false --xcode=false --dotfiles=false --manual-apps=false
  [ "$status" -eq 0 ]
  [[ "$output" == *"Counts:"* ]]
}

@test "backup verbose includes section command and app matching details" {
  app_root="$BATS_TEST_TMPDIR/Applications"
  mkdir -p "$app_root"
  make_test_app "$app_root" "Verbose App" "com.example.verbose" "1.0" false
  mock_command brew 'while [ "$1" = "env" ] || [ "${1#HOMEBREW_}" != "$1" ]; do shift; done; case "$1 $2 $3" in "list --cask ") : ;; "search --casks /.*/") echo verbose-app ;; *) exit 0 ;; esac'

  run env MI_APP_DIRS="$app_root" "$BIN" backup --target local --skip-report --verbose --apps=false --brew=false --npm=false --pip=false --pipx=false --oh-my-zsh=false --xcode=false --dotfiles=false --manual-apps=true --manual-brew-match=never
  [ "$status" -eq 0 ]
  [[ "$output" == *"backup: inventory temp file"* ]]
  [[ "$output" == *"backup: section manual_apps temp file"* ]]
  [[ "$output" == *"brew list --cask: starting"* ]]
  [[ "$output" == *"brew search --casks: captured"* ]]
  [[ "$output" == *"apps: building installed app index"* ]]
  [[ "$output" == *"apps: indexed Verbose App"* ]]
  [[ "$output" == *"manual_apps: Verbose App matched Homebrew cask candidate verbose-app"* ]]
  [[ "$output" == *"manual_apps: recorded Verbose App"* ]]
}

@test "backup removes temporary files after successful run" {
  app_root="$BATS_TEST_TMPDIR/Applications"
  tmp_root="$BATS_TEST_TMPDIR/tmp"
  mkdir -p "$app_root" "$tmp_root"
  make_test_app "$app_root" "Temp App" "com.example.temp" "1.0" false
  mock_command brew 'while [ "$1" = "env" ] || [ "${1#HOMEBREW_}" != "$1" ]; do shift; done; case "$1 $2 $3" in "list --cask ") : ;; "search --casks /.*/") echo temp-app ;; "info --json=v2 --cask") echo "{\"casks\":[{\"deprecated\":false,\"disabled\":false}]}" ;; *) exit 0 ;; esac'

  run env TMPDIR="$tmp_root" MI_APP_DIRS="$app_root" "$BIN" backup --target local --skip-report --apps=false --brew=false --npm=false --pip=false --pipx=false --oh-my-zsh=false --xcode=false --dotfiles=false --manual-apps=true --manual-brew-match=never
  [ "$status" -eq 0 ]
  leftover_count="$(find "$tmp_root" -maxdepth 1 -type f -name 'mac-setup-*' | wc -l | tr -d ' ')"
  [ "$leftover_count" -eq 0 ]
}

@test "backup writes default markdown list next to local snapshot" {
  command -v yq >/dev/null 2>&1 || skip "yq is required for markdown backup list rendering"

  run "$BIN" backup --target local --skip-report --apps=false --brew=false --npm=false --pip=false --pipx=false --oh-my-zsh=false --xcode=false --dotfiles=false --manual-apps=false
  [ "$status" -eq 0 ]
  [ -f mac-setup.backup.yml ]
  [ -f backup-list.md ]
  [ -f README.md ]
  grep -q '# Mac Setup Snapshot' backup-list.md
  grep -q '# Mac Setup Snapshot Backup' README.md
  grep -q 'mac-setup restore --source local --inventory mac-setup.backup.yml' README.md
  grep -q 'mac-setup wizard' README.md
}

@test "backup generated README includes wizard restore instructions" {
  run "$BIN" backup --target local --skip-report --apps=false --brew=false --npm=false --pip=false --pipx=false --oh-my-zsh=false --xcode=false --dotfiles=false --manual-apps=false
  [ "$status" -eq 0 ]
  [ -f README.md ]
  grep -q 'For a guided restore' README.md
  grep -q 'mac-setup wizard' README.md
  grep -q 'Restore is additive' README.md
  grep -q 'It does not uninstall apps, remove packages, or clean up existing files' README.md
  grep -q 'The wizard asks for dry-run mode, storage endpoint, enabled sources, and App Store login policy' README.md
}

@test "backup dry-run reports markdown list path without writing it" {
  run "$BIN" backup --target local --dry-run --skip-report --apps=false --brew=false --npm=false --pip=false --pipx=false --oh-my-zsh=false --xcode=false --dotfiles=false --manual-apps=false
  [ "$status" -eq 0 ]
  [[ "$output" == *"dry-run backup starting"* ]]
  [[ "$output" == *"dry-run: would write backup list to ./backup-list.md"* ]]
  [[ "$output" == *"dry-run: would write backup README to ./README.md"* ]]
  [ ! -f backup-list.md ]
  [ ! -f README.md ]
}

@test "appstore backup normalizes json output and skips duplicates and stale rows" {
  command -v yq >/dev/null 2>&1 || skip "yq is required for mas json parsing"
  app_root="$BATS_TEST_TMPDIR/Applications"
  mkdir -p "$app_root"
  make_test_app "$app_root" "Current App" "com.example.current" "1.2.3" true
  mock_command mas 'if [ "$1 $2" = "list --json" ]; then printf "%s\n" "{\"adamId\":100,\"trackName\":\"Current App\",\"version\":\"1.2.3\",\"bundleId\":\"com.example.current\"}" "{\"adamId\":100,\"trackName\":\"Current App Old\",\"version\":\"0.9\",\"bundleId\":\"com.example.current\"}" "{\"adamId\":200,\"trackName\":\"Removed App\",\"version\":\"5.0\",\"bundleId\":\"com.example.removed\"}"; elif [ "$1" = "list" ]; then echo "100 Current App (1.2.3)"; else exit 1; fi'

  run env MI_APP_DIRS="$app_root" "$BIN" backup --target local --skip-report --apps=true --brew=false --npm=false --pip=false --pipx=false --oh-my-zsh=false --xcode=false --dotfiles=false --manual-apps=false
  [ "$status" -eq 0 ]
  grep -q 'id: "100"' mac-setup.backup.yml
  grep -q 'ref: "appstore:100"' mac-setup.backup.yml
  grep -q "path: \"$app_root/Current App.app\"" mac-setup.backup.yml
  ! grep -q 'id: "200"' mac-setup.backup.yml
  [ "$(grep -c 'id: "100"' mac-setup.backup.yml)" -eq 1 ]
  grep -q '| 100 | Current App | '"$app_root"'/Current App.app | 1.2.3 | false | appstore:100 |' backup-list.md
}

@test "appstore backup uses matched local bundle name and version" {
  command -v yq >/dev/null 2>&1 || skip "yq is required for mas json parsing"
  app_root="$BATS_TEST_TMPDIR/Applications"
  mkdir -p "$app_root"
  make_test_app "$app_root" "Keynote Creator Studio" "com.apple.Keynote" "15.2.1" true
  make_test_app "$app_root" "Keynote" "com.apple.iWork.Keynote" "14.5" true
  mock_command mas 'if [ "$1 $2" = "list --json" ]; then printf "%s\n" "{\"adamId\":361285480,\"trackName\":\"Keynote\",\"version\":\"15.2\",\"bundleId\":\"com.apple.Keynote\"}" "{\"adamId\":409183694,\"trackName\":\"Keynote\",\"version\":\"14.0\",\"bundleId\":\"com.apple.iWork.Keynote\"}"; elif [ "$1" = "list" ]; then printf "%s\n" "361285480 Keynote (15.2)" "409183694 Keynote (14.0)"; else exit 1; fi'

  run env MI_APP_DIRS="$app_root" "$BIN" backup --target local --skip-report --apps=true --brew=false --npm=false --pip=false --pipx=false --oh-my-zsh=false --xcode=false --dotfiles=false --manual-apps=false
  [ "$status" -eq 0 ]
  grep -q 'name: "Keynote Creator Studio"' mac-setup.backup.yml
  grep -q "path: \"$app_root/Keynote Creator Studio.app\"" mac-setup.backup.yml
  grep -q 'version: "15.2.1"' mac-setup.backup.yml
  grep -q 'name: "Keynote"' mac-setup.backup.yml
  grep -q "path: \"$app_root/Keynote.app\"" mac-setup.backup.yml
  grep -q 'version: "14.5"' mac-setup.backup.yml
  grep -q '| 361285480 | Keynote Creator Studio | '"$app_root"'/Keynote Creator Studio.app | 15.2.1 | false | appstore:361285480 |' backup-list.md
  grep -q '| 409183694 | Keynote | '"$app_root"'/Keynote.app | 14.5 | false | appstore:409183694 |' backup-list.md
}

@test "appstore verbose builds installed app index once across multiple mas rows" {
  command -v yq >/dev/null 2>&1 || skip "yq is required for mas json parsing"
  app_root="$BATS_TEST_TMPDIR/Applications"
  mkdir -p "$app_root"
  make_test_app "$app_root" "First App" "com.example.first" "1.0" true
  make_test_app "$app_root" "Second App" "com.example.second" "2.0" true
  mock_command mas 'if [ "$1 $2" = "list --json" ]; then printf "%s\n" "{\"adamId\":101,\"trackName\":\"First App\",\"version\":\"1.0\",\"bundleId\":\"com.example.first\"}" "{\"adamId\":102,\"trackName\":\"Second App\",\"version\":\"2.0\",\"bundleId\":\"com.example.second\"}"; elif [ "$1" = "list" ]; then printf "%s\n" "101 First App (1.0)" "102 Second App (2.0)"; else exit 1; fi'

  run env MI_APP_DIRS="$app_root" "$BIN" backup --target local --skip-report --verbose --apps=true --brew=false --npm=false --pip=false --pipx=false --oh-my-zsh=false --xcode=false --dotfiles=false --manual-apps=false
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | grep -c 'apps: building installed app index')" -eq 1 ]
  [[ "$output" == *"apps: reusing installed app index"* ]]
  grep -q 'id: "101"' mac-setup.backup.yml
  grep -q 'id: "102"' mac-setup.backup.yml
}

@test "manual apps skip appstore and installed cask duplicates" {
  app_root="$BATS_TEST_TMPDIR/Applications"
  mkdir -p "$app_root"
  make_test_app "$app_root" "Store App" "com.example.store" "1.0" true
  make_test_app "$app_root" "Installed App" "com.example.installed" "2.0" false
  make_test_app "$app_root" "VLC" "org.videolan.vlc" "3.0" false
  make_test_app "$app_root" "Firefox Nightly" "org.mozilla.nightly" "130.0" false
  make_test_app "$app_root" "Standalone App" "com.example.standalone" "3.0" false
  mock_command brew 'while [ "$1" = "env" ] || [ "${1#HOMEBREW_}" != "$1" ]; do shift; done; case "$1 $2 $3" in "list --cask ") printf "%s\n" installed-app vlc firefox@nightly ;; "search --casks /.*/") printf "%s\n" standalone-app ;; *) exit 0 ;; esac'

  run env MI_APP_DIRS="$app_root" "$BIN" backup --target local --skip-report --apps=false --brew=false --npm=false --pip=false --pipx=false --oh-my-zsh=false --xcode=false --dotfiles=false --manual-apps=true --manual-brew-match=never
  [ "$status" -eq 0 ]
  [[ "$output" == *"backup: manual_apps checking"* ]]
  ! grep -q 'Store App' mac-setup.backup.yml
  ! grep -q 'Installed App' mac-setup.backup.yml
  ! grep -q 'VLC' mac-setup.backup.yml
  ! grep -q 'Firefox Nightly' mac-setup.backup.yml
  grep -q 'Standalone App' mac-setup.backup.yml
  grep -q 'brew_cask_candidate: "standalone-app"' mac-setup.backup.yml
}

@test "manual apps search per app when cask catalog is unavailable" {
  app_root="$BATS_TEST_TMPDIR/Applications"
  mkdir -p "$app_root"
  make_test_app "$app_root" "Standalone App" "com.example.standalone" "3.0" false
  mock_command brew 'while [ "$1" = "env" ] || [ "${1#HOMEBREW_}" != "$1" ]; do shift; done; case "$1 $2 $3" in "list --cask ") : ;; "search --casks /.*/") exit 1 ;; "search --casks standalone-app") echo standalone-app ;; *) exit 0 ;; esac'

  run env MI_APP_DIRS="$app_root" "$BIN" backup --target local --skip-report --apps=false --brew=false --npm=false --pip=false --pipx=false --oh-my-zsh=false --xcode=false --dotfiles=false --manual-apps=true --manual-brew-match=never
  [ "$status" -eq 0 ]
  grep -q 'Standalone App' mac-setup.backup.yml
  grep -q 'brew_cask_candidate: "standalone-app"' mac-setup.backup.yml
}

@test "manual apps record non-installed cask candidates as replacements" {
  app_root="$BATS_TEST_TMPDIR/Applications"
  mkdir -p "$app_root"
  make_test_app "$app_root" "Candidate App" "com.example.candidate" "5.0" false
  mock_command brew 'while [ "$1" = "env" ] || [ "${1#HOMEBREW_}" != "$1" ]; do shift; done; case "$1 $2 $3" in "list --cask ") : ;; "search --casks /.*/") echo candidate-app ;; *) exit 0 ;; esac'

  run env MI_APP_DIRS="$app_root" "$BIN" backup --target local --skip-report --apps=false --brew=false --npm=false --pip=false --pipx=false --oh-my-zsh=false --xcode=false --dotfiles=false --manual-apps=true --manual-brew-match=never
  [ "$status" -eq 0 ]
  grep -q 'name: "Candidate App"' mac-setup.backup.yml
  grep -q 'ref: "manual:com.example.candidate"' mac-setup.backup.yml
  grep -q 'brew_cask_candidate: "candidate-app"' mac-setup.backup.yml
  grep -q 'selected_brew_cask: ""' mac-setup.backup.yml
  grep -q '| Candidate App | '"$app_root"'/Candidate App.app | 5.0 | candidate-app | false | manual:com.example.candidate |' backup-list.md
}

@test "manual apps ask mode warns when it cannot prompt without a tty" {
  app_root="$BATS_TEST_TMPDIR/Applications"
  mkdir -p "$app_root"
  make_test_app "$app_root" "Prompt App" "com.example.prompt" "1.0" false
  mock_command brew 'while [ "$1" = "env" ] || [ "${1#HOMEBREW_}" != "$1" ]; do shift; done; case "$1 $2 $3" in "list --cask ") : ;; "search --casks /.*/") echo prompt-app ;; *) exit 0 ;; esac'

  run env MI_APP_DIRS="$app_root" "$BIN" backup --target local --skip-report --apps=false --brew=false --npm=false --pip=false --pipx=false --oh-my-zsh=false --xcode=false --dotfiles=false --manual-apps=true --manual-brew-match=ask
  [ "$status" -eq 0 ]
  [[ "$output" == *"cannot ask about Homebrew cask prompt-app for Prompt App because stdin is not a TTY"* ]]
  grep -q 'name: "Prompt App"' mac-setup.backup.yml
  grep -q 'brew_cask_candidate: "prompt-app"' mac-setup.backup.yml
  grep -q 'selected_brew_cask: ""' mac-setup.backup.yml
}

@test "manual apps without bundle ids get hashed refs" {
  app_root="$BATS_TEST_TMPDIR/Applications"
  mkdir -p "$app_root"
  make_test_app "$app_root" "No Bundle App" "" "1.0" false
  mock_command brew 'while [ "$1" = "env" ] || [ "${1#HOMEBREW_}" != "$1" ]; do shift; done; case "$1 $2 $3" in "list --cask ") : ;; "search --casks /.*/") : ;; *) exit 0 ;; esac'

  run env MI_APP_DIRS="$app_root" "$BIN" backup --target local --skip-report --apps=false --brew=false --npm=false --pip=false --pipx=false --oh-my-zsh=false --xcode=false --dotfiles=false --manual-apps=true --manual-brew-match=never
  [ "$status" -eq 0 ]
  grep -q 'name: "No Bundle App"' mac-setup.backup.yml
  grep -q 'ref: "manual:no-bundle-app-' mac-setup.backup.yml
}

@test "manual apps skip cask candidates that brew info cannot resolve" {
  app_root="$BATS_TEST_TMPDIR/Applications"
  mkdir -p "$app_root"
  make_test_app "$app_root" "Falcon" "com.example.falcon" "1.0" false
  mock_command brew 'while [ "$1" = "env" ] || [ "${1#HOMEBREW_}" != "$1" ]; do shift; done; case "$1 $2 $3" in "list --cask ") : ;; "search --casks /.*/") echo falcon ;; "info --json=v2 --cask") exit 1 ;; *) exit 0 ;; esac'

  run env MI_APP_DIRS="$app_root" "$BIN" backup --target local --skip-report --apps=false --brew=false --npm=false --pip=false --pipx=false --oh-my-zsh=false --xcode=false --dotfiles=false --manual-apps=true --manual-brew-match=never
  [ "$status" -eq 0 ]
  grep -q 'name: "Falcon"' mac-setup.backup.yml
  grep -q 'brew_cask_candidate: ""' mac-setup.backup.yml
  grep -q '| Falcon | '"$app_root"'/Falcon.app | 1.0 |  | false | manual:com.example.falcon |' backup-list.md
}

@test "manual apps skip invalid cask candidate tokens" {
  app_root="$BATS_TEST_TMPDIR/Applications"
  mkdir -p "$app_root"
  make_test_app "$app_root" "Unsafe App" "com.example.unsafe" "1.0" false
  mock_command brew 'while [ "$1" = "env" ] || [ "${1#HOMEBREW_}" != "$1" ]; do shift; done; case "$1 $2 $3" in "list --cask ") : ;; "search --casks /.*/") echo "unsafe app" ;; *) exit 0 ;; esac'

  run env MI_APP_DIRS="$app_root" "$BIN" backup --target local --skip-report --apps=false --brew=false --npm=false --pip=false --pipx=false --oh-my-zsh=false --xcode=false --dotfiles=false --manual-apps=true --manual-brew-match=never
  [ "$status" -eq 0 ]
  grep -q 'name: "Unsafe App"' mac-setup.backup.yml
  grep -q 'brew_cask_candidate: ""' mac-setup.backup.yml
}

@test "manual apps skip deprecated cask candidates" {
  command -v yq >/dev/null 2>&1 || skip "yq is required for brew cask json parsing"
  app_root="$BATS_TEST_TMPDIR/Applications"
  mkdir -p "$app_root"
  make_test_app "$app_root" "Retired App" "com.example.retired" "1.0" false
  mock_command brew 'while [ "$1" = "env" ] || [ "${1#HOMEBREW_}" != "$1" ]; do shift; done; case "$1 $2 $3" in "list --cask ") : ;; "search --casks /.*/") echo retired-app ;; "info --json=v2 --cask") printf "%s\n" "{\"casks\":[{\"deprecated\":true,\"disabled\":false}]}" ;; *) exit 0 ;; esac'

  run env MI_APP_DIRS="$app_root" "$BIN" backup --target local --skip-report --apps=false --brew=false --npm=false --pip=false --pipx=false --oh-my-zsh=false --xcode=false --dotfiles=false --manual-apps=true --manual-brew-match=never
  [ "$status" -eq 0 ]
  grep -q 'name: "Retired App"' mac-setup.backup.yml
  grep -q 'brew_cask_candidate: ""' mac-setup.backup.yml
}

@test "manual apps skip disabled cask candidates" {
  command -v yq >/dev/null 2>&1 || skip "yq is required for brew cask json parsing"
  app_root="$BATS_TEST_TMPDIR/Applications"
  mkdir -p "$app_root"
  make_test_app "$app_root" "Disabled App" "com.example.disabled" "1.0" false
  mock_command brew 'while [ "$1" = "env" ] || [ "${1#HOMEBREW_}" != "$1" ]; do shift; done; case "$1 $2 $3" in "list --cask ") : ;; "search --casks /.*/") echo disabled-app ;; "info --json=v2 --cask") printf "%s\n" "{\"casks\":[{\"deprecated\":false,\"disabled\":true}]}" ;; *) exit 0 ;; esac'

  run env MI_APP_DIRS="$app_root" "$BIN" backup --target local --skip-report --apps=false --brew=false --npm=false --pip=false --pipx=false --oh-my-zsh=false --xcode=false --dotfiles=false --manual-apps=true --manual-brew-match=never
  [ "$status" -eq 0 ]
  grep -q 'name: "Disabled App"' mac-setup.backup.yml
  grep -q 'brew_cask_candidate: ""' mac-setup.backup.yml
}

@test "manual app accepted cask migration is added to brew casks" {
  app_root="$BATS_TEST_TMPDIR/Applications"
  mkdir -p "$app_root"
  make_test_app "$app_root" "Migrate App" "com.example.migrate" "4.0" false
  mock_command brew 'while [ "$1" = "env" ] || [ "${1#HOMEBREW_}" != "$1" ]; do shift; done; case "$1 $2 $3" in "tap  ") echo homebrew/core ;; "leaves  ") : ;; "list --cask ") : ;; "list --cask --versions") : ;; "search --casks /.*/") echo migrate-app ;; *) exit 0 ;; esac'

  run env MI_APP_DIRS="$app_root" "$BIN" backup --target local --skip-report --yes --apps=false --brew=true --npm=false --pip=false --pipx=false --oh-my-zsh=false --xcode=false --dotfiles=false --manual-apps=true --manual-brew-match=ask
  [ "$status" -eq 0 ]
  ! grep -q 'Migrate App' mac-setup.backup.yml
  grep -q 'name: "migrate-app"' mac-setup.backup.yml
  grep -q 'ref: "brew_cask:migrate-app"' mac-setup.backup.yml
  grep -q 'version: "matched-manual-app"' mac-setup.backup.yml
  grep -q 'display_name: "Migrate App"' mac-setup.backup.yml
  grep -q "path: \"$app_root/Migrate App.app\"" mac-setup.backup.yml
  grep -q 'app_version: "4.0"' mac-setup.backup.yml
}

@test "manual app all mode accepts cask migration without yes flag" {
  app_root="$BATS_TEST_TMPDIR/Applications"
  mkdir -p "$app_root"
  make_test_app "$app_root" "All Mode App" "com.example.allmode" "4.0" false
  mock_command brew 'while [ "$1" = "env" ] || [ "${1#HOMEBREW_}" != "$1" ]; do shift; done; case "$1 $2 $3" in "tap  ") echo homebrew/core ;; "leaves  ") : ;; "list --cask ") : ;; "list --cask --versions") : ;; "search --casks /.*/") echo all-mode-app ;; *) exit 0 ;; esac'

  run env MI_APP_DIRS="$app_root" "$BIN" backup --target local --skip-report --apps=false --brew=true --npm=false --pip=false --pipx=false --oh-my-zsh=false --xcode=false --dotfiles=false --manual-apps=true --manual-brew-match=all
  [ "$status" -eq 0 ]
  ! grep -q 'ref: "manual:com.example.allmode"' mac-setup.backup.yml
  grep -q 'name: "all-mode-app"' mac-setup.backup.yml
  grep -q 'ref: "brew_cask:all-mode-app"' mac-setup.backup.yml
}

@test "backup can explicitly skip signed-out App Store inventory" {
  mock_command mas 'case "$1" in list) exit 1 ;; *) echo "unexpected mas $*" >&2; exit 1 ;; esac'
  run "$BIN" backup --target local --appstore-login=skip --apps=true --brew=false --npm=false --pip=false --pipx=false --oh-my-zsh=false --xcode=false --dotfiles=false --manual-apps=false
  [ "$status" -eq 0 ]
  grep -q 'status: "skipped_mas_list_failed"' mac-setup.backup.yml
}

@test "ignore marks appstore ref and unignore clears it" {
  command -v yq >/dev/null 2>&1 || skip "yq is required for ignore edits"
  cat >snapshot.yml <<'YAML'
version: 1
apps:
  status: ok
  items:
    - id: "100"
      ref: "appstore:100"
      name: "Current App"
      path: "/Applications/Current App.app"
      version: "1.0"
YAML

  run "$BIN" ignore appstore:100 --source local --inventory snapshot.yml --config config.yml --skip-report
  [ "$status" -eq 0 ]
  grep -q 'ignored: true' snapshot.yml
  grep -q 'ignored_at:' snapshot.yml
  grep -q 'ignored_items:' config.yml
  grep -q 'ref: appstore:100' config.yml

  run "$BIN" unignore appstore:100 --source local --inventory snapshot.yml --config config.yml --skip-report
  [ "$status" -eq 0 ]
  grep -q 'ignored: false' snapshot.yml
  ! grep -q 'ignored_at:' snapshot.yml
  ! grep -q 'ref: appstore:100' config.yml
}

@test "ignore by manual token adds ref and future backup reapplies config" {
  command -v yq >/dev/null 2>&1 || skip "yq is required for ignore edits"
  cat >snapshot.yml <<'YAML'
version: 1
manual_apps:
  apps:
    - name: "Token App"
      path: "/Applications/Token App.app"
      bundle_id: "com.example.token"
      version: "1.0"
      brew_cask_candidate: ""
      selected_brew_cask: ""
YAML

  run "$BIN" ignore "Token App" --source local --inventory snapshot.yml --config config.yml --skip-report
  [ "$status" -eq 0 ]
  grep -q 'ref: manual:com.example.token' snapshot.yml
  grep -q 'ignored: true' snapshot.yml
  grep -q 'ignored_items:' config.yml
  grep -q 'ref: manual:com.example.token' config.yml

  app_root="$BATS_TEST_TMPDIR/Applications"
  mkdir -p "$app_root"
  make_test_app "$app_root" "Token App" "com.example.token" "2.0" false
  mock_command brew 'while [ "$1" = "env" ] || [ "${1#HOMEBREW_}" != "$1" ]; do shift; done; case "$1 $2 $3" in "list --cask ") : ;; "search --casks /.*/") : ;; *) exit 0 ;; esac'
  run env MI_APP_DIRS="$app_root" "$BIN" backup --target local --inventory new.yml --config config.yml --skip-report --apps=false --brew=false --npm=false --pip=false --pipx=false --oh-my-zsh=false --xcode=false --dotfiles=false --manual-apps=true
  [ "$status" -eq 0 ]
  grep -q 'ref: "manual:com.example.token"' new.yml
  grep -q 'ignored: true' new.yml
}

@test "ignore rejects ambiguous app tokens without editing" {
  command -v yq >/dev/null 2>&1 || skip "yq is required for ignore edits"
  cat >snapshot.yml <<'YAML'
version: 1
apps:
  status: ok
  items:
    - id: "100"
      ref: "appstore:100"
      name: "Same App"
      path: "/Applications/Same App.app"
      version: "1.0"
manual_apps:
  apps:
    - name: "Same App"
      ref: "manual:com.example.same"
      path: "/Users/me/Applications/Same App.app"
      bundle_id: "com.example.same"
      version: "1.0"
YAML

  run "$BIN" ignore "Same App" --source local --inventory snapshot.yml --config config.yml --skip-report
  [ "$status" -eq 2 ]
  [[ "$output" == *"multiple snapshot entries matched"* ]]
  ! grep -q 'ignored:' snapshot.yml
  [ ! -f config.yml ]
}

@test "ignore marks non-app snapshot entries" {
  command -v yq >/dev/null 2>&1 || skip "yq is required for ignore edits"
  cat >snapshot.yml <<'YAML'
version: 1
brew:
  formulae:
    - name: "git"
      ref: "brew_formula:git"
      version: "2.0"
npm:
  globals:
    - name: "typescript"
      ref: "npm:typescript"
      version: "5.0.0"
dotfiles:
  files:
    - path: "~/.zshrc"
      ref: "dotfile:zshrc-12345678"
      exists: true
      backup_path: "files/.zshrc"
YAML

  run "$BIN" ignore brew_formula:git --source local --inventory snapshot.yml --config config.yml --skip-report
  [ "$status" -eq 0 ]
  grep -q 'ignored: true' snapshot.yml
  grep -q 'ignored_items:' config.yml
  grep -q 'ref: brew_formula:git' config.yml

  run "$BIN" ignore npm:typescript --source local --inventory snapshot.yml --config config.yml --skip-report
  [ "$status" -eq 0 ]
  grep -q 'ref: npm:typescript' config.yml

  run "$BIN" ignore dotfile:zshrc-12345678 --source local --inventory snapshot.yml --config config.yml --skip-report
  [ "$status" -eq 0 ]
  grep -q 'ref: dotfile:zshrc-12345678' config.yml
}

@test "restore skips ignored appstore brew cask and manual app rows" {
  command -v yq >/dev/null 2>&1 || skip "yq is required for restore"
  cat >snapshot.yml <<'YAML'
version: 1
apps:
  status: ok
  items:
    - id: "100"
      ref: "appstore:100"
      name: "Ignored Store"
      ignored: true
brew:
  taps: []
  formulae: []
  casks:
    - name: "ignored-cask"
      ref: "brew_cask:ignored-cask"
      display_name: "Ignored Cask"
      ignored: true
manual_apps:
  apps:
    - name: "Ignored Manual"
      ref: "manual:com.example.ignored"
      bundle_id: "com.example.ignored"
      ignored: true
YAML
  mock_command mas 'if [ "$1" = "list" ]; then :; else echo "unexpected mas $*" >&2; exit 1; fi'
  mock_command brew 'while [ "$1" = "env" ] || [ "${1#HOMEBREW_}" != "$1" ]; do shift; done; case "$1 $2" in "tap ") : ;; *) echo "unexpected brew $*" >&2; exit 1 ;; esac'

  run "$BIN" restore --source local --inventory snapshot.yml --skip-prepare=true --skip-report --apps=true --brew=true --npm=false --pip=false --pipx=false --oh-my-zsh=false --xcode=false --dotfiles=false --manual-apps=true
  [ "$status" -eq 0 ]
  [[ "$output" == *"ignored appstore:100"* ]]
  [[ "$output" == *"ignored brew_cask:ignored-cask"* ]]
  [[ "$output" == *"ignored manual:com.example.ignored"* ]]
}

@test "skip-report suppresses final process report" {
  run "$BIN" backup --target local --dry-run --skip-report --apps=false --brew=false --npm=false --pip=false --pipx=false --oh-my-zsh=false --xcode=false --dotfiles=false --manual-apps=false
  [ "$status" -eq 0 ]
  [[ "$output" != *"Process report"* ]]
}

@test "writes markdown report when requested" {
  run "$BIN" backup --target local --dry-run --report "$BATS_TEST_TMPDIR/report.md" --report-format md --apps=false --brew=false --npm=false --pip=false --pipx=false --oh-my-zsh=false --xcode=false --dotfiles=false --manual-apps=false
  [ "$status" -eq 0 ]
  [ -f "$BATS_TEST_TMPDIR/report.md" ]
  grep -q '# Mac Setup Snapshot Process Report' "$BATS_TEST_TMPDIR/report.md"
}

@test "list can render human-readable markdown" {
  command -v yq >/dev/null 2>&1 || skip "yq is required for markdown list rendering"
  cat >snapshot.yml <<'YAML'
version: 1
created_at: "2026-06-01T00:00:00Z"
host:
  hostname: "test-mac"
brew:
  formulae:
    - name: "git"
      version: "2.0"
  casks: []
npm:
  globals:
    - name: "typescript"
      version: "5.0.0"
YAML

  run "$BIN" list --source local --inventory snapshot.yml --format md
  [ "$status" -eq 0 ]
  [[ "$output" == *"# Mac Setup Snapshot"* ]]
  [[ "$output" == *"## Host"* ]]
  [[ "$output" == *"| hostname | test-mac |"* ]]
  [[ "$output" == *"## Homebrew Formulae"* ]]
  [[ "$output" == *"| git | 2.0 |"* ]]
  [[ "$output" == *"## npm Globals"* ]]
  [[ "$output" == *"| typescript | 5.0.0 |"* ]]
}

@test "list markdown shows refs as the last column and ignored state" {
  command -v yq >/dev/null 2>&1 || skip "yq is required for markdown list rendering"
  cat >snapshot.yml <<'YAML'
version: 1
apps:
  status: ok
  items:
    - id: "100"
      ref: "appstore:100"
      name: "Current App"
      ignored: true
brew:
  taps:
    - name: "homebrew/core"
      ref: "brew_tap:homebrew/core"
      ignored: false
  formulae:
    - name: "git"
      ref: "brew_formula:git"
      version: "2.0"
      ignored: true
  casks:
    - name: "visual-studio-code"
      ref: "brew_cask:visual-studio-code"
      display_name: "Visual Studio Code"
      ignored: false
npm:
  globals:
    - name: "typescript"
      ref: "npm:typescript"
      version: "5.0.0"
      ignored: true
dotfiles:
  files:
    - path: "~/.zshrc"
      ref: "dotfile:zshrc-12345678"
      exists: true
      backup_path: "files/.zshrc"
      ignored: false
manual_apps:
  apps:
    - name: "Manual App"
      ref: "manual:com.example.manual"
      ignored: true
YAML

  run "$BIN" list --source local --inventory snapshot.yml --format md
  [ "$status" -eq 0 ]
  [[ "$output" == *"| ID | Name | Path | Version | Ignored | Ref |"* ]]
  [[ "$output" == *"| 100 | Current App |"* ]]
  [[ "$output" == *"| visual-studio-code | Visual Studio Code |"* ]]
  [[ "$output" == *"| Manual App |"* ]]
  [[ "$output" == *"| true | appstore:100 |"* ]]
  [[ "$output" == *"| false | brew_cask:visual-studio-code |"* ]]
  [[ "$output" == *"| true | manual:com.example.manual |"* ]]
  [[ "$output" == *"| homebrew/core | false | brew_tap:homebrew/core |"* ]]
  [[ "$output" == *"| git | 2.0 | true | brew_formula:git |"* ]]
  [[ "$output" == *"| typescript | 5.0.0 | true | npm:typescript |"* ]]
  [[ "$output" == *"| ~/.zshrc | true | files/.zshrc | false | dotfile:zshrc-12345678 |"* ]]
}
