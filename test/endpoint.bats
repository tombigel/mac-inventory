#!/usr/bin/env bats

load helpers/setup

setup() {
  make_mock_bin
  cd "$BATS_TEST_TMPDIR"
}

make_icloud() {
  ICLOUD_ROOT="$BATS_TEST_TMPDIR/iCloud"
  mkdir -p "$ICLOUD_ROOT"
}

@test "backup dry-run defaults to iCloud endpoint without writing" {
  make_icloud
  run "$BIN" backup --dry-run --skip-report --interactive=false --icloud-root "$ICLOUD_ROOT" --apps=false --brew=false --npm=false --pip=false --pipx=false --oh-my-zsh=false --xcode=false --dotfiles=false --manual-apps=false
  [ "$status" -eq 0 ]
  [[ "$output" == *"$ICLOUD_ROOT/Mac Setup Snapshot/mac-setup.yml"* ]]
  [[ "$output" == *"dry-run: would use iCloud endpoint"* ]]
  [ ! -e "$ICLOUD_ROOT/Mac Setup Snapshot" ]
}

@test "backup to iCloud creates bundle and metadata" {
  make_icloud
  run "$BIN" backup --skip-report --interactive=false --icloud-root "$ICLOUD_ROOT" --apps=false --brew=false --npm=false --pip=false --pipx=false --oh-my-zsh=false --xcode=false --dotfiles=false --manual-apps=false
  [ "$status" -eq 0 ]
  [ -f "$ICLOUD_ROOT/Mac Setup Snapshot/mac-setup.yml" ]
  [ -f "$ICLOUD_ROOT/Mac Setup Snapshot/metadata.yml" ]
  grep -q 'endpoint: icloud' "$ICLOUD_ROOT/Mac Setup Snapshot/metadata.yml"
}

@test "backup to iCloud moves previous bundle into history" {
  make_icloud
  mkdir -p "$ICLOUD_ROOT/Mac Setup Snapshot/files"
  echo old >"$ICLOUD_ROOT/Mac Setup Snapshot/mac-setup.yml"
  echo old >"$ICLOUD_ROOT/Mac Setup Snapshot/metadata.yml"

  run "$BIN" backup --skip-report --interactive=false --icloud-root "$ICLOUD_ROOT" --apps=false --brew=false --npm=false --pip=false --pipx=false --oh-my-zsh=false --xcode=false --dotfiles=false --manual-apps=false
  [ "$status" -eq 0 ]
  [ -f "$ICLOUD_ROOT/Mac Setup Snapshot/mac-setup.yml" ]
  history_count="$(find "$ICLOUD_ROOT/Mac Setup Snapshot/history" -name mac-setup.yml | wc -l | tr -d ' ')"
  [ "$history_count" -eq 1 ]
}

@test "restore dry-run defaults to iCloud bundle when present" {
  make_icloud
  mkdir -p "$ICLOUD_ROOT/Mac Setup Snapshot"
  cat >"$ICLOUD_ROOT/Mac Setup Snapshot/mac-setup.yml" <<'YAML'
version: 1
apps: []
YAML
  mock_command yq 'if [ "$1" = "--version" ]; then echo "yq (https://github.com/mikefarah/yq/) version v4.0.0"; exit 0; fi; exit 0'

  run "$BIN" restore --dry-run --skip-prepare=true --interactive=false --install-missing-tools=false --apps=false --xcode=false --icloud-root "$ICLOUD_ROOT"
  [ "$status" -eq 0 ]
}

@test "list defaults to iCloud bundle when present" {
  make_icloud
  mkdir -p "$ICLOUD_ROOT/Mac Setup Snapshot"
  cat >"$ICLOUD_ROOT/Mac Setup Snapshot/mac-setup.yml" <<'YAML'
version: 1
apps: []
brew: []
YAML

  run "$BIN" list --interactive=false --icloud-root "$ICLOUD_ROOT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"version"* ]]
  [[ "$output" == *"apps"* ]]
  [[ "$output" == *"brew"* ]]
}

@test "missing iCloud in non-interactive mode fails clearly" {
  run "$BIN" backup --dry-run --interactive=false --icloud-root "$BATS_TEST_TMPDIR/missing" --apps=false --brew=false --npm=false --pip=false --pipx=false --oh-my-zsh=false --xcode=false --dotfiles=false --manual-apps=false
  [ "$status" -eq 1 ]
  [[ "$output" == *"iCloud endpoint is unavailable"* ]]
}

@test "read-only iCloud path fails backup before writing" {
  make_icloud
  chmod 500 "$ICLOUD_ROOT"
  run "$BIN" backup --interactive=false --icloud-root "$ICLOUD_ROOT" --apps=false --brew=false --npm=false --pip=false --pipx=false --oh-my-zsh=false --xcode=false --dotfiles=false --manual-apps=false
  [ "$status" -eq 1 ]
  [[ "$output" == *"iCloud endpoint is unavailable"* || "$output" == *"iCloud endpoint is not writable"* ]]
}

@test "source local preserves current local restore behavior" {
  cat >inventory.yml <<'YAML'
version: 1
apps: []
YAML
  mock_command yq 'if [ "$1" = "--version" ]; then echo "yq (https://github.com/mikefarah/yq/) version v4.0.0"; exit 0; fi; exit 0'
  run "$BIN" restore --source local --inventory inventory.yml --skip-prepare=true --dry-run --apps=false --xcode=false
  [ "$status" -eq 0 ]
}

@test "explicit inventory preserves local list behavior" {
  make_icloud
  mkdir -p "$ICLOUD_ROOT/Mac Setup Snapshot"
  cat >"$ICLOUD_ROOT/Mac Setup Snapshot/mac-setup.yml" <<'YAML'
version: 1
apps: []
YAML
  cat >custom.yml <<'YAML'
version: 1
npm: []
YAML

  run "$BIN" list --interactive=false --icloud-root "$ICLOUD_ROOT" --inventory custom.yml
  [ "$status" -eq 0 ]
  [[ "$output" == *"npm"* ]]
  [[ "$output" != *"apps"* ]]
}

@test "target github routes through Gist push dry-run" {
  mock_command gh 'if [ "$1" = "auth" ]; then exit 0; fi; echo gh "$@"'
  run "$BIN" backup --target github --dry-run --skip-report --apps=false --brew=false --npm=false --pip=false --pipx=false --oh-my-zsh=false --xcode=false --dotfiles=false --manual-apps=false
  [ "$status" -eq 0 ]
  [[ "$output" == *"dry-run: would push"* ]]
}

@test "source github routes through Gist pull dry-run" {
  mock_command gh 'if [ "$1" = "auth" ]; then exit 0; fi; echo gh "$@"'
  run "$BIN" restore --source github -g abc123 --dry-run --interactive=false --skip-prepare=true
  [ "$status" -eq 1 ]
  [[ "$output" == *"dry-run: would pull gist abc123"* ]]
  [[ "$output" == *"setup snapshot not found"* ]]
}

@test "explicit inventory overrides iCloud-derived default path" {
  run "$BIN" backup --dry-run --skip-report --interactive=false --inventory custom.yml --apps=false --brew=false --npm=false --pip=false --pipx=false --oh-my-zsh=false --xcode=false --dotfiles=false --manual-apps=false
  [ "$status" -eq 0 ]
  [[ "$output" == *"custom.yml"* ]]
}
