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

@test "generates config file" {
  run "$BIN" config generate -o generated.yml
  [ "$status" -eq 0 ]
  [ -f generated.yml ]
  grep -q "oh_my_zsh: true" generated.yml
  grep -q "xcode: true" generated.yml
}

@test "backup emits mocked brew and npm inventory" {
  mock_command brew 'while [ "$1" = "env" ] || [ "${1#HOMEBREW_}" != "$1" ]; do shift; done; case "$1 $2" in "tap ") echo homebrew/core ;; "leaves ") echo git ;; "list --versions") echo "git 2.0" ;; "list --cask") echo "visual-studio-code 1.0" ;; *) exit 0 ;; esac'
  mock_command npm 'if [ "$1" = "list" ]; then printf "%s\n" /prefix /prefix/lib/node_modules/typescript; elif [ "$1" = "view" ]; then echo 5.0.0; fi'

  run "$BIN" backup --target local --apps=false --pip=false --pipx=false --oh-my-zsh=false --xcode=false --dotfiles=false --manual-apps=false
  [ "$status" -eq 0 ]
  grep -q 'name: "git"' mac-setup.yml
  grep -q 'name: "typescript"' mac-setup.yml
}

@test "command timeout fails slow mas inventory with warning" {
  mock_command mas 'if [ "$1" = "account" ]; then echo "user@example.com"; elif [ "$1" = "list" ]; then sleep 5; fi'
  run "$BIN" backup --target local --apps=true --brew=false --npm=false --pip=false --pipx=false --oh-my-zsh=false --xcode=false --dotfiles=false --manual-apps=false --command-timeout 1
  [ "$status" -eq 1 ]
  [[ "$output" == *"timed out after 1s"* ]]
  [[ "$output" == *"App Store inventory is required"* ]]
}

@test "backup can explicitly skip signed-out App Store inventory" {
  mock_command mas 'case "$1" in list) exit 1 ;; *) echo "unexpected mas $*" >&2; exit 1 ;; esac'
  run "$BIN" backup --target local --appstore-login=skip --apps=true --brew=false --npm=false --pip=false --pipx=false --oh-my-zsh=false --xcode=false --dotfiles=false --manual-apps=false
  [ "$status" -eq 0 ]
  grep -q 'status: "skipped_mas_list_failed"' mac-setup.yml
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
