#!/usr/bin/env bash

mi_config_apply() {
  if [ -f "$MI_CONFIG" ] && mi_has yq; then
    [ "$MI_APPS_EXPLICIT" = "true" ] || mi_config_bool sources.apps MI_APPS
    [ "$MI_BREW_EXPLICIT" = "true" ] || mi_config_bool sources.brew MI_BREW
    [ "$MI_NPM_EXPLICIT" = "true" ] || mi_config_bool sources.npm MI_NPM
    [ "$MI_PIP_EXPLICIT" = "true" ] || mi_config_bool sources.pip MI_PIP
    [ "$MI_PIPX_EXPLICIT" = "true" ] || mi_config_bool sources.pipx MI_PIPX
    [ "$MI_OH_MY_ZSH_EXPLICIT" = "true" ] || mi_config_bool sources.oh_my_zsh MI_OH_MY_ZSH
    [ "$MI_XCODE_EXPLICIT" = "true" ] || mi_config_bool sources.xcode MI_XCODE
    [ "$MI_DOTFILES_EXPLICIT" = "true" ] || mi_config_bool sources.dotfiles MI_DOTFILES
    [ "$MI_MANUAL_APPS_EXPLICIT" = "true" ] || mi_config_bool sources.manual_apps MI_MANUAL_APPS
    mi_config_bool defaults.interactive MI_INTERACTIVE
    [ "$MI_INSTALL_MISSING_TOOLS_EXPLICIT" = "true" ] || mi_config_bool defaults.install_missing_tools MI_INSTALL_MISSING_TOOLS
    mi_config_bool defaults.record_versions MI_RECORD_VERSIONS
    mi_config_bool defaults.skip_existing MI_SKIP_EXISTING
    mi_config_bool defaults.overwrite MI_OVERWRITE
    mi_config_bool defaults.caffeinate MI_CAFFEINATE
    [ "$MI_RESUME_FILE_EXPLICIT" = "true" ] || mi_config_string defaults.resume_file MI_RESUME_FILE
    if [ "$MI_TARGET_EXPLICIT" != "true" ]; then
      mi_config_enum storage.default_target MI_TARGET icloud local github
    fi
    if [ "$MI_SOURCE_EXPLICIT" != "true" ]; then
      mi_config_enum storage.default_source MI_SOURCE icloud local github
    fi
    mi_config_string storage.icloud_folder MI_ICLOUD_FOLDER_NAME
    mi_config_bool prepare.pause_after_manual_steps MI_PAUSE_AFTER_PREPARE
    [ "$MI_CHECK_MANUAL_BREW_EXPLICIT" = "true" ] || mi_config_bool backup.check_manual_brew MI_CHECK_MANUAL_BREW
    [ "$MI_MANUAL_BREW_MATCH_EXPLICIT" = "true" ] || mi_config_enum backup.manual_brew_match MI_MANUAL_BREW_MATCH ask never all
    [ -n "$MI_DOTFILES_PATHS" ] || mi_config_string_list backup.dotfiles MI_DOTFILES_PATHS
    [ "$MI_COMMAND_TIMEOUT_EXPLICIT" = "true" ] || mi_config_number defaults.command_timeout MI_COMMAND_TIMEOUT
    [ "$MI_APPSTORE_LOGIN_EXPLICIT" = "true" ] || mi_config_enum restore.appstore_login MI_APPSTORE_LOGIN skip prompt pause require
    [ "$MI_REPORT_EXPLICIT" = "true" ] || mi_config_string reports.path MI_REPORT
    [ "$MI_REPORT_FORMAT_EXPLICIT" = "true" ] || mi_config_enum reports.format MI_REPORT_FORMAT text md yaml json
    [ "$MI_SKIP_REPORT_EXPLICIT" = "true" ] || mi_config_bool reports.skip MI_SKIP_REPORT
  elif [ -f "$MI_CONFIG" ]; then
    mi_warn "config exists but yq is not installed; using CLI/default values"
  fi
}

mi_config_string_list() {
  key="$1"
  var="$2"
  value="$(yq e -r ".${key}[]? // \"\"" "$MI_CONFIG" 2>/dev/null | sed '/^$/d')"
  [ -n "$value" ] || return 0
  printf -v "$var" '%s' "$value"
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
    output="mac-setup.config.yml"
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
  resume_file: ~/.mac-setup/resume.yml

storage:
  default_target: icloud
  default_source: icloud
  icloud_folder: "Mac Setup Snapshot"
  github_backend: gist

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
  check_manual_brew: true
  manual_brew_match: ask
  dotfiles:
    - ~/.zshrc
    - ~/.zprofile
    - ~/.zshenv
    - ~/.bashrc
    - ~/.bash_profile
    - ~/.profile
    - ~/.gitconfig
    - ~/.gitignore_global
    - ~/.editorconfig
    - ~/.hushlogin
    - ~/.inputrc
    - ~/.vimrc
    - ~/.ideavimrc
    - ~/.tmux.conf
    - ~/.screenrc
    - ~/.asdfrc
    - ~/.tool-versions
    - ~/.default-npm-packages
    - ~/.ripgreprc
    - ~/.config/git/config
    - ~/.config/starship.toml
    - ~/.config/bat/config
    - ~/.config/direnv/direnvrc
    - ~/.config/atuin/config.toml
    - ~/.config/zellij/config.kdl
    - ~/.config/ghostty/config
    - ~/.config/wezterm/wezterm.lua
    - ~/.config/alacritty/alacritty.toml
    - ~/.config/kitty/kitty.conf
    - ~/.config/fish/config.fish
    - ~/.config/nvim/init.lua
    - ~/.config/nvim/init.vim
    - ~/.config/helix/config.toml
    - ~/.config/lazygit/config.yml
    - ~/.ssh/config

restore:
  appstore_login: prompt
  ignored_items: []
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
  inventory_file: mac-setup.backup.yml
  config_file: mac-setup.config.yml

reports:
  path: ""
  format: text
  skip: false
EOF
  mi_info "wrote $output"
}
