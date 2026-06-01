#!/usr/bin/env bash

brew_backup() {
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
    printf '%s\n' "$brew_casks" | while IFS= read -r line; do
      [ -n "$line" ] || continue
      name="$(printf '%s\n' "$line" | awk '{print $1}')"
      version="$(printf '%s\n' "$line" | cut -d' ' -f2-)"
      printf '    - name: %s\n' "$(mi_yaml_scalar "$name")"
      printf '      version: %s\n' "$(mi_yaml_scalar "$version")"
    done
    if [ -n "${MI_MATCHED_CASKS_FILE:-}" ] && [ -s "$MI_MATCHED_CASKS_FILE" ]; then
      sort -u "$MI_MATCHED_CASKS_FILE" | while IFS= read -r cask; do
        [ -n "$cask" ] || continue
        printf '    - name: %s\n' "$(mi_yaml_scalar "$cask")"
        printf '      version: "matched-manual-app"\n'
      done
    fi
  else
    printf '  formulae: []\n'
    printf '  casks: []\n'
  fi
}

brew_restore() {
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
  yq e '.brew.casks[]?.name' "$MI_INVENTORY" 2>/dev/null | while IFS= read -r name; do
    [ -n "$name" ] && [ "$name" != "null" ] || continue
    mi_validate_identifier "$name" || { mi_warn "invalid cask: $name"; continue; }
    if mi_brew_capture cask_check list --cask "$name" && [ "$MI_SKIP_EXISTING" = "true" ]; then
      mi_info "brew cask: $name already installed"
    else
      mi_brew_run install --cask "$name"
    fi
  done
}
