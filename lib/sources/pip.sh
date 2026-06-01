#!/usr/bin/env bash

pip_backup() {
  printf 'pip:\n'
  printf '  packages:\n'
  if ! mi_has pip3; then
    return 0
  fi
  pip3 list --format=freeze 2>/dev/null | while IFS= read -r line; do
    case "$line" in
      *"=="*) name="${line%%==*}"; version="${line#*==}" ;;
      *) name="$line"; version="" ;;
    esac
    [ -n "$name" ] || continue
    printf '    - name: %s\n' "$(mi_yaml_scalar "$name")"
    printf '      version: %s\n' "$(mi_yaml_scalar "$version")"
  done
}

pip_restore() {
  mi_has pip3 || { mi_warn "pip3 missing; skipping pip restore"; return 0; }
  yq e '.pip.packages[]?.name' "$MI_INVENTORY" 2>/dev/null | while IFS= read -r name; do
    [ -n "$name" ] && [ "$name" != "null" ] || continue
    mi_validate_identifier "$name" || { mi_warn "invalid pip package: $name"; continue; }
    if pip3 show "$name" >/dev/null 2>&1 && [ "$MI_SKIP_EXISTING" = "true" ]; then
      mi_info "pip: $name already installed"
    else
      mi_run pip3 install "$name"
    fi
  done
}

