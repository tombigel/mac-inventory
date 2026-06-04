#!/usr/bin/env bash

mi_app_ref_key() {
  printf '%s\n' "$1" | tr '[:upper:]' '[:lower:]' | sed 's/\.app$//; s/[^a-z0-9]/-/g; s/--*/-/g; s/^-//; s/-$//'
}

mi_string_hash() {
  local value="$1"
  if mi_has shasum; then
    printf '%s' "$value" | shasum -a 256 | awk '{print substr($1,1,8)}'
  elif mi_has sha256sum; then
    printf '%s' "$value" | sha256sum | awk '{print substr($1,1,8)}'
  else
    printf '%s' "$value" | cksum | awk '{print $1}'
  fi
}

mi_appstore_ref() {
  printf 'appstore:%s\n' "$1"
}

mi_brew_tap_ref() {
  printf 'brew_tap:%s\n' "$1"
}

mi_brew_formula_ref() {
  printf 'brew_formula:%s\n' "$1"
}

mi_brew_cask_ref() {
  printf 'brew_cask:%s\n' "$1"
}

mi_npm_ref() {
  printf 'npm:%s\n' "$1"
}

mi_pip_ref() {
  printf 'pip:%s\n' "$1"
}

mi_pipx_ref() {
  printf 'pipx:%s\n' "$1"
}

mi_dotfile_ref() {
  local path="$1"
  local key hash
  key="$(mi_app_ref_key "$path")"
  [ -n "$key" ] || key="file"
  hash="$(mi_string_hash "$path")"
  printf 'dotfile:%s-%s\n' "$key" "$hash"
}

mi_oh_my_zsh_ref() {
  printf 'oh_my_zsh:state\n'
}

mi_xcode_ref() {
  printf 'xcode:state\n'
}

mi_manual_app_ref() {
  local bundle_id="$1"
  local name="$2"
  local path="$3"
  local key hash
  if [ -n "$bundle_id" ]; then
    printf 'manual:%s\n' "$bundle_id"
    return 0
  fi
  key="$(mi_app_ref_key "$name")"
  [ -n "$key" ] || key="app"
  hash="$(mi_string_hash "$path|$name")"
  printf 'manual:%s-%s\n' "$key" "$hash"
}

mi_github_project_ref() {
  local owner_repo="$1"
  [ -n "$owner_repo" ] || owner_repo="project-$(mi_string_hash "$2")"
  printf 'github_project:%s\n' "$owner_repo"
}

mi_ignore_normalize() {
  printf '%s\n' "$1" | sed 's/\.app$//' | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]//g'
}

mi_ignore_basename_no_app() {
  local value="$1"
  value="$(basename -- "$value" 2>/dev/null || printf '%s' "$value")"
  printf '%s\n' "${value%.app}"
}

mi_ignore_effective_ref() {
  local type="$1"
  local ref="$2"
  local id="$3"
  local name="$4"
  local path="$5"
  local token1="$6"
  [ -n "$ref" ] && [ "$ref" != "null" ] && { printf '%s\n' "$ref"; return 0; }
  case "$type" in
    appstore) mi_appstore_ref "$id" ;;
    brew_tap) mi_brew_tap_ref "$id" ;;
    brew_formula) mi_brew_formula_ref "$id" ;;
    brew_cask) mi_brew_cask_ref "$id" ;;
    npm) mi_npm_ref "$id" ;;
    pip) mi_pip_ref "$id" ;;
    pipx) mi_pipx_ref "$id" ;;
    dotfile) mi_dotfile_ref "$id" ;;
    oh_my_zsh) mi_oh_my_zsh_ref ;;
    xcode) mi_xcode_ref ;;
    github_project) mi_github_project_ref "$id" "$path" ;;
    manual) mi_manual_app_ref "$id" "$name" "$path" ;;
  esac
}

mi_ignore_row_matches() {
  local token="$1"
  local token_norm="$2"
  local type="$3"
  local ref="$4"
  local id="$5"
  local name="$6"
  local path="$7"
  local token1="$8"
  local token2="$9"
  local value base value_norm

  for value in "$ref" "$id" "$name" "$path" "$token1" "$token2"; do
    [ -n "$value" ] && [ "$value" != "null" ] || continue
    [ "$token" = "$value" ] && return 0
  done

  case "$type" in
    appstore)
      for value in "$name" "$(mi_ignore_basename_no_app "$path")"; do
        value_norm="$(mi_ignore_normalize "$value")"
        [ -n "$value_norm" ] && [ "$token_norm" = "$value_norm" ] && return 0
      done
      ;;
    brew_cask)
      base="$(mi_ignore_basename_no_app "$path")"
      for value in "$id" "$name" "$base"; do
        value_norm="$(mi_ignore_normalize "$value")"
        [ -n "$value_norm" ] && [ "$token_norm" = "$value_norm" ] && return 0
      done
      ;;
    manual)
      base="$(mi_ignore_basename_no_app "$path")"
      for value in "$name" "$base" "$token1" "$token2"; do
        value_norm="$(mi_ignore_normalize "$value")"
        [ -n "$value_norm" ] && [ "$token_norm" = "$value_norm" ] && return 0
      done
      ;;
    *)
      for value in "$id" "$name" "$(mi_ignore_basename_no_app "$path")"; do
        value_norm="$(mi_ignore_normalize "$value")"
        [ -n "$value_norm" ] && [ "$token_norm" = "$value_norm" ] && return 0
      done
      ;;
  esac

  return 1
}

mi_ignore_inventory_rows() {
  local inventory="$1"
  yq e -r '
    (.apps.items // []) | to_entries[]? |
      "appstore" + "|" + ".apps.items[" + (.key | tostring) + "]" + "|" +
      (.value.ref // "" | tostring) + "|" + (.value.id // "" | tostring) + "|" + (.value.name // "" | tostring) + "|" +
      (.value.path // "" | tostring) + "|" + "" + "|" + ""
  ' "$inventory" 2>/dev/null
  yq e -r '
    (.brew.taps // []) | to_entries[]? |
      "brew_tap" + "|" + ".brew.taps[" + (.key | tostring) + "]" + "|" +
      (.value.ref // "" | tostring) + "|" + (.value.name // "" | tostring) + "|" + (.value.name // "" | tostring) + "|" + "" + "|" + "" + "|"
  ' "$inventory" 2>/dev/null
  yq e -r '
    (.brew.formulae // []) | to_entries[]? |
      "brew_formula" + "|" + ".brew.formulae[" + (.key | tostring) + "]" + "|" +
      (.value.ref // "" | tostring) + "|" + (.value.name // "" | tostring) + "|" + (.value.name // "" | tostring) + "|" +
      "" + "|" + "" + "|"
  ' "$inventory" 2>/dev/null
  yq e -r '
    (.brew.casks // []) | to_entries[]? |
      "brew_cask" + "|" + ".brew.casks[" + (.key | tostring) + "]" + "|" +
      (.value.ref // "" | tostring) + "|" + (.value.name // "" | tostring) + "|" + (.value.display_name // "" | tostring) + "|" +
      (.value.path // "" | tostring) + "|" + "" + "|" + ""
  ' "$inventory" 2>/dev/null
  yq e -r '
    (.npm.globals // []) | to_entries[]? |
      "npm" + "|" + ".npm.globals[" + (.key | tostring) + "]" + "|" +
      (.value.ref // "" | tostring) + "|" + (.value.name // "" | tostring) + "|" + (.value.name // "" | tostring) + "|" +
      "" + "|" + "" + "|"
  ' "$inventory" 2>/dev/null
  yq e -r '
    (.pip.packages // []) | to_entries[]? |
      "pip" + "|" + ".pip.packages[" + (.key | tostring) + "]" + "|" +
      (.value.ref // "" | tostring) + "|" + (.value.name // "" | tostring) + "|" + (.value.name // "" | tostring) + "|" +
      "" + "|" + "" + "|"
  ' "$inventory" 2>/dev/null
  yq e -r '
    (.pipx.packages // []) | to_entries[]? |
      "pipx" + "|" + ".pipx.packages[" + (.key | tostring) + "]" + "|" +
      (.value.ref // "" | tostring) + "|" + (.value.name // "" | tostring) + "|" + (.value.name // "" | tostring) + "|" +
      "" + "|" + "" + "|"
  ' "$inventory" 2>/dev/null
  yq e -r '
    (.dotfiles.files // []) | to_entries[]? |
      "dotfile" + "|" + ".dotfiles.files[" + (.key | tostring) + "]" + "|" +
      (.value.ref // "" | tostring) + "|" + (.value.path // "" | tostring) + "|" + (.value.path // "" | tostring) + "|" +
      (.value.backup_path // "" | tostring) + "|" + "" + "|"
  ' "$inventory" 2>/dev/null
  yq e -r '
    (.github_projects.repos // []) | to_entries[]? |
      "github_project" + "|" + ".github_projects.repos[" + (.key | tostring) + "]" + "|" +
      (.value.ref // "" | tostring) + "|" + (.value.owner_repo // "" | tostring) + "|" + (.value.name // "" | tostring) + "|" +
      (.value.relative_path // "" | tostring) + "|" +
      (.value.clone_url // "" | tostring) + "|" +
      (.value.origin_url // "" | tostring)
  ' "$inventory" 2>/dev/null
  yq e -r '
    .oh_my_zsh | select(type == "!!map") |
      "oh_my_zsh|.oh_my_zsh|" + (.ref // "" | tostring) + "|oh_my_zsh|Oh My Zsh|" + (.path // "" | tostring) + "||"
  ' "$inventory" 2>/dev/null
  yq e -r '
    .xcode | select(type == "!!map") |
      "xcode|.xcode|" + (.ref // "" | tostring) + "|xcode|Xcode|" + (.developer_dir // "" | tostring) + "||"
  ' "$inventory" 2>/dev/null
  yq e -r '
    (.manual_apps.apps // []) | to_entries[]? |
      "manual" + "|" + ".manual_apps.apps[" + (.key | tostring) + "]" + "|" +
      (.value.ref // "" | tostring) + "|" + (.value.bundle_id // "" | tostring) + "|" + (.value.name // "" | tostring) + "|" +
      (.value.path // "" | tostring) + "|" +
      ((.value.selected_brew_cask // .value.brew_cask_candidate // "") | tostring) + "|" +
      (.value.brew_cask_candidate // "" | tostring)
  ' "$inventory" 2>/dev/null
}

mi_ignore_find_matches() {
  local inventory="$1"
  local token="$2"
  local matches="$3"
  local token_norm type path_expr ref id name app_path token1 token2 effective_ref label
  token_norm="$(mi_ignore_normalize "$token")"
  : >"$matches"
  mi_ignore_inventory_rows "$inventory" | while IFS="|" read -r type path_expr ref id name app_path token1 token2; do
    [ -n "$type" ] || continue
    effective_ref="$(mi_ignore_effective_ref "$type" "$ref" "$id" "$name" "$app_path" "$token1")"
    mi_ignore_row_matches "$token" "$token_norm" "$type" "$effective_ref" "$id" "$name" "$app_path" "$token1" "$token2" || continue
    label="$name"
    [ -n "$label" ] || label="$id"
    printf '%s|%s|%s|%s|%s\n' "$type" "$path_expr" "$effective_ref" "$label" "$id" >>"$matches"
  done
}

mi_ignore_write_inventory() {
  local inventory="$1"
  local path_expr="$2"
  local ref="$3"
  local action="$4"
  local type="$5"
  local id="$6"
  local label="$7"
  local tmp stamp
  stamp="$(mi_timestamp)"
  tmp="$(mktemp "${inventory}.tmp.XXXXXX")" || return 1
  case "$action" in
    ignore)
      MI_IGNORE_REF="$ref" MI_IGNORE_AT="$stamp" yq e \
        "($path_expr.ref) = strenv(MI_IGNORE_REF) | ($path_expr.ignored) = true | ($path_expr.ignored_at) = strenv(MI_IGNORE_AT) | .updated_at = strenv(MI_IGNORE_AT)" \
        "$inventory" >"$tmp" || { rm -f "$tmp"; return 1; }
      ;;
    unignore)
      MI_IGNORE_REF="$ref" MI_IGNORE_AT="$stamp" yq e \
        "($path_expr.ref) = strenv(MI_IGNORE_REF) | ($path_expr.ignored) = false | del($path_expr.ignored_at) | .updated_at = strenv(MI_IGNORE_AT)" \
        "$inventory" >"$tmp" || { rm -f "$tmp"; return 1; }
      ;;
  esac
  mv "$tmp" "$inventory"
}

mi_ignore_ensure_config_file() {
  [ -f "$MI_CONFIG" ] && return 0
  mi_mkdir_parent "$MI_CONFIG"
  {
    printf 'version: 1\n'
    printf 'restore:\n'
    printf '  ignored_items: []\n'
  } >"$MI_CONFIG"
}

mi_ignore_update_config() {
  local action="$1"
  local ref="$2"
  local name="$3"
  local tmp
  mi_ignore_ensure_config_file || return 1
  tmp="$(mktemp "${MI_CONFIG}.tmp.XXXXXX")" || return 1
  if [ "$action" = "ignore" ]; then
    MI_IGNORE_REF="$ref" MI_IGNORE_NAME="$name" yq e '
      .version = (.version // 1) |
      .restore.ignored_items = (((.restore.ignored_items // []) | map(select(.ref != strenv(MI_IGNORE_REF)))) + [{"ref": strenv(MI_IGNORE_REF), "name": strenv(MI_IGNORE_NAME)}])
    ' "$MI_CONFIG" >"$tmp" || { rm -f "$tmp"; return 1; }
  else
    MI_IGNORE_REF="$ref" yq e '
      .restore.ignored_items = ((.restore.ignored_items // []) | map(select(.ref != strenv(MI_IGNORE_REF))))
    ' "$MI_CONFIG" >"$tmp" || { rm -f "$tmp"; return 1; }
  fi
  mv "$tmp" "$MI_CONFIG"
}

mi_ignore_apply_config_to_inventory() {
  local inventory="$1"
  local refs ref tmp stamp
  [ -f "$MI_CONFIG" ] || return 0
  mi_has yq || return 0
  refs="$(yq e -r '.restore.ignored_items[]?.ref // ""' "$MI_CONFIG" 2>/dev/null | sed '/^$/d' | sort -u || true)"
  [ -n "$refs" ] || return 0
  stamp="$(mi_timestamp)"
  while IFS= read -r ref; do
    [ -n "$ref" ] || continue
    tmp="$(mktemp "${inventory}.tmp.XXXXXX")" || return 1
    MI_IGNORE_REF="$ref" MI_IGNORE_AT="$stamp" yq e '
      (.apps.items[]? | select(.ref == strenv(MI_IGNORE_REF)) | .ignored) = true |
      (.apps.items[]? | select(.ref == strenv(MI_IGNORE_REF)) | .ignored_at) = strenv(MI_IGNORE_AT) |
      (.brew.taps[]? | select(.ref == strenv(MI_IGNORE_REF)) | .ignored) = true |
      (.brew.taps[]? | select(.ref == strenv(MI_IGNORE_REF)) | .ignored_at) = strenv(MI_IGNORE_AT) |
      (.brew.formulae[]? | select(.ref == strenv(MI_IGNORE_REF)) | .ignored) = true |
      (.brew.formulae[]? | select(.ref == strenv(MI_IGNORE_REF)) | .ignored_at) = strenv(MI_IGNORE_AT) |
      (.brew.casks[]? | select(.ref == strenv(MI_IGNORE_REF)) | .ignored) = true |
      (.brew.casks[]? | select(.ref == strenv(MI_IGNORE_REF)) | .ignored_at) = strenv(MI_IGNORE_AT) |
      (.npm.globals[]? | select(.ref == strenv(MI_IGNORE_REF)) | .ignored) = true |
      (.npm.globals[]? | select(.ref == strenv(MI_IGNORE_REF)) | .ignored_at) = strenv(MI_IGNORE_AT) |
      (.pip.packages[]? | select(.ref == strenv(MI_IGNORE_REF)) | .ignored) = true |
      (.pip.packages[]? | select(.ref == strenv(MI_IGNORE_REF)) | .ignored_at) = strenv(MI_IGNORE_AT) |
      (.pipx.packages[]? | select(.ref == strenv(MI_IGNORE_REF)) | .ignored) = true |
      (.pipx.packages[]? | select(.ref == strenv(MI_IGNORE_REF)) | .ignored_at) = strenv(MI_IGNORE_AT) |
      (.dotfiles.files[]? | select(.ref == strenv(MI_IGNORE_REF)) | .ignored) = true |
      (.dotfiles.files[]? | select(.ref == strenv(MI_IGNORE_REF)) | .ignored_at) = strenv(MI_IGNORE_AT) |
      (.github_projects.repos[]? | select(.ref == strenv(MI_IGNORE_REF)) | .ignored) = true |
      (.github_projects.repos[]? | select(.ref == strenv(MI_IGNORE_REF)) | .ignored_at) = strenv(MI_IGNORE_AT) |
      (.oh_my_zsh | select(.ref == strenv(MI_IGNORE_REF)) | .ignored) = true |
      (.oh_my_zsh | select(.ref == strenv(MI_IGNORE_REF)) | .ignored_at) = strenv(MI_IGNORE_AT) |
      (.xcode | select(.ref == strenv(MI_IGNORE_REF)) | .ignored) = true |
      (.xcode | select(.ref == strenv(MI_IGNORE_REF)) | .ignored_at) = strenv(MI_IGNORE_AT) |
      (.manual_apps.apps[]? | select(.ref == strenv(MI_IGNORE_REF)) | .ignored) = true |
      (.manual_apps.apps[]? | select(.ref == strenv(MI_IGNORE_REF)) | .ignored_at) = strenv(MI_IGNORE_AT)
    ' "$inventory" >"$tmp" || { rm -f "$tmp"; return 1; }
    mv "$tmp" "$inventory"
  done <<EOF
$refs
EOF
}

mi_ignore_regenerate_outputs() {
  case "${MI_EFFECTIVE_SOURCE:-local}" in
    github) return 0 ;;
  esac
  mi_inventory_write_backup_list "$MI_INVENTORY"
  mi_inventory_write_backup_readme "$MI_INVENTORY"
}

mi_ignore_command() {
  local action="$1"
  local token="${MI_IGNORE_TOKEN:-}"
  local matches count type path_expr ref label id
  [ -n "$token" ] || { mi_error "$action requires a ref or token"; return 2; }
  [ -f "$MI_INVENTORY" ] || { mi_error "setup snapshot not found: $MI_INVENTORY"; return 1; }
  mi_require_yq || return 1

  matches="$(mktemp "${TMPDIR:-/tmp}/mac-setup-ignore-matches.XXXXXX")" || return 1
  mi_ignore_find_matches "$MI_INVENTORY" "$token" "$matches"
  count="$(wc -l <"$matches" | tr -d ' ')"
  if [ "$count" -eq 0 ]; then
    rm -f "$matches"
    mi_error "no snapshot entry matched: $token"
    return 1
  fi
  if [ "$count" -gt 1 ]; then
    mi_error "multiple snapshot entries matched: $token"
    while IFS="|" read -r type path_expr ref label id; do
      mi_warn "match: $ref ${label:+($label)}"
    done <"$matches"
    rm -f "$matches"
    return 2
  fi

  IFS="|" read -r type path_expr ref label id <"$matches"
  rm -f "$matches"

  if [ "$MI_DRY_RUN" = "true" ]; then
    mi_info "dry-run: would $action $ref ${label:+($label)} in $MI_INVENTORY"
    mi_info "dry-run: would update ignored item rules in $MI_CONFIG"
    mi_info "dry-run: would regenerate backup-list and README when supported"
    return 0
  fi

  mi_ignore_write_inventory "$MI_INVENTORY" "$path_expr" "$ref" "$action" "$type" "$id" "$label" || return 1
  mi_ignore_update_config "$action" "$ref" "$label" || return 1
  mi_ignore_regenerate_outputs || return 1
  mi_info "$action: $ref ${label:+($label)}"
}
