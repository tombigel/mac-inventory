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

appstore_parse_json_rows() {
  local json="$1"
  local json_array
  [ -n "$json" ] || return 0
  mi_has yq || return 1
  mi_verbose "apps: parsing mas JSON output"
  json_array="$(printf '%s\n' "$json" | awk '
    BEGIN {print "["}
    NF {
      if (n > 0) {
        print ","
      }
      print
      n++
    }
    END {print "]"}
  ')"
  printf '%s\n' "$json_array" | yq e -p=json -r '
    .[] |
    ((.adamId // .adamID // .appId // .trackId // .id // "") | tostring) + "\t" +
    ((.trackName // .appName // .name // "") | tostring) + "\t" +
    ((.version // .bundleShortVersion // .bundleShortVersionString // "") | tostring) + "\t" +
    ((.bundleId // .bundleID // .bundleIdentifier // "") | tostring)
  ' - 2>/dev/null
}

appstore_parse_text_rows() {
  local text="$1"
  local line id version name
  mi_verbose "apps: parsing mas text output"
  printf '%s\n' "$text" | while IFS= read -r line; do
    [ -n "$line" ] || continue
    id="$(printf '%s\n' "$line" | awk '{print $1}')"
    version="$(printf '%s\n' "$line" | sed -n 's/.*(\([^)]*\))[[:space:]]*$/\1/p')"
    name="$(printf '%s\n' "$line" | sed -E 's/^[0-9]+[[:space:]]+//; s/[[:space:]]+\([^)]*\)[[:space:]]*$//')"
    [ -n "$id" ] || continue
    printf '%s\t%s\t%s\t%s\n' "$id" "$name" "$version" ""
  done
}

appstore_list_installed() {
  local mas_json mas_lines parsed
  mi_verbose "apps: trying mas list --json"
  if mi_mas_capture mas_json list --json && [ -n "$mas_json" ]; then
    parsed="$(appstore_parse_json_rows "$mas_json" 2>/dev/null || true)"
    if [ -n "$parsed" ]; then
      mi_verbose "apps: using mas JSON output"
      printf '%s\n' "$parsed"
      return 0
    fi
    mi_verbose "apps: mas JSON output was empty after parsing; falling back to text"
  else
    mi_verbose "apps: mas list --json unavailable or empty; falling back to text"
  fi

  mi_mas_capture mas_lines list || return 1
  appstore_parse_text_rows "$mas_lines"
}

appstore_emit_normalized_items() {
  local rows="$1"
  local raw_rows deduped id name version bundle_id skipped entry_word match
  local app_path app_name app_version output_name output_version output_path
  raw_rows="$(mktemp "${TMPDIR:-/tmp}/mac-setup-mas-rows.XXXXXX")" || return 1
  deduped="$(mktemp "${TMPDIR:-/tmp}/mac-setup-mas-deduped.XXXXXX")" || { rm -f "$raw_rows"; return 1; }
  printf '%s\n' "$rows" >"$raw_rows"
  awk -F '\t' 'NF >= 3 && $1 != "" && !seen[$1]++ {print}' "$raw_rows" >"$deduped"
  skipped="$(awk -F '\t' 'NF >= 3 && $1 != "" {seen[$1]++} END {dups=0; for (id in seen) if (seen[id] > 1) dups += seen[id] - 1; print dups}' "$raw_rows")"
  if [ "$skipped" != "0" ]; then
    entry_word="entries"
    [ "$skipped" = "1" ] && entry_word="entry"
    mi_warn "apps: skipped $skipped duplicate mas list $entry_word"
  fi

  mi_app_index_ensure || true
  while IFS="$(printf '\t')" read -r id name version bundle_id; do
    [ -n "$id" ] || continue
    mi_verbose "apps: considering mas app id=$id name=${name:-unknown} version=${version:-unknown} bundle_id=${bundle_id:-unknown}"
    match="$(mi_app_index_match_appstore_row "$id" "$name" "$bundle_id" || true)"
    if mi_app_index_has_appstore_markers && [ -z "$match" ]; then
      mi_warn "apps: skipped stale mas entry $id ${name:-<unknown>} because no installed app bundle matched it"
      continue
    fi
    output_name="$name"
    output_version="$version"
    output_path=""
    if [ -n "$match" ]; then
      IFS="|" read -r app_path app_name _ app_version _ _ <<EOF
$match
EOF
      [ -n "$app_name" ] && output_name="$app_name"
      [ -n "$app_version" ] && output_version="$app_version"
      output_path="$app_path"
      mi_verbose "apps: matched mas app id=$id to $app_path name=${output_name:-unknown} version=${output_version:-unknown}"
    fi
    mi_verbose "apps: recording mas app id=$id name=${output_name:-unknown}"
    printf '    - id: %s\n' "$(mi_yaml_scalar "$id")"
    printf '      ref: %s\n' "$(mi_yaml_scalar "$(mi_appstore_ref "$id")")"
    printf '      name: %s\n' "$(mi_yaml_scalar "$output_name")"
    printf '      path: %s\n' "$(mi_yaml_scalar "$output_path")"
    printf '      version: %s\n' "$(mi_yaml_scalar "$output_version")"
  done <"$deduped"
  rm -f "$raw_rows" "$deduped"
}

appstore_backup() {
  local app_rows
  printf 'apps:\n'
  if ! appstore_ensure_mas "backup"; then
    printf '  status: "skipped_mas_missing"\n'
    printf '  items: []\n'
    [ "$MI_APPSTORE_LOGIN" = "skip" ] && return 0
    return 1
  fi
  if ! app_rows="$(appstore_list_installed)"; then
    appstore_handle_missing_login "backup"
    mi_report_event warn apps mas_list_failed "mas list failed; App Store inventory could not continue"
    printf '  status: "skipped_mas_list_failed"\n'
    printf '  items: []\n'
    [ "$MI_APPSTORE_LOGIN" = "skip" ] && return 0
    return 1
  fi
  printf '  status: "ok"\n'
  printf '  items:\n'
  appstore_emit_normalized_items "$app_rows"
}

appstore_restore() {
  local installed_apps rows id ref name ignored
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
  rows="$(yq e -r '
    ([.apps[]? | select((type == "!!map") and has("id"))] + [(.apps | select(type == "!!map") | .items[]?) | select((type == "!!map") and has("id"))])[]? |
    (.id // "" | tostring) + "|" +
    (.ref // "" | tostring) + "|" +
    (.name // "" | tostring) + "|" +
    (.ignored // false | tostring)
  ' "$MI_INVENTORY" 2>/dev/null || true)"
  printf '%s\n' "$rows" | while IFS="|" read -r id ref name ignored; do
    [ -n "$id" ] && [ "$id" != "null" ] || continue
    if [ "$ignored" = "true" ]; then
      mi_info "apps: ignored $ref ${name:+($name)}; skipping"
      continue
    fi
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
