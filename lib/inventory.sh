#!/usr/bin/env bash
# shellcheck disable=SC2016

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
    mi_info "dry-run: would write setup snapshot to $MI_INVENTORY"
    tmp_dry="$(mktemp "${TMPDIR:-/tmp}/mac-setup-dry.XXXXXX")" || return 1
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

  mi_inventory_emit_or_copy "$inventory_out" apps appstore_backup || return 1
  MI_MATCHED_CASKS_FILE="$(mktemp "${TMPDIR:-/tmp}/mac-setup-casks.XXXXXX")"
  export MI_MATCHED_CASKS_FILE
  mi_inventory_emit_or_copy "$inventory_out" manual_apps manual_apps_backup || return 1
  mi_inventory_emit_or_copy "$inventory_out" brew brew_backup || return 1
  mi_inventory_emit_or_copy "$inventory_out" npm npm_backup || return 1
  mi_inventory_emit_or_copy "$inventory_out" pip pip_backup || return 1
  mi_inventory_emit_or_copy "$inventory_out" pipx pipx_backup || return 1
  mi_inventory_emit_or_copy "$inventory_out" oh_my_zsh oh_my_zsh_backup || return 1
  mi_inventory_emit_or_copy "$inventory_out" xcode xcode_backup || return 1
  mi_inventory_emit_or_copy "$inventory_out" dotfiles dotfiles_backup || return 1
  rm -f "$MI_MATCHED_CASKS_FILE"
}

mi_inventory_emit_or_copy() {
  local target_out="$1"
  local section="$2"
  local fn="$3"
  if mi_source_enabled "$section" && mi_section_selected "$section"; then
    if ! "$fn" >>"$target_out"; then
      if [ "$section" = "apps" ] && [ "$MI_APPSTORE_LOGIN" != "skip" ]; then
        mi_error "backup: App Store inventory is required; pass --apps=false or --appstore-login=skip to skip it"
        return 1
      fi
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
  [ -f "$MI_INVENTORY" ] || { mi_error "setup snapshot not found: $MI_INVENTORY"; return 1; }
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
    md)
      mi_inventory_list_md
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

mi_inventory_md_section_selected() {
  mi_section_selected "$1" || return 1
}

mi_inventory_md_table() {
  local title="$1"
  local header="$2"
  local query="$3"
  local rows
  printf '\n## %s\n\n' "$title"
  printf '%s\n' "$header"
  rows="$(yq e -r "$query" "$MI_INVENTORY" 2>/dev/null || true)"
  if [ -n "$rows" ]; then
    printf '%s\n' "$rows"
  else
    printf '_None recorded._\n'
  fi
}

mi_inventory_list_md() {
  local value
  mi_require_yq || return 1

  printf '# Mac Setup Snapshot\n\n'
  value="$(yq e '.created_at // ""' "$MI_INVENTORY" 2>/dev/null)"
  [ -n "$value" ] && [ "$value" != "null" ] && printf "%s \`%s\`\n" "- Created:" "$value"
  value="$(yq e '.updated_at // ""' "$MI_INVENTORY" 2>/dev/null)"
  [ -n "$value" ] && [ "$value" != "null" ] && printf "%s \`%s\`\n" "- Updated:" "$value"
  printf "%s \`%s\`\n" "- Snapshot:" "$MI_INVENTORY"

  if mi_inventory_md_section_selected host; then
    printf '\n## Host\n\n'
    yq e -r '
      .host // {} |
      ["| Field | Value |", "| --- | --- |"] +
      (to_entries | map("| " + .key + " | " + (.value // "" | tostring) + " |")) |
      .[]
    ' "$MI_INVENTORY"
  fi

  mi_inventory_md_section_selected apps && mi_inventory_md_table "App Store Apps" "| ID | Name | Version |
| --- | --- | --- |" '
    (.apps.items // .apps // [])[]? |
    "| " + (.id // "" | tostring) + " | " + (.name // "" | tostring) + " | " + (.version // "" | tostring) + " |"
  '

  if mi_inventory_md_section_selected brew; then
    mi_inventory_md_table "Homebrew Formulae" "| Name | Version |
| --- | --- |" '
      (.brew.formulae // [])[]? |
      "| " + (.name // "" | tostring) + " | " + (.version // "" | tostring) + " |"
    '
    mi_inventory_md_table "Homebrew Casks" "| Name | Version |
| --- | --- |" '
      (.brew.casks // [])[]? |
      "| " + (.name // "" | tostring) + " | " + (.version // "" | tostring) + " |"
    '
  fi

  mi_inventory_md_section_selected npm && mi_inventory_md_table "npm Globals" "| Name | Version |
| --- | --- |" '
    (.npm.globals // [])[]? |
    "| " + (.name // "" | tostring) + " | " + (.version // "" | tostring) + " |"
  '

  mi_inventory_md_section_selected pip && mi_inventory_md_table "pip Packages" "| Name | Version |
| --- | --- |" '
    (.pip.packages // [])[]? |
    "| " + (.name // "" | tostring) + " | " + (.version // "" | tostring) + " |"
  '

  mi_inventory_md_section_selected pipx && mi_inventory_md_table "pipx Packages" "| Name | Version |
| --- | --- |" '
    (.pipx.packages // [])[]? |
    "| " + (.name // "" | tostring) + " | " + (.version // "" | tostring) + " |"
  '

  if mi_inventory_md_section_selected oh_my_zsh; then
    printf '\n## Oh My Zsh\n\n'
    yq e -r '
      .oh_my_zsh // {} |
      ["| Field | Value |", "| --- | --- |"] +
      (to_entries | map("| " + .key + " | " + (.value // "" | tostring) + " |")) |
      .[]
    ' "$MI_INVENTORY"
  fi

  if mi_inventory_md_section_selected xcode; then
    printf '\n## Xcode\n\n'
    yq e -r '
      .xcode // {} |
      ["| Field | Value |", "| --- | --- |"] +
      (to_entries | map("| " + .key + " | " + (.value // "" | tostring) + " |")) |
      .[]
    ' "$MI_INVENTORY"
  fi

  mi_inventory_md_section_selected dotfiles && mi_inventory_md_table "Dotfiles" "| Path | Exists | Backup Path |
| --- | --- | --- |" '
    (.dotfiles.files // [])[]? |
    "| " + (.path // "" | tostring) + " | " + (.exists // "" | tostring) + " | " + (.backup_path // "" | tostring) + " |"
  '

  mi_inventory_md_section_selected manual_apps && mi_inventory_md_table "Manual Apps" "| Name | Path | Version | Brew Cask |
| --- | --- | --- | --- |" '
    (.manual_apps.apps // [])[]? |
    "| " + (.name // "" | tostring) + " | " + (.path // "" | tostring) + " | " + (.version // "" | tostring) + " | " + (.selected_brew_cask // .brew_cask_candidate // "" | tostring) + " |"
  '
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
  [ -f "$MI_INVENTORY" ] || { mi_error "setup snapshot not found: $MI_INVENTORY"; return 1; }
  mi_require_yq || return 1

  mi_restore_section apps appstore_restore || return 1
  mi_restore_section brew brew_restore || return 1
  mi_restore_section npm npm_restore || return 1
  mi_restore_section pip pip_restore || return 1
  mi_restore_section pipx pipx_restore || return 1
  mi_restore_section oh_my_zsh oh_my_zsh_restore || return 1
  mi_restore_section xcode xcode_restore || return 1
  mi_restore_section dotfiles dotfiles_restore || return 1
  mi_restore_section manual_apps manual_apps_restore || return 1
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
