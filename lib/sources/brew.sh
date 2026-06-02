#!/usr/bin/env bash

brew_backup() {
  local brew_taps brew_formulae brew_casks name version formula_version line cask display_name path app_version
  printf 'brew:\n'
  printf '  taps:\n'
  if mi_has brew; then
    mi_brew_capture brew_taps tap || brew_taps=""
    printf '%s\n' "$brew_taps" | while IFS= read -r tap; do
      [ -n "$tap" ] && printf '    - %s\n' "$(mi_yaml_scalar "$tap")"
    done
    printf '  formulae:\n'
    mi_brew_capture brew_formulae leaves || brew_formulae=""
    printf '%s\n' "$brew_formulae" | while IFS= read -r name; do
      [ -n "$name" ] || continue
      version=""
      if [ "$MI_RECORD_VERSIONS" = "true" ] && mi_brew_capture formula_version list --versions "$name"; then
        version="$(printf '%s\n' "$formula_version" | cut -d' ' -f2-)"
      fi
      printf '    - name: %s\n' "$(mi_yaml_scalar "$name")"
      printf '      version: %s\n' "$(mi_yaml_scalar "$version")"
    done
    printf '  casks:\n'
    mi_brew_capture brew_casks list --cask --versions || brew_casks=""
    if [ -n "$brew_casks" ] || { [ -n "${MI_MATCHED_CASKS_FILE:-}" ] && [ -s "$MI_MATCHED_CASKS_FILE" ]; }; then
      mi_app_index_ensure || true
    fi
    printf '%s\n' "$brew_casks" | while IFS= read -r line; do
      [ -n "$line" ] || continue
      name="$(printf '%s\n' "$line" | awk '{print $1}')"
      version="$(printf '%s\n' "$line" | cut -d' ' -f2-)"
      brew_emit_cask_item "$name" "$version" "" "" ""
    done
    if [ -n "${MI_MATCHED_CASKS_FILE:-}" ] && [ -s "$MI_MATCHED_CASKS_FILE" ]; then
      sort -u "$MI_MATCHED_CASKS_FILE" | while IFS="|" read -r cask display_name path app_version; do
        [ -n "$cask" ] || continue
        brew_emit_cask_item "$cask" "matched-manual-app" "$display_name" "$path" "$app_version"
      done
    fi
  else
    printf '  formulae: []\n'
    printf '  casks: []\n'
  fi
}

brew_emit_cask_item() {
  local name="$1"
  local version="$2"
  local display_name="${3:-}"
  local path="${4:-}"
  local app_version="${5:-}"
  local match app_path app_name app_bundle_id matched_version
  match="$(mi_app_index_match_cask_row "$name" || true)"
  if [ -n "$match" ]; then
    IFS="|" read -r app_path app_name app_bundle_id matched_version _ _ <<EOF
$match
EOF
    [ -n "$display_name" ] || display_name="$app_name"
    [ -n "$path" ] || path="$app_path"
    [ -n "$app_version" ] || app_version="$matched_version"
    mi_verbose "brew: matched cask $name to app ${display_name:-unknown} path=${path:-unknown} bundle_id=${app_bundle_id:-unknown}"
  elif [ -n "$display_name" ] || [ -n "$path" ]; then
    mi_verbose "brew: using manual app metadata for cask $name path=${path:-unknown}"
  else
    mi_verbose "brew: no installed app match for cask $name"
  fi
  printf '    - name: %s\n' "$(mi_yaml_scalar "$name")"
  printf '      ref: %s\n' "$(mi_yaml_scalar "$(mi_brew_cask_ref "$name")")"
  printf '      version: %s\n' "$(mi_yaml_scalar "$version")"
  printf '      display_name: %s\n' "$(mi_yaml_scalar "$display_name")"
  printf '      path: %s\n' "$(mi_yaml_scalar "$path")"
  printf '      app_version: %s\n' "$(mi_yaml_scalar "$app_version")"
}

brew_restore() {
  local installed_taps tap name ref display_name ignored cask_rows
  mi_has brew || { mi_warn "brew missing; skipping Homebrew restore"; return 0; }
  mi_brew_capture installed_taps tap || installed_taps=""
  yq e '.brew.taps[]?' "$MI_INVENTORY" 2>/dev/null | while IFS= read -r tap; do
    [ -n "$tap" ] && [ "$tap" != "null" ] || continue
    mi_validate_identifier "$tap" || { mi_warn "invalid tap: $tap"; continue; }
    printf '%s\n' "$installed_taps" | grep -Fxq "$tap" || mi_brew_run tap "$tap"
  done
  yq e '.brew.formulae[]?.name' "$MI_INVENTORY" 2>/dev/null | while IFS= read -r name; do
    [ -n "$name" ] && [ "$name" != "null" ] || continue
    mi_validate_identifier "$name" || { mi_warn "invalid formula: $name"; continue; }
    if mi_brew_capture formula_check list --formula "$name" && [ "$MI_SKIP_EXISTING" = "true" ]; then
      mi_info "brew: $name already installed"
    else
      mi_brew_run install "$name"
    fi
  done
  cask_rows="$(yq e -r '
    (.brew.casks // [])[]? |
    (.name // "" | tostring) + "|" +
    (.ref // "" | tostring) + "|" +
    (.display_name // "" | tostring) + "|" +
    (.ignored // false | tostring)
  ' "$MI_INVENTORY" 2>/dev/null || true)"
  printf '%s\n' "$cask_rows" | while IFS="|" read -r name ref display_name ignored; do
    [ -n "$name" ] && [ "$name" != "null" ] || continue
    if [ "$ignored" = "true" ]; then
      mi_info "brew cask: ignored ${ref:-$name} ${display_name:+($display_name)}; skipping"
      continue
    fi
    mi_validate_identifier "$name" || { mi_warn "invalid cask: $name"; continue; }
    if mi_brew_capture cask_check list --cask "$name" && [ "$MI_SKIP_EXISTING" = "true" ]; then
      mi_info "brew cask: $name already installed"
    else
      mi_brew_run install --cask "$name"
    fi
  done
}
