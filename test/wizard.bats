#!/usr/bin/env bats

load helpers/setup

setup() {
  make_mock_bin
  cd "$BATS_TEST_TMPDIR"
}

@test "wizard selection parser supports all none ranges and comma pieces" {
  run env PROJECT_ROOT="$PROJECT_ROOT" bash -c '
    . "$PROJECT_ROOT/lib/common.sh"
    . "$PROJECT_ROOT/lib/args.sh"
    . "$PROJECT_ROOT/lib/endpoint.sh"
    . "$PROJECT_ROOT/lib/inventory.sh"
    . "$PROJECT_ROOT/lib/wizard.sh"
    all="$(mi_wizard_parse_selection_token all 3 | paste -sd "," -)"
    range="$(mi_wizard_parse_selection_token 2-4 5 | paste -sd "," -)"
    one="$(mi_wizard_parse_selection_token 3 5)"
    none="$(mi_wizard_parse_selection_token none 5 | wc -l | tr -d " ")"
    printf "%s|%s|%s|%s\n" "$all" "$range" "$one" "$none"
  '
  [ "$status" -eq 0 ]
  [ "$output" = "1,2,3|2,3,4|3|0" ]
}

@test "wizard rejects invalid selection parser tokens" {
  run env PROJECT_ROOT="$PROJECT_ROOT" bash -c '
    . "$PROJECT_ROOT/lib/common.sh"
    . "$PROJECT_ROOT/lib/args.sh"
    . "$PROJECT_ROOT/lib/endpoint.sh"
    . "$PROJECT_ROOT/lib/inventory.sh"
    . "$PROJECT_ROOT/lib/wizard.sh"
    mi_wizard_parse_selection_token 4-2 5
  '
  [ "$status" -ne 0 ]
}

@test "wizard validates allowlisted flows sources and prompts" {
  run env PROJECT_ROOT="$PROJECT_ROOT" bash -c '
    . "$PROJECT_ROOT/lib/common.sh"
    . "$PROJECT_ROOT/lib/args.sh"
    . "$PROJECT_ROOT/lib/endpoint.sh"
    . "$PROJECT_ROOT/lib/inventory.sh"
    . "$PROJECT_ROOT/lib/wizard.sh"
    mi_wizard_valid_flow backup
    mi_wizard_valid_flow restore
    ! mi_wizard_valid_flow shell
    mi_wizard_valid_source brew
    ! mi_wizard_valid_source command
    mi_wizard_valid_prompt backup config
    mi_wizard_valid_prompt backup manual_brew_match
    mi_wizard_valid_prompt restore use_config
    mi_wizard_valid_prompt restore appstore_login
    ! mi_wizard_valid_prompt restore manual_brew_match
  '
  [ "$status" -eq 0 ]
}

@test "wizard dry-run defaults are backup no and restore yes" {
  run env PROJECT_ROOT="$PROJECT_ROOT" bash -c '
    . "$PROJECT_ROOT/lib/common.sh"
    . "$PROJECT_ROOT/lib/args.sh"
    . "$PROJECT_ROOT/lib/endpoint.sh"
    . "$PROJECT_ROOT/lib/inventory.sh"
    . "$PROJECT_ROOT/lib/wizard.sh"
    printf "%s|%s\n" "$(mi_wizard_dry_run_default backup)" "$(mi_wizard_dry_run_default restore)"
  '
  [ "$status" -eq 0 ]
  [ "$output" = "no|yes" ]
}

@test "wizard backup config path follows selected backup directory" {
  run env PROJECT_ROOT="$PROJECT_ROOT" bash -c '
    . "$PROJECT_ROOT/lib/common.sh"
    . "$PROJECT_ROOT/lib/args.sh"
    . "$PROJECT_ROOT/lib/endpoint.sh"
    . "$PROJECT_ROOT/lib/inventory.sh"
    . "$PROJECT_ROOT/lib/wizard.sh"
    mi_args_init
    MI_TARGET=local
    MI_INVENTORY=backups/mac-setup.backup.yml
    local_path="$(mi_wizard_backup_config_path)"
    MI_TARGET=icloud
    MI_ICLOUD_ROOT=/tmp/icloud-root
    MI_ICLOUD_FOLDER_NAME="Mac Setup Snapshot"
    icloud_path="$(mi_wizard_backup_config_path)"
    printf "%s|%s\n" "$local_path" "$icloud_path"
  '
  [ "$status" -eq 0 ]
  [ "$output" = "backups/mac-setup.config.yml|/tmp/icloud-root/Mac Setup Snapshot/mac-setup.config.yml" ]
}

@test "wizard choice highlights the default menu option" {
  run env PROJECT_ROOT="$PROJECT_ROOT" bash -c '
    . "$PROJECT_ROOT/lib/common.sh"
    . "$PROJECT_ROOT/lib/args.sh"
    . "$PROJECT_ROOT/lib/endpoint.sh"
    . "$PROJECT_ROOT/lib/inventory.sh"
    . "$PROJECT_ROOT/lib/wizard.sh"
    mi_wizard_read() { printf "%s\n" ""; }
    mi_wizard_choice "Storage" "icloud|iCloud Drive
local|Local files
github|GitHub Gist" 2
  ' 2>&1
  [ "$status" -eq 0 ]
  [[ "$output" == *"    2. Local files"* ]]
  [[ "$output" != *"(default)"* ]]
  [[ "$output" != *"*"* ]]
  [[ "$output" == *"local"* ]]
}

@test "wizard choice applies ansi style to default menu option when color is enabled" {
  run env PROJECT_ROOT="$PROJECT_ROOT" bash -c '
    . "$PROJECT_ROOT/lib/common.sh"
    . "$PROJECT_ROOT/lib/args.sh"
    . "$PROJECT_ROOT/lib/endpoint.sh"
    . "$PROJECT_ROOT/lib/inventory.sh"
    . "$PROJECT_ROOT/lib/wizard.sh"
    mi_color_enabled() { return 0; }
    mi_wizard_read() { printf "%s\n" ""; }
    mi_wizard_choice "Storage" "icloud|iCloud Drive
local|Local files
github|GitHub Gist" 2
  ' 2>&1
  [ "$status" -eq 0 ]
  [[ "$output" == *$'\033[1;32m    2. Local files\033[0m'* ]]
}

@test "wizard backup config step generates missing user config in backup folder" {
  run env PROJECT_ROOT="$PROJECT_ROOT" BACKUP_DIR="$BATS_TEST_TMPDIR/backup" bash -c '
    . "$PROJECT_ROOT/lib/common.sh"
    . "$PROJECT_ROOT/lib/args.sh"
    . "$PROJECT_ROOT/lib/endpoint.sh"
    . "$PROJECT_ROOT/lib/config.sh"
    . "$PROJECT_ROOT/lib/inventory.sh"
    . "$PROJECT_ROOT/lib/wizard.sh"
    mi_args_init
    MI_TARGET=local
    MI_INVENTORY="$BACKUP_DIR/mac-setup.backup.yml"
    MI_WIZARD_CONFIG="$BACKUP_DIR/mac-setup.wizard.yml"
    mi_wizard_generate_configs
    test -f "$BACKUP_DIR/mac-setup.config.yml"
    test ! -f "$BACKUP_DIR/mac-setup.wizard.yml"
    printf "%s|%s\n" "$MI_CONFIG" "$MI_CONFIG_EXPLICIT"
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"$BATS_TEST_TMPDIR/backup/mac-setup.config.yml|true"* ]]
}

@test "wizard backup config step can create new config beside existing one" {
  run env PROJECT_ROOT="$PROJECT_ROOT" BACKUP_DIR="$BATS_TEST_TMPDIR/backup" bash -c '
    . "$PROJECT_ROOT/lib/common.sh"
    . "$PROJECT_ROOT/lib/args.sh"
    . "$PROJECT_ROOT/lib/endpoint.sh"
    . "$PROJECT_ROOT/lib/config.sh"
    . "$PROJECT_ROOT/lib/inventory.sh"
    . "$PROJECT_ROOT/lib/wizard.sh"
    mkdir -p "$BACKUP_DIR"
    printf "existing\n" >"$BACKUP_DIR/mac-setup.config.yml"
    mi_wizard_choice() { printf "%s\n" new; }
    mi_args_init
    MI_TARGET=local
    MI_INVENTORY="$BACKUP_DIR/mac-setup.backup.yml"
    mi_wizard_generate_configs
    test "$(cat "$BACKUP_DIR/mac-setup.config.yml")" = "existing"
    test -f "$MI_CONFIG"
    case "$MI_CONFIG" in "$BACKUP_DIR"/mac-setup.config.*.yml) exit 0 ;; *) exit 1 ;; esac
  '
  [ "$status" -eq 0 ]
}

@test "wizard source args reflect current source booleans" {
  run env PROJECT_ROOT="$PROJECT_ROOT" bash -c '
    . "$PROJECT_ROOT/lib/common.sh"
    . "$PROJECT_ROOT/lib/args.sh"
    . "$PROJECT_ROOT/lib/endpoint.sh"
    . "$PROJECT_ROOT/lib/inventory.sh"
    . "$PROJECT_ROOT/lib/wizard.sh"
    MI_APPS=false
    MI_BREW=true
    MI_NPM=false
    MI_PIP=false
    MI_PIPX=false
    MI_OH_MY_ZSH=false
    MI_XCODE=false
    MI_DOTFILES=false
    MI_MANUAL_APPS=true
    mi_wizard_args_for_sources
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"--apps=false"* ]]
  [[ "$output" == *"--brew=true"* ]]
  [[ "$output" == *"--manual-apps=true"* ]]
}

@test "wizard config can relabel reorder and default known sources" {
  command -v yq >/dev/null 2>&1 || skip "yq is required for wizard config loading"
  cat >custom-wizard.yml <<'YAML'
version: 1
wizard:
  flows:
    backup:
      sources:
        - id: brew
          label: "Packages"
          default: false
        - id: apps
          label: "Store"
          default: true
        - id: unsupported
          label: "Bad"
          default: true
YAML

  run env PROJECT_ROOT="$PROJECT_ROOT" bash -c '
    . "$PROJECT_ROOT/lib/common.sh"
    . "$PROJECT_ROOT/lib/args.sh"
    . "$PROJECT_ROOT/lib/endpoint.sh"
    . "$PROJECT_ROOT/lib/inventory.sh"
    . "$PROJECT_ROOT/lib/wizard.sh"
    MI_WIZARD_CONFIG=custom-wizard.yml
    mi_wizard_load_config
    mi_wizard_sources backup
  '
  [ "$status" -eq 0 ]
  [ "$output" = $'warning: wizard config source backup.unsupported is unsupported; ignoring\nbrew|Packages|false\napps|Store|true' ]
}
