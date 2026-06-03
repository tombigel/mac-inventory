#!/usr/bin/env bats

load helpers/setup

setup() {
  make_mock_bin
  cd "$BATS_TEST_TMPDIR"
  : >mac-setup.config.yml
}

mock_matrix_yq() {
  mock_command yq '
if [ "$1" = "--version" ]; then
  echo "yq (https://github.com/mikefarah/yq/) version v4.0.0"
  exit 0
fi
expr="$*"
case "$expr" in
  *"sources.apps"*) echo true ;;
  *"sources.brew"*) echo true ;;
  *"sources.npm"*) echo false ;;
  *"sources.pip "*) echo false ;;
  *"sources.pipx"*) echo false ;;
  *"sources.oh_my_zsh"*) echo false ;;
  *"sources.xcode"*) echo false ;;
  *"sources.dotfiles"*) echo false ;;
  *"sources.manual_apps"*) echo true ;;
  *"storage.default_target"*) echo local ;;
  *"storage.default_source"*) echo github ;;
  *"defaults.command_timeout"*) echo 9 ;;
  *"defaults.resume_file"*) echo configured-resume.yml ;;
  *"defaults.install_missing_tools"*) echo false ;;
  *"restore.appstore_login"*) echo skip ;;
  *"reports.path"*) echo configured-report.md ;;
  *"reports.format"*) echo md ;;
  *"reports.skip"*) echo true ;;
  *) echo "" ;;
esac'
}

@test "config applies matrix defaults when cli leaves values unset" {
  mock_matrix_yq
  run env PROJECT_ROOT="$PROJECT_ROOT" bash -c '
    . "$PROJECT_ROOT/lib/common.sh"
    . "$PROJECT_ROOT/lib/args.sh"
    . "$PROJECT_ROOT/lib/config.sh"
    mi_args_init
    mi_parse_args backup >/dev/null
    mi_config_apply
    printf "%s|%s|%s|%s|%s|%s|%s|%s|%s|%s\n" \
      "$MI_APPS" "$MI_NPM" "$MI_TARGET" "$MI_SOURCE" "$MI_COMMAND_TIMEOUT" \
      "$MI_RESUME_FILE" "$MI_INSTALL_MISSING_TOOLS" "$MI_APPSTORE_LOGIN" \
      "$MI_REPORT" "$MI_REPORT_FORMAT:$MI_SKIP_REPORT"
  '
  [ "$status" -eq 0 ]
  [ "$output" = "true|false|local|github|9|configured-resume.yml|false|skip|configured-report.md|md:true" ]
}

@test "explicit cli options override config matrix defaults" {
  mock_matrix_yq
  run env PROJECT_ROOT="$PROJECT_ROOT" bash -c '
    . "$PROJECT_ROOT/lib/common.sh"
    . "$PROJECT_ROOT/lib/args.sh"
    . "$PROJECT_ROOT/lib/config.sh"
    mi_args_init
    mi_parse_args backup \
      --apps=false --brew=false --npm=true --pip=true --pipx=true \
      --oh-my-zsh=true --xcode=true --dotfiles=true --manual-apps=false \
      --target github --source local --command-timeout 2 \
      --resume-file cli-resume.yml --install-missing-tools=true \
      --appstore-login require --report cli-report.json --report-format json \
      >/dev/null
    mi_config_apply
    printf "%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s\n" \
      "$MI_APPS" "$MI_BREW" "$MI_NPM" "$MI_PIP" "$MI_PIPX" \
      "$MI_OH_MY_ZSH" "$MI_XCODE" "$MI_DOTFILES" "$MI_MANUAL_APPS" \
      "$MI_TARGET" "$MI_SOURCE" "$MI_COMMAND_TIMEOUT" "$MI_RESUME_FILE" \
      "$MI_INSTALL_MISSING_TOOLS:$MI_APPSTORE_LOGIN:$MI_REPORT:$MI_REPORT_FORMAT:$MI_SKIP_REPORT"
  '
  [ "$status" -eq 0 ]
  [ "$output" = "false|false|true|true|true|true|true|true|false|github|local|2|cli-resume.yml|true:require:cli-report.json:json:true" ]
}
