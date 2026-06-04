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
  [[ "$output" == *"setup snapshot not found"* ]]
}

@test "restore shows welcome progress and friendly summary" {
  cat >"$BATS_TEST_TMPDIR/inventory.yml" <<'YAML'
version: 1
brew:
  taps: []
  formulae: []
  casks: []
YAML

  run "$BIN" restore --dry-run --skip-prepare=true --apps=false --brew=true --npm=false --pip=false --pipx=false --oh-my-zsh=false --xcode=false --dotfiles=false --manual-apps=false --inventory "$BATS_TEST_TMPDIR/inventory.yml"
  [ "$status" -eq 0 ]
  [[ "$output" == *"dry-run restore starting"* ]]
  [[ "$output" == *"Next step: Homebrew"* ]]
  [[ "$output" == *"restore: brew..."* ]]
  [[ "$output" == *"[############] 1/1"* ]]
  [[ "$output" == *"Mac Setup Snapshot summary"* ]]
  [[ "$output" == *"restore completed"* ]]
  [[ "$output" == *"restore completed (dry-run)"* ]]
  [[ "$output" != *"Counts:"* ]]
}

@test "restore pause mode can skip selected sections" {
  command -v yq >/dev/null 2>&1 || skip "yq is required for restore"
  run env PROJECT_ROOT="$PROJECT_ROOT" LOG="$BATS_TEST_TMPDIR/restore.log" bash -c '
    . "$PROJECT_ROOT/lib/common.sh"
    . "$PROJECT_ROOT/lib/args.sh"
    . "$PROJECT_ROOT/lib/safety.sh"
    . "$PROJECT_ROOT/lib/inventory.sh"
    mi_args_init
    MI_INVENTORY="$PWD/inventory.yml"
    MI_APPS=false
    MI_BREW=true
    MI_NPM=true
    MI_PIP=false
    MI_PIPX=false
    MI_OH_MY_ZSH=false
    MI_XCODE=false
    MI_DOTFILES=false
    MI_MANUAL_APPS=false
    MI_GITHUB_PROJECTS=false
    MI_RESTORE_STEP_MODE=pause
    cat >"$MI_INVENTORY" <<YAML
version: 1
brew:
  formulae: []
npm:
  globals: []
YAML
    brew_restore() { printf "%s\n" brew >>"$LOG"; }
    npm_restore() { printf "%s\n" npm >>"$LOG"; }
    mi_prompt_available() { return 0; }
    mi_restore_step_action() {
      case "$1" in
        brew) return 0 ;;
        npm) return 1 ;;
      esac
    }
    mi_inventory_restore_body
    cat "$LOG"
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"brew"* ]]
  [[ "$output" != *"npm"* ]]
  [[ "$output" == *"restore: skipped npm globals"* ]]
}

@test "restore dry-run prompts for manual app cask candidates" {
  mock_command brew 'case "$1 $2 $3" in "list --cask candidate-app") exit 1 ;; *) exit 0 ;; esac'
  cat >"$BATS_TEST_TMPDIR/inventory.yml" <<'YAML'
version: 1
manual_apps:
  apps:
    - name: "Candidate App"
      path: "/Applications/Candidate App.app"
      version: "5.0"
      brew_cask_candidate: "candidate-app"
      selected_brew_cask: ""
YAML

  run "$BIN" restore --dry-run --skip-prepare=true --skip-report --apps=false --brew=false --npm=false --pip=false --pipx=false --oh-my-zsh=false --xcode=false --dotfiles=false --manual-apps=true --inventory "$BATS_TEST_TMPDIR/inventory.yml"
  [ "$status" -eq 0 ]
  [[ "$output" == *"dry-run: would prompt to install Homebrew cask candidate-app for manual app Candidate App"* ]]
}

@test "restore non-interactive reports manual app cask candidates without installing" {
  mock_command brew 'case "$1 $2 $3" in "list --cask candidate-app") exit 1 ;; "install --cask candidate-app") echo install >> "$BATS_TEST_TMPDIR/brew.log" ;; *) exit 0 ;; esac'
  cat >"$BATS_TEST_TMPDIR/inventory.yml" <<'YAML'
version: 1
manual_apps:
  apps:
    - name: "Candidate App"
      path: "/Applications/Candidate App.app"
      version: "5.0"
      brew_cask_candidate: "candidate-app"
      selected_brew_cask: ""
YAML

  run "$BIN" restore --interactive=false --skip-prepare=true --skip-report --apps=false --brew=false --npm=false --pip=false --pipx=false --oh-my-zsh=false --xcode=false --dotfiles=false --manual-apps=true --inventory "$BATS_TEST_TMPDIR/inventory.yml"
  [ "$status" -eq 0 ]
  [[ "$output" == *"manual app Candidate App can be restored with Homebrew cask candidate-app; rerun interactively or pass --yes to install it"* ]]
  [ ! -f "$BATS_TEST_TMPDIR/brew.log" ]
}

@test "restore yes installs manual app cask candidates" {
  mock_command brew 'case "$1 $2 $3" in "list --cask candidate-app") exit 1 ;; "install --cask candidate-app") echo install >> "$BATS_TEST_TMPDIR/brew.log" ;; *) exit 0 ;; esac'
  cat >"$BATS_TEST_TMPDIR/inventory.yml" <<'YAML'
version: 1
manual_apps:
  apps:
    - name: "Candidate App"
      path: "/Applications/Candidate App.app"
      version: "5.0"
      brew_cask_candidate: "candidate-app"
      selected_brew_cask: ""
YAML

  run "$BIN" restore --yes --skip-prepare=true --skip-report --apps=false --brew=false --npm=false --pip=false --pipx=false --oh-my-zsh=false --xcode=false --dotfiles=false --manual-apps=true --inventory "$BATS_TEST_TMPDIR/inventory.yml"
  [ "$status" -eq 0 ]
  grep -q '^install$' "$BATS_TEST_TMPDIR/brew.log"
}

@test "restore skips manual app cask candidates that brew info cannot resolve" {
  mock_command brew 'case "$1 $2 $3" in "info --json=v2 --cask") exit 1 ;; "install --cask falcon") echo install >> "$BATS_TEST_TMPDIR/brew.log" ;; *) exit 0 ;; esac'
  cat >"$BATS_TEST_TMPDIR/inventory.yml" <<'YAML'
version: 1
manual_apps:
  apps:
    - name: "Falcon"
      path: "/Applications/Falcon.app"
      version: "1.0"
      brew_cask_candidate: "falcon"
      selected_brew_cask: ""
YAML

  run "$BIN" restore --yes --skip-prepare=true --skip-report --apps=false --brew=false --npm=false --pip=false --pipx=false --oh-my-zsh=false --xcode=false --dotfiles=false --manual-apps=true --inventory "$BATS_TEST_TMPDIR/inventory.yml"
  [ "$status" -eq 0 ]
  [[ "$output" == *"manual app Falcon has Homebrew cask candidate falcon, but brew info --cask could not resolve it"* ]]
  [ ! -f "$BATS_TEST_TMPDIR/brew.log" ]
}

@test "status prints existing resume state" {
  cat >"$BATS_TEST_TMPDIR/resume.yml" <<'YAML'
version: 1
workflow: "prepare"
created_at: "2026-06-01T00:00:00Z"
updated_at: "2026-06-01T00:00:00Z"
inventory: "mac-setup.backup.yml"
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
inventory: "mac-setup.backup.yml"
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

@test "caffeinate dry-run reports intended wrapper when enabled" {
  mock_command caffeinate 'echo caffeinate "$@" >> "$BATS_TEST_TMPDIR/caffeinate.log"'
  run "$BIN" prepare --dry-run --caffeinate=true --apps=false --xcode=false --pipx=false --resume-file "$BATS_TEST_TMPDIR/resume.yml"
  [ "$status" -eq 0 ]
  [[ "$output" == *"would use caffeinate"* ]]
}

@test "restore skips signed-out App Store in non-interactive mode" {
  mock_command mas 'case "$1" in list) exit 1 ;; *) echo "unexpected mas $*" >&2; exit 1 ;; esac'
  cat >"$BATS_TEST_TMPDIR/inventory.yml" <<'YAML'
version: 1
apps:
  items:
    - id: "123"
      name: "Example"
YAML

  run "$BIN" restore --dry-run --interactive=false --skip-prepare=true --appstore-login=skip --apps=true --brew=false --npm=false --pip=false --pipx=false --oh-my-zsh=false --xcode=false --dotfiles=false --manual-apps=false --inventory "$BATS_TEST_TMPDIR/inventory.yml"
  [ "$status" -eq 0 ]
  [[ "$output" == *"App Store access is unavailable"* ]]
  [[ "$output" == *"App Store work would be skipped"* ]]
}

@test "restore requires signed-in App Store by default" {
  mock_command mas 'case "$1" in list) exit 1 ;; *) echo "unexpected mas $*" >&2; exit 1 ;; esac'
  cat >"$BATS_TEST_TMPDIR/inventory.yml" <<'YAML'
version: 1
apps:
  items:
    - id: "123"
      name: "Example"
YAML

  run "$BIN" restore --interactive=false --skip-prepare=true --apps=true --brew=false --npm=false --pip=false --pipx=false --oh-my-zsh=false --xcode=false --dotfiles=false --manual-apps=false --inventory "$BATS_TEST_TMPDIR/inventory.yml"
  [ "$status" -eq 1 ]
  [[ "$output" == *"authentication required; run interactively or pass --appstore-login=skip"* ]]
}

@test "prepare require policy reports App Store access blocker" {
  mock_command mas 'case "$1" in list) exit 1 ;; *) exit 0 ;; esac'
  run "$BIN" prepare --interactive=false --appstore-login=require --apps=true --xcode=false --pipx=false --resume-file "$BATS_TEST_TMPDIR/resume.yml"
  [ "$status" -eq 1 ]
  [[ "$output" == *"authentication required by --appstore-login=require"* ]]
  [[ "$output" == *"workflow failed at step check_appstore_login"* ]]
}
