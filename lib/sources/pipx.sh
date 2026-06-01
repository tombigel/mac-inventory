#!/usr/bin/env bash

pipx_backup() {
  printf 'pipx:\n'
  printf '  packages:\n'
  if ! mi_has pipx; then
    return 0
  fi
  pipx list --short 2>/dev/null | while IFS= read -r line; do
    name="$(printf '%s\n' "$line" | awk '{print $1}')"
    version="$(printf '%s\n' "$line" | awk '{print $2}')"
    [ -n "$name" ] || continue
    printf '    - name: %s\n' "$(mi_yaml_scalar "$name")"
    printf '      version: %s\n' "$(mi_yaml_scalar "$version")"
  done
}

pipx_restore() {
  mi_has pipx || { mi_warn "pipx missing; skipping pipx restore"; return 0; }
  yq e '.pipx.packages[]?.name' "$MI_INVENTORY" 2>/dev/null | while IFS= read -r name; do
    [ -n "$name" ] && [ "$name" != "null" ] || continue
    mi_validate_identifier "$name" || { mi_warn "invalid pipx package: $name"; continue; }
    if pipx list --short 2>/dev/null | awk '{print $1}' | grep -Fxq "$name" && [ "$MI_SKIP_EXISTING" = "true" ]; then
      mi_info "pipx: $name already installed"
    else
      mi_run pipx install "$name"
    fi
  done
}

