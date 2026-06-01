#!/usr/bin/env bash

npm_backup() {
  printf 'npm:\n'
  printf '  globals:\n'
  if ! mi_has npm; then
    return 0
  fi
  mi_npm_capture npm_globals list -g --depth=0 --parseable || return 0
  printf '%s\n' "$npm_globals" | tail -n +2 | while IFS= read -r path; do
    name="$(basename "$path")"
    [ -n "$name" ] || continue
    version=""
    if [ "$MI_RECORD_VERSIONS" = "true" ]; then
      mi_npm_capture npm_version view "$name" version && version="$npm_version"
    fi
    printf '    - name: %s\n' "$(mi_yaml_scalar "$name")"
    printf '      version: %s\n' "$(mi_yaml_scalar "$version")"
  done
}

npm_restore() {
  mi_has npm || { mi_warn "npm missing; skipping npm restore"; return 0; }
  yq e '.npm.globals[]?.name' "$MI_INVENTORY" 2>/dev/null | while IFS= read -r name; do
    [ -n "$name" ] && [ "$name" != "null" ] || continue
    mi_validate_identifier "$name" || { mi_warn "invalid npm package: $name"; continue; }
    if npm list -g "$name" --depth=0 >/dev/null 2>&1 && [ "$MI_SKIP_EXISTING" = "true" ]; then
      mi_info "npm: $name already installed"
    else
      mi_run npm install -g "$name"
    fi
  done
}
