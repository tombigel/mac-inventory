#!/usr/bin/env bash

appstore_login_ready() {
  [ "$MI_LOGIN_CHECK" = "true" ] || return 0
  mi_has mas || return 1
  mi_mas_capture mas_account account >/dev/null 2>&1
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
  local message="App Store is not signed in; $context cannot use mas until you sign in to the App Store app"
  mi_warn "$message"
  mi_report_event warn apps appstore_not_logged_in "$message"

  if [ "$MI_DRY_RUN" = "true" ]; then
    case "$MI_APPSTORE_LOGIN" in
      skip) mi_info "dry-run: App Store work would be skipped" ;;
      prompt) mi_info "dry-run: would prompt to open App Store, then skip App Store work until sign-in" ;;
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
        mi_warn "appstore: sign in, then rerun this command or use mac-inventory continue if a resume file exists"
      else
        mi_info "appstore: non-interactive prompt policy behaves like skip"
      fi
      return 0
      ;;
    pause)
      appstore_open_prompt
      mi_error "appstore: sign in to the App Store app, then run: mac-inventory continue"
      return 1
      ;;
    require)
      mi_error "appstore: login required by --appstore-login=require"
      return 1
      ;;
  esac
}

appstore_backup() {
  local mas_lines line id version name
  printf 'apps:\n'
  if ! mi_has mas; then
    mi_warn "apps: mas missing; skipping App Store inventory"
    mi_report_event warn apps mas_missing "mas is missing; App Store inventory was skipped"
    printf '  status: "skipped_mas_missing"\n'
    printf '  items: []\n'
    return 0
  fi
  if ! appstore_login_ready; then
    mi_warn "apps: App Store is not signed in; skipping App Store inventory"
    mi_report_event warn apps appstore_not_logged_in "App Store is not signed in; App Store inventory was skipped"
    printf '  status: "skipped_not_logged_in"\n'
    printf '  items: []\n'
    return 0
  fi
  if ! mi_mas_capture mas_lines list; then
    mi_warn "apps: mas list failed; skipping App Store inventory"
    mi_report_event warn apps mas_list_failed "mas list failed; App Store inventory was skipped"
    printf '  status: "skipped_mas_list_failed"\n'
    printf '  items: []\n'
    return 0
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
  mi_has mas || mi_install_brew_tool_if_allowed mas mas || { mi_warn "mas missing; skipping App Store restore"; return 0; }
  if ! appstore_login_ready; then
    appstore_handle_missing_login "restore"
    return $?
  fi
  if ! mi_mas_capture installed_apps list; then
    mi_warn "apps: mas list failed; skipping App Store restore"
    mi_report_event warn apps mas_list_failed "mas list failed; App Store restore was skipped"
    return 0
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
  if mi_has mas; then
    if appstore_login_ready; then
      mi_info "appstore: signed in"
    else
      mi_warn "appstore: mas is installed but not signed in"
    fi
  fi
}
