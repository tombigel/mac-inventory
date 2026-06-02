#!/usr/bin/env bash

appstore_access_ready() {
  local mas_lines
  [ "$MI_LOGIN_CHECK" = "true" ] || return 0
  mi_has mas || return 1
  mi_mas_capture mas_lines list >/dev/null 2>&1
}

appstore_ensure_mas() {
  local context="$1"
  if mi_has mas; then
    return 0
  fi

  mi_warn "apps: mas missing; $context cannot use Mac App Store apps"
  mi_report_event warn apps mas_missing "mas is missing; $context cannot use Mac App Store apps"

  if [ "$MI_APPSTORE_LOGIN" = "skip" ]; then
    mi_info "appstore: skipping App Store work because --appstore-login=skip"
    return 1
  fi
  if [ "$MI_INSTALL_MISSING_TOOLS" != "true" ]; then
    mi_error "mas is required for App Store work; pass --apps=false or --appstore-login=skip to skip it"
    return 1
  fi
  if [ "$MI_DRY_RUN" = "true" ]; then
    mi_info "dry-run: would install mas with Homebrew"
    return 0
  fi
  if [ "$MI_INTERACTIVE" != "true" ] || [ ! -t 0 ]; then
    mi_error "mas is required for App Store work; run prepare interactively or pass --apps=false/--appstore-login=skip"
    return 1
  fi

  mi_install_brew_tool_if_allowed mas mas || {
    mi_error "mas installation did not complete; App Store work cannot continue"
    return 1
  }
}

appstore_open_prompt() {
  if [ "$MI_DRY_RUN" = "true" ]; then
    mi_info "dry-run: would open App Store for sign-in"
    return 0
  fi
  mi_prompt_yes_no "Open the App Store app so you can sign in?" "yes" || return 0
  mi_run open -a "App Store"
}

appstore_handle_missing_login() {
  local context="$1"
  local message="App Store access is unavailable; $context cannot use mas until App Store authentication succeeds"
  mi_warn "$message"
  mi_report_event warn apps appstore_not_logged_in "$message"

  if [ "$MI_DRY_RUN" = "true" ]; then
    case "$MI_APPSTORE_LOGIN" in
      skip) mi_info "dry-run: App Store work would be skipped" ;;
      prompt) mi_info "dry-run: would prompt to open App Store and require sign-in before using mas" ;;
      pause) mi_info "dry-run: would pause and resume after App Store sign-in" ;;
      require) mi_info "dry-run: would fail until App Store sign-in is available" ;;
    esac
    return 0
  fi

  case "$MI_APPSTORE_LOGIN" in
    skip)
      mi_info "appstore: skipping App Store work because --appstore-login=skip"
      return 0
      ;;
    prompt)
      if [ "$MI_INTERACTIVE" = "true" ] && [ -t 0 ]; then
        appstore_open_prompt
        mi_error "appstore: authenticate in the App Store app or mas prompt, then rerun this command or use ${MI_PROGRAM_NAME:-mac-setup} continue if a resume file exists"
      else
        mi_error "appstore: authentication required; run interactively or pass --appstore-login=skip"
      fi
      return 1
      ;;
    pause)
      appstore_open_prompt
      mi_error "appstore: authenticate in the App Store app or mas prompt, then run: ${MI_PROGRAM_NAME:-mac-setup} continue"
      return 1
      ;;
    require)
      mi_error "appstore: authentication required by --appstore-login=require"
      return 1
      ;;
  esac
}

appstore_backup() {
  local mas_lines line id version name
  printf 'apps:\n'
  if ! appstore_ensure_mas "backup"; then
    printf '  status: "skipped_mas_missing"\n'
    printf '  items: []\n'
    [ "$MI_APPSTORE_LOGIN" = "skip" ] && return 0
    return 1
  fi
  if ! mi_mas_capture mas_lines list; then
    appstore_handle_missing_login "backup"
    mi_report_event warn apps mas_list_failed "mas list failed; App Store inventory could not continue"
    printf '  status: "skipped_mas_list_failed"\n'
    printf '  items: []\n'
    [ "$MI_APPSTORE_LOGIN" = "skip" ] && return 0
    return 1
  fi
  printf '  status: "ok"\n'
  printf '  items:\n'
  printf '%s\n' "$mas_lines" | while IFS= read -r line; do
    [ -n "$line" ] || continue
    id="$(printf '%s\n' "$line" | awk '{print $1}')"
    version="$(printf '%s\n' "$line" | sed -n 's/.*(\([^)]*\)).*/\1/p')"
    name="$(printf '%s\n' "$line" | sed -E 's/^[0-9]+[[:space:]]+//; s/[[:space:]]+\([^)]*\)$//')"
    printf '    - id: %s\n' "$(mi_yaml_scalar "$id")"
    printf '      name: %s\n' "$(mi_yaml_scalar "$name")"
    printf '      version: %s\n' "$(mi_yaml_scalar "$version")"
  done
}

appstore_restore() {
  local installed_apps id
  if ! appstore_ensure_mas "restore"; then
    [ "$MI_APPSTORE_LOGIN" = "skip" ] && return 0
    return 1
  fi
  if ! mi_mas_capture installed_apps list; then
    appstore_handle_missing_login "restore"
    mi_report_event warn apps mas_list_failed "mas list failed; App Store restore could not continue"
    [ "$MI_APPSTORE_LOGIN" = "skip" ] && return 0
    return 1
  fi
  yq e '([.apps[]? | select((type == "!!map") and has("id"))] + [(.apps | select(type == "!!map") | .items[]?) | select((type == "!!map") and has("id"))])[]?.id' "$MI_INVENTORY" 2>/dev/null | while IFS= read -r id; do
    [ -n "$id" ] && [ "$id" != "null" ] || continue
    mi_validate_identifier "$id" || { mi_warn "invalid App Store id: $id"; continue; }
    if printf '%s\n' "$installed_apps" | awk '{print $1}' | grep -Fxq "$id"; then
      mi_info "apps: $id already installed"
    else
      mi_run mas install "$id"
    fi
  done
}

appstore_doctor() {
  if ! mi_has mas; then
    mi_warn "appstore: mas missing"
    return 0
  fi
  if appstore_access_ready; then
    mi_info "appstore: mas list succeeded"
  else
    mi_warn "appstore: mas is installed but App Store access is unavailable"
  fi
}
