#!/usr/bin/env bats

load helpers/setup

setup() {
  make_mock_bin
  cd "$BATS_TEST_TMPDIR"
}

@test "prepare dry-run prints clean step output without writing requested resume file" {
  run "$BIN" prepare --dry-run --resume-file "$BATS_TEST_TMPDIR/resume.yml" --apps=false --xcode=false --pipx=false
  [ "$status" -eq 0 ]
  [[ "$output" == *"Step 1/"* ]]
  [[ "$output" == *"Press Ctrl-C to stop safely"* ]]
  [ ! -f "$BATS_TEST_TMPDIR/resume.yml" ]
}

@test "restore preflight runs by default and fails at missing inventory" {
  run "$BIN" restore --dry-run --interactive=false --resume-file "$BATS_TEST_TMPDIR/resume.yml" --inventory "$BATS_TEST_TMPDIR/missing.yml"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Check Xcode Command Line Tools"* ]]
  [[ "$output" == *"workflow failed at step restore_inventory"* ]]
}

@test "restore can skip prepare preflight" {
  run "$BIN" restore --skip-prepare=true --dry-run --inventory "$BATS_TEST_TMPDIR/missing.yml"
  [ "$status" -eq 1 ]
  [[ "$output" != *"Check Xcode Command Line Tools"* ]]
  [[ "$output" == *"inventory not found"* ]]
}

@test "status prints existing resume state" {
  cat >"$BATS_TEST_TMPDIR/resume.yml" <<'YAML'
version: 1
workflow: "prepare"
created_at: "2026-06-01T00:00:00Z"
updated_at: "2026-06-01T00:00:00Z"
inventory: "mac-inventory.yml"
current_step: "install_yq"
steps:
  - id: "check_xcode_cli"
    status: "done"
  - id: "install_yq"
    status: "failed"
YAML
  run "$BIN" status --resume-file "$BATS_TEST_TMPDIR/resume.yml"
  [ "$status" -eq 0 ]
  [[ "$output" == *"workflow: \"prepare\""* ]]
  [[ "$output" == *"install_yq"* ]]
}

@test "continue dry-run resumes saved workflow steps" {
  cat >"$BATS_TEST_TMPDIR/resume.yml" <<'YAML'
version: 1
workflow: "prepare"
created_at: "2026-06-01T00:00:00Z"
updated_at: "2026-06-01T00:00:00Z"
inventory: "mac-inventory.yml"
current_step: "install_yq"
steps:
  - id: "check_xcode_cli"
    status: "done"
  - id: "install_yq"
    status: "failed"
YAML
  run "$BIN" continue --dry-run --resume-file "$BATS_TEST_TMPDIR/resume.yml"
  [ "$status" -eq 0 ]
  [[ "$output" != *"Check Xcode Command Line Tools"* ]]
  [[ "$output" == *"Install yq"* ]]
}

@test "caffeinate is used when enabled and available" {
  mock_command caffeinate 'echo caffeinate "$@" >> "$BATS_TEST_TMPDIR/caffeinate.log"; sleep 2 & wait'
  run "$BIN" prepare --dry-run --caffeinate=true --apps=false --xcode=false --pipx=false --resume-file "$BATS_TEST_TMPDIR/resume.yml"
  [ "$status" -eq 0 ]
  [[ "$output" == *"would use caffeinate"* ]]
}

@test "restore skips signed-out App Store in non-interactive mode" {
  mock_command mas 'case "$1" in account) exit 1 ;; *) echo "unexpected mas $*" >&2; exit 1 ;; esac'
  cat >"$BATS_TEST_TMPDIR/inventory.yml" <<'YAML'
version: 1
apps:
  items:
    - id: "123"
      name: "Example"
YAML

  run "$BIN" restore --dry-run --interactive=false --skip-prepare=true --appstore-login=skip --apps=true --brew=false --npm=false --pip=false --pipx=false --oh-my-zsh=false --xcode=false --dotfiles=false --manual-apps=false --inventory "$BATS_TEST_TMPDIR/inventory.yml"
  [ "$status" -eq 0 ]
  [[ "$output" == *"App Store is not signed in"* ]]
  [[ "$output" == *"App Store work would be skipped"* ]]
}

@test "prepare require policy reports App Store login blocker" {
  mock_command mas 'case "$1" in account) exit 1 ;; *) exit 0 ;; esac'
  run "$BIN" prepare --interactive=false --appstore-login=require --apps=true --xcode=false --pipx=false --resume-file "$BATS_TEST_TMPDIR/resume.yml"
  [ "$status" -eq 1 ]
  [[ "$output" == *"login required by --appstore-login=require"* ]]
  [[ "$output" == *"workflow failed at step check_appstore_login"* ]]
}
