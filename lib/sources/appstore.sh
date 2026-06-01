#!/usr/bin/env bash

appstore_backup() {
  printf 'apps:\n'
  if ! mi_has mas; then
    printf '  []\n'
    return 0
  fi
  mas list 2>/dev/null | while IFS= read -r line; do
    [ -n "$line" ] || continue
    id="$(printf '%s\n' "$line" | awk '{print $1}')"
    version="$(printf '%s\n' "$line" | sed -n 's/.*(\([^)]*\)).*/\1/p')"
    name="$(printf '%s\n' "$line" | sed -E 's/^[0-9]+[[:space:]]+//; s/[[:space:]]+\([^)]*\)$//')"
    printf '  - id: %s\n' "$(mi_yaml_scalar "$id")"
    printf '    name: %s\n' "$(mi_yaml_scalar "$name")"
    printf '    version: %s\n' "$(mi_yaml_scalar "$version")"
  done
}

appstore_restore() {
  mi_has mas || { mi_warn "mas missing; skipping App Store restore"; return 0; }
  yq e '.apps[]?.id' "$MI_INVENTORY" 2>/dev/null | while IFS= read -r id; do
    [ -n "$id" ] && [ "$id" != "null" ] || continue
    mi_validate_identifier "$id" || { mi_warn "invalid App Store id: $id"; continue; }
    if mas list 2>/dev/null | awk '{print $1}' | grep -Fxq "$id"; then
      mi_info "apps: $id already installed"
    else
      mi_run mas install "$id"
    fi
  done
}

appstore_doctor() {
  if mi_has mas; then
    if mas account >/dev/null 2>&1; then
      mi_info "appstore: signed in"
    else
      mi_warn "appstore: mas is installed but not signed in"
    fi
  fi
}

