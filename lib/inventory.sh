#!/usr/bin/env bash

mi_source_enabled() {
  case "$1" in
    apps) [ "$MI_APPS" = "true" ] ;;
    brew) [ "$MI_BREW" = "true" ] ;;
    npm) [ "$MI_NPM" = "true" ] ;;
    pip) [ "$MI_PIP" = "true" ] ;;
    pipx) [ "$MI_PIPX" = "true" ] ;;
    oh_my_zsh) [ "$MI_OH_MY_ZSH" = "true" ] ;;
    xcode) [ "$MI_XCODE" = "true" ] ;;
    dotfiles) [ "$MI_DOTFILES" = "true" ] ;;
    manual_apps) [ "$MI_MANUAL_APPS" = "true" ] ;;
    *) return 1 ;;
  esac
}

mi_section_selected() {
  local section="$1"
  if [ -z "$MI_SECTIONS" ]; then
    return 0
  fi
  printf '%s\n' "$MI_SECTIONS" | grep -Fxq "$section"
}

mi_inventory_backup() {
  local tmp tmp_dry

  if [ "$MI_DRY_RUN" = "true" ]; then
    mi_info "dry-run: would write inventory to $MI_INVENTORY"
    tmp_dry="$(mktemp "${TMPDIR:-/tmp}/mac-inventory-dry.XXXXXX")" || return 1
    mi_inventory_emit_backup "$tmp_dry" || { rm -f "$tmp_dry"; return 1; }
    cat "$tmp_dry"
    rm -f "$tmp_dry"
    return 0
  fi

  tmp="$(mktemp "${MI_INVENTORY}.tmp.XXXXXX")" || return 1
  mi_inventory_emit_backup "$tmp" || { rm -f "$tmp"; return 1; }
  mi_mkdir_parent "$MI_INVENTORY"
  mv "$tmp" "$MI_INVENTORY"
  mi_info "wrote $MI_INVENTORY"
}

mi_inventory_emit_backup() {
  local inventory_out="$1"
  {
    printf 'version: 1\n'
    printf 'created_at: %s\n' "$(mi_yaml_scalar "$(mi_timestamp)")"
    printf 'updated_at: %s\n' "$(mi_yaml_scalar "$(mi_timestamp)")"
    printf 'host:\n'
    printf '  hostname: %s\n' "$(mi_yaml_scalar "$(hostname 2>/dev/null || printf unknown)")"
    printf '  macos: %s\n' "$(mi_yaml_scalar "$(sw_vers -productVersion 2>/dev/null || uname -r)")"
    printf '  arch: %s\n' "$(mi_yaml_scalar "$(uname -m)")"
  } >"$inventory_out"

  mi_inventory_emit_or_copy "$inventory_out" apps appstore_backup
  MI_MATCHED_CASKS_FILE="$(mktemp "${TMPDIR:-/tmp}/mac-inventory-casks.XXXXXX")"
  export MI_MATCHED_CASKS_FILE
  mi_inventory_emit_or_copy "$inventory_out" manual_apps manual_apps_backup
  mi_inventory_emit_or_copy "$inventory_out" brew brew_backup
  mi_inventory_emit_or_copy "$inventory_out" npm npm_backup
  mi_inventory_emit_or_copy "$inventory_out" pip pip_backup
  mi_inventory_emit_or_copy "$inventory_out" pipx pipx_backup
  mi_inventory_emit_or_copy "$inventory_out" oh_my_zsh oh_my_zsh_backup
  mi_inventory_emit_or_copy "$inventory_out" xcode xcode_backup
  mi_inventory_emit_or_copy "$inventory_out" dotfiles dotfiles_backup
  rm -f "$MI_MATCHED_CASKS_FILE"
}

mi_inventory_emit_or_copy() {
  local target_out="$1"
  local section="$2"
  local fn="$3"
  if mi_source_enabled "$section" && mi_section_selected "$section"; then
    if ! "$fn" >>"$target_out"; then
      mi_warn "backup: section $section reported a non-fatal error; continuing"
    fi
  elif [ "$MI_UPDATE" = "true" ] && [ -f "$MI_INVENTORY" ]; then
    mi_inventory_copy_section "$MI_INVENTORY" "$section" >>"$target_out"
  fi
  return 0
}

mi_inventory_copy_section() {
  local file="$1"
  local section="$2"
  awk -v section="$section" '
    $0 ~ "^" section ":" {printing=1; print; next}
    printing && /^[A-Za-z0-9_]+:/ {printing=0}
    printing {print}
  ' "$file"
}

mi_inventory_list() {
  [ -f "$MI_INVENTORY" ] || { mi_error "inventory not found: $MI_INVENTORY"; return 1; }
  case "$MI_FORMAT" in
    yaml)
      if [ -z "$MI_SECTIONS" ]; then
        cat "$MI_INVENTORY"
      else
        while IFS= read -r section; do
          mi_inventory_copy_section "$MI_INVENTORY" "$section"
        done <<EOF
$MI_SECTIONS
EOF
      fi
      ;;
    json)
      mi_require_yq || return 1
      yq e -o=json "$MI_INVENTORY"
      ;;
    table)
      if [ -z "$MI_SECTIONS" ]; then
        awk -F: '/^[A-Za-z0-9_]+:/ {print $1}' "$MI_INVENTORY"
      else
        printf '%s\n' "$MI_SECTIONS"
      fi
      ;;
  esac
}

mi_inventory_restore() {
  if [ "$MI_SKIP_PREPARE" != "true" ]; then
    if [ "$MI_PREPARE_ONLY" = "true" ]; then
      mi_workflow_run "prepare"
      return $?
    fi
    mi_workflow_run "restore"
    return $?
  fi
  mi_inventory_restore_body
}

mi_inventory_restore_body() {
  [ -f "$MI_INVENTORY" ] || { mi_error "inventory not found: $MI_INVENTORY"; return 1; }
  mi_require_yq || return 1

  mi_restore_section apps appstore_restore
  mi_restore_section brew brew_restore
  mi_restore_section npm npm_restore
  mi_restore_section pip pip_restore
  mi_restore_section pipx pipx_restore
  mi_restore_section oh_my_zsh oh_my_zsh_restore
  mi_restore_section xcode xcode_restore
  mi_restore_section dotfiles dotfiles_restore
  mi_restore_section manual_apps manual_apps_restore
}

mi_restore_section() {
  local section="$1"
  local fn="$2"
  mi_source_enabled "$section" || return 0
  mi_section_selected "$section" || return 0
  "$fn"
}

mi_doctor() {
  mi_doctor_tool brew
  mi_doctor_tool yq
  mi_doctor_tool mas
  mi_doctor_tool npm
  mi_doctor_tool pip3
  mi_doctor_tool pipx
  mi_doctor_github
  appstore_doctor
  oh_my_zsh_doctor
  xcode_doctor
}

mi_doctor_tool() {
  if mi_has "$1"; then
    mi_info "$1: found"
  else
    mi_warn "$1: missing"
  fi
}
