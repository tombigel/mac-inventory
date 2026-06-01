#!/usr/bin/env bash

brew_backup() {
  printf 'brew:\n'
  printf '  taps:\n'
  if mi_has brew; then
    brew tap 2>/dev/null | while IFS= read -r tap; do
      [ -n "$tap" ] && printf '    - %s\n' "$(mi_yaml_scalar "$tap")"
    done
    printf '  formulae:\n'
    brew leaves --versions 2>/dev/null | while IFS= read -r line; do
      [ -n "$line" ] || continue
      name="$(printf '%s\n' "$line" | awk '{print $1}')"
      version="$(printf '%s\n' "$line" | cut -d' ' -f2-)"
      printf '    - name: %s\n' "$(mi_yaml_scalar "$name")"
      printf '      version: %s\n' "$(mi_yaml_scalar "$version")"
    done
    printf '  casks:\n'
    brew list --cask --versions 2>/dev/null | while IFS= read -r line; do
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
  yq e '.brew.taps[]?' "$MI_INVENTORY" 2>/dev/null | while IFS= read -r tap; do
    [ -n "$tap" ] && [ "$tap" != "null" ] || continue
    mi_validate_identifier "$tap" || { mi_warn "invalid tap: $tap"; continue; }
    brew tap | grep -Fxq "$tap" || mi_run brew tap "$tap"
  done
  yq e '.brew.formulae[]?.name' "$MI_INVENTORY" 2>/dev/null | while IFS= read -r name; do
    [ -n "$name" ] && [ "$name" != "null" ] || continue
    mi_validate_identifier "$name" || { mi_warn "invalid formula: $name"; continue; }
    if brew list --formula "$name" >/dev/null 2>&1 && [ "$MI_SKIP_EXISTING" = "true" ]; then
      mi_info "brew: $name already installed"
    else
      mi_run brew install "$name"
    fi
  done
  yq e '.brew.casks[]?.name' "$MI_INVENTORY" 2>/dev/null | while IFS= read -r name; do
    [ -n "$name" ] && [ "$name" != "null" ] || continue
    mi_validate_identifier "$name" || { mi_warn "invalid cask: $name"; continue; }
    if brew list --cask "$name" >/dev/null 2>&1 && [ "$MI_SKIP_EXISTING" = "true" ]; then
      mi_info "brew cask: $name already installed"
    else
      mi_run brew install --cask "$name"
    fi
  done
}
