#!/usr/bin/env bash

mi_config_apply() {
  if [ -f "$MI_CONFIG" ] && mi_has yq; then
    mi_config_bool sources.apps MI_APPS
    mi_config_bool sources.brew MI_BREW
    mi_config_bool sources.npm MI_NPM
    mi_config_bool sources.pip MI_PIP
    mi_config_bool sources.pipx MI_PIPX
    mi_config_bool sources.oh_my_zsh MI_OH_MY_ZSH
    mi_config_bool sources.xcode MI_XCODE
    mi_config_bool sources.dotfiles MI_DOTFILES
    mi_config_bool sources.manual_apps MI_MANUAL_APPS
    mi_config_bool defaults.interactive MI_INTERACTIVE
    mi_config_bool defaults.skip_existing MI_SKIP_EXISTING
    mi_config_bool defaults.overwrite MI_OVERWRITE
    mi_config_bool defaults.caffeinate MI_CAFFEINATE
    mi_config_string defaults.resume_file MI_RESUME_FILE
    mi_config_bool prepare.pause_after_manual_steps MI_PAUSE_AFTER_PREPARE
    mi_config_number defaults.command_timeout MI_COMMAND_TIMEOUT
    mi_config_enum restore.appstore_login MI_APPSTORE_LOGIN skip prompt pause require
    mi_config_string reports.path MI_REPORT
    mi_config_enum reports.format MI_REPORT_FORMAT text md yaml json
    mi_config_bool reports.skip MI_SKIP_REPORT
  elif [ -f "$MI_CONFIG" ]; then
    mi_warn "config exists but yq is not installed; using CLI/default values"
  fi
}

mi_config_enum() {
  key="$1"
  var="$2"
  shift 2
  value="$(yq e ".$key // \"\"" "$MI_CONFIG" 2>/dev/null)"
  case "$value" in
    ''|null) return 0 ;;
  esac
  for allowed in "$@"; do
    if [ "$value" = "$allowed" ]; then
      printf -v "$var" '%s' "$value"
      return 0
    fi
  done
  mi_warn "config $key has unsupported value; ignoring"
}

mi_config_number() {
  key="$1"
  var="$2"
  value="$(yq e ".$key // \"\"" "$MI_CONFIG" 2>/dev/null)"
  case "$value" in
    ''|null) return 0 ;;
    *[!0-9]*) mi_warn "config $key must be a number; ignoring" ;;
    *) printf -v "$var" '%s' "$value" ;;
  esac
}

mi_config_string() {
  key="$1"
  var="$2"
  value="$(yq e ".$key // \"\"" "$MI_CONFIG" 2>/dev/null)"
  case "$value" in
    ''|null) return 0 ;;
    *) printf -v "$var" '%s' "$value" ;;
  esac
}

mi_config_bool() {
  key="$1"
  var="$2"
  value="$(yq e ".$key // \"\"" "$MI_CONFIG" 2>/dev/null)"
  if [ -n "$value" ] && [ "$value" != "null" ]; then
    mi_set_bool_var "$var" "$value" >/dev/null 2>&1 || true
  fi
}

mi_config_generate() {
  output="${MI_OUTPUT:-$MI_CONFIG}"
  if [ -z "$output" ]; then
    output="mac-inventory.config.yml"
  fi

  if [ "$MI_DRY_RUN" = "true" ]; then
    mi_info "dry-run: would write config to $output"
    return 0
  fi

  if [ -e "$output" ] && ! mi_prompt_yes_no "Overwrite existing config $output?" "no"; then
    mi_error "config not written"
    return 1
  fi

  mi_mkdir_parent "$output"
  cat >"$output" <<'EOF'
version: 1
defaults:
  interactive: true
  install_missing_tools: true
  record_versions: true
  restore_versions: false
  skip_existing: true
  overwrite: false
  command_timeout: 30
  caffeinate: true
  resume_file: ~/.mac-inventory/resume.yml

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

backup:
  check_manual_brew: false
  manual_brew_match: ask
  dotfiles:
    - ~/.zshrc
    - ~/.gitconfig
    - ~/.gitignore_global
    - ~/.ssh/config

restore:
  appstore_login: prompt
  dotfiles_mode: skip_existing
  oh_my_zsh_mode: install_if_missing
  xcode:
    install_command_line_tools: true
    install_xcode_app: prompt
    accept_license: prompt

prepare:
  install_xcode_cli: prompt
  install_homebrew: prompt
  install_yq: prompt
  install_mas: prompt
  install_pipx: prompt
  pause_after_manual_steps: true

gist:
  visibility: secret
  inventory_file: mac-inventory.yml
  config_file: mac-inventory.config.yml

reports:
  path: ""
  format: text
  skip: false
EOF
  mi_info "wrote $output"
}
