#!/usr/bin/env bash
# shellcheck disable=SC2034

mi_endpoint_init_defaults() {
  MI_TARGET="${MI_TARGET:-}"
  MI_SOURCE="${MI_SOURCE:-}"
  MI_TARGET_EXPLICIT="${MI_TARGET_EXPLICIT:-false}"
  MI_SOURCE_EXPLICIT="${MI_SOURCE_EXPLICIT:-false}"
  MI_EFFECTIVE_TARGET="${MI_EFFECTIVE_TARGET:-}"
  MI_EFFECTIVE_SOURCE="${MI_EFFECTIVE_SOURCE:-}"
  MI_ICLOUD_FOLDER_NAME="${MI_ICLOUD_FOLDER_NAME:-Mac Setup Snapshot}"
  MI_ICLOUD_ROOT="${MI_ICLOUD_ROOT:-$HOME/Library/Mobile Documents/com~apple~CloudDocs}"
  MI_ENDPOINT_BUNDLE=""
}

mi_endpoint_iCloud_bundle() {
  printf '%s/%s\n' "$MI_ICLOUD_ROOT" "$MI_ICLOUD_FOLDER_NAME"
}

mi_endpoint_valid() {
  case "$1" in
    icloud|local|github) return 0 ;;
    *) return 1 ;;
  esac
}

mi_endpoint_privacy_guidance() {
  mi_warn "iCloud Drive is not readable/writable from this shell."
  mi_warn "macOS may require file access permission for Terminal, iTerm, Codex, or your shell host."
  mi_warn "Check System Settings > Privacy & Security > Files & Folders and allow iCloud Drive access."
}

mi_endpoint_choose_fallback() {
  local reason="$1"
  mi_warn "$reason"
  if [ "$MI_INTERACTIVE" != "true" ] || [ ! -t 0 ]; then
    mi_error "iCloud endpoint is unavailable; pass --target local/--source local or --target github/--source github"
    return 1
  fi
  if mi_prompt_yes_no "Use local files in the current directory instead?" "yes"; then
    printf '%s\n' "local"
    return 0
  fi
  if mi_prompt_yes_no "Use GitHub Gist instead?" "no"; then
    printf '%s\n' "github"
    return 0
  fi
  mi_error "iCloud endpoint is unavailable"
  return 1
}

mi_endpoint_preflight_icloud() {
  local mode="$1"
  local fallback endpoint bundle

  if [ ! -d "$MI_ICLOUD_ROOT" ]; then
    fallback="$(mi_endpoint_choose_fallback "iCloud Drive folder was not found at $MI_ICLOUD_ROOT")" || return 1
    printf '%s\n' "$fallback"
    return 0
  fi

  if [ ! -r "$MI_ICLOUD_ROOT" ]; then
    mi_endpoint_privacy_guidance
    fallback="$(mi_endpoint_choose_fallback "iCloud Drive is not readable at $MI_ICLOUD_ROOT")" || return 1
    printf '%s\n' "$fallback"
    return 0
  fi

  if [ "$mode" = "target" ] && [ ! -w "$MI_ICLOUD_ROOT" ]; then
    mi_endpoint_privacy_guidance
    fallback="$(mi_endpoint_choose_fallback "iCloud Drive is not writable at $MI_ICLOUD_ROOT")" || return 1
    printf '%s\n' "$fallback"
    return 0
  fi

  endpoint="icloud"
  bundle="$(mi_endpoint_iCloud_bundle)"
  if [ "$mode" = "source" ] && [ -d "$bundle" ] && [ ! -r "$bundle" ]; then
    mi_endpoint_privacy_guidance
    fallback="$(mi_endpoint_choose_fallback "iCloud bundle is not readable at $bundle")" || return 1
    printf '%s\n' "$fallback"
    return 0
  fi

  printf '%s\n' "$endpoint"
}

mi_endpoint_command_mode() {
  case "$MI_COMMAND" in
    backup) printf '%s\n' "target" ;;
    restore|list|ignore|unignore) printf '%s\n' "source" ;;
    *) printf '%s\n' "" ;;
  esac
}

mi_endpoint_effective_for_mode() {
  local mode="$1"
  case "$mode" in
    target)
      if [ "$MI_TARGET_EXPLICIT" = "true" ]; then
        printf '%s\n' "$MI_TARGET"
      elif [ "$MI_GIST_PUSH" = "true" ]; then
        printf '%s\n' "github"
      elif [ "$MI_INVENTORY_EXPLICIT" = "true" ]; then
        printf '%s\n' "local"
      else
        printf '%s\n' "${MI_TARGET:-icloud}"
      fi
      ;;
    source)
      if [ "$MI_SOURCE_EXPLICIT" = "true" ]; then
        printf '%s\n' "$MI_SOURCE"
      elif [ "$MI_GIST_PULL" = "true" ]; then
        printf '%s\n' "github"
      elif [ "$MI_INVENTORY_EXPLICIT" = "true" ]; then
        printf '%s\n' "local"
      else
        printf '%s\n' "${MI_SOURCE:-icloud}"
      fi
      ;;
  esac
}

mi_endpoint_resolve_config_path() {
  local mode endpoint bundle fallback
  mi_endpoint_init_defaults
  mode="$(mi_endpoint_command_mode)"
  [ -n "$mode" ] || return 0
  [ "$MI_CONFIG_EXPLICIT" = "true" ] && return 0
  endpoint="$(mi_endpoint_effective_for_mode "$mode")"
  [ "$endpoint" = "icloud" ] || return 0

  fallback="$(mi_endpoint_preflight_icloud "$mode")" || return 1
  endpoint="$fallback"
  if [ "$mode" = "target" ]; then
    MI_EFFECTIVE_TARGET="$endpoint"
    [ "$MI_TARGET_EXPLICIT" = "true" ] || MI_TARGET="$endpoint"
  else
    MI_EFFECTIVE_SOURCE="$endpoint"
    [ "$MI_SOURCE_EXPLICIT" = "true" ] || MI_SOURCE="$endpoint"
  fi
  [ "$endpoint" = "icloud" ] || return 0
  bundle="$(mi_endpoint_iCloud_bundle)"
  MI_CONFIG="$bundle/mac-setup.config.yml"
}

mi_endpoint_resolve() {
  local mode endpoint bundle fallback
  mi_endpoint_init_defaults
  mode="$(mi_endpoint_command_mode)"
  [ -n "$mode" ] || return 0

  endpoint="$(mi_endpoint_effective_for_mode "$mode")"
  if ! mi_endpoint_valid "$endpoint"; then
    mi_error "endpoint must be icloud, local, or github"
    return 2
  fi

  if [ "$endpoint" = "icloud" ]; then
    fallback="$(mi_endpoint_preflight_icloud "$mode")" || return 1
    endpoint="$fallback"
  fi

  case "$mode:$endpoint" in
    target:icloud)
      bundle="$(mi_endpoint_iCloud_bundle)"
      MI_ENDPOINT_BUNDLE="$bundle"
      MI_EFFECTIVE_TARGET="icloud"
      [ "$MI_INVENTORY_EXPLICIT" = "true" ] || MI_INVENTORY="$bundle/mac-setup.yml"
      [ "$MI_CONFIG_EXPLICIT" = "true" ] || MI_CONFIG="$bundle/mac-setup.config.yml"
      ;;
    source:icloud)
      bundle="$(mi_endpoint_iCloud_bundle)"
      MI_ENDPOINT_BUNDLE="$bundle"
      MI_EFFECTIVE_SOURCE="icloud"
      [ "$MI_INVENTORY_EXPLICIT" = "true" ] || MI_INVENTORY="$bundle/mac-setup.yml"
      [ "$MI_CONFIG_EXPLICIT" = "true" ] || MI_CONFIG="$bundle/mac-setup.config.yml"
      if [ ! -f "$MI_INVENTORY" ]; then
        mi_error "setup snapshot not found in iCloud endpoint: $MI_INVENTORY"
        return 1
      fi
      if [ ! -r "$MI_INVENTORY" ]; then
        mi_endpoint_privacy_guidance
        mi_error "setup snapshot is not readable: $MI_INVENTORY"
        return 1
      fi
      ;;
    target:github)
      MI_EFFECTIVE_TARGET="github"
      MI_GIST_PUSH="true"
      ;;
    source:github)
      MI_EFFECTIVE_SOURCE="github"
      MI_GIST_PULL="true"
      case "$MI_COMMAND" in
        ignore|unignore) MI_GIST_PUSH="true" ;;
      esac
      ;;
    target:local)
      MI_EFFECTIVE_TARGET="local"
      ;;
    source:local)
      MI_EFFECTIVE_SOURCE="local"
      ;;
  esac
}

mi_endpoint_history_stamp() {
  date -u '+%Y%m%dT%H%M%SZ'
}

mi_endpoint_prepare_backup() {
  local history_dir stamp moved item base
  [ "${MI_EFFECTIVE_TARGET:-}" = "icloud" ] || return 0
  [ -n "$MI_ENDPOINT_BUNDLE" ] || MI_ENDPOINT_BUNDLE="$(mi_endpoint_iCloud_bundle)"

  if [ "$MI_DRY_RUN" = "true" ]; then
    mi_info "dry-run: would use iCloud endpoint $MI_ENDPOINT_BUNDLE"
    for item in "$MI_ENDPOINT_BUNDLE/mac-setup.yml" "$MI_ENDPOINT_BUNDLE/mac-setup.config.yml" "$MI_ENDPOINT_BUNDLE/files" "$MI_ENDPOINT_BUNDLE/metadata.yml" "$MI_ENDPOINT_BUNDLE/backup-list.md" "$MI_ENDPOINT_BUNDLE/README.md"; do
      [ -e "$item" ] && mi_info "dry-run: would move existing $(basename "$item") to iCloud history"
    done
    return 0
  fi

  mkdir -p "$MI_ENDPOINT_BUNDLE" || { mi_error "could not create iCloud endpoint: $MI_ENDPOINT_BUNDLE"; return 1; }
  if [ ! -w "$MI_ENDPOINT_BUNDLE" ]; then
    mi_endpoint_privacy_guidance
    mi_error "iCloud endpoint is not writable: $MI_ENDPOINT_BUNDLE"
    return 1
  fi

  moved="false"
  stamp="$(mi_endpoint_history_stamp)"
  history_dir="$MI_ENDPOINT_BUNDLE/history/$stamp"
  for item in "$MI_ENDPOINT_BUNDLE/mac-setup.yml" "$MI_ENDPOINT_BUNDLE/mac-setup.config.yml" "$MI_ENDPOINT_BUNDLE/files" "$MI_ENDPOINT_BUNDLE/metadata.yml" "$MI_ENDPOINT_BUNDLE/backup-list.md" "$MI_ENDPOINT_BUNDLE/README.md"; do
    [ -e "$item" ] || continue
    [ "$moved" = "true" ] || { mkdir -p "$history_dir" || return 1; moved="true"; }
    base="$(basename "$item")"
    mv "$item" "$history_dir/$base" || return 1
  done
  if [ "$moved" = "true" ] && [ "$MI_CONFIG_EXPLICIT" != "true" ] && [ -f "$history_dir/mac-setup.config.yml" ]; then
    cp "$history_dir/mac-setup.config.yml" "$MI_ENDPOINT_BUNDLE/mac-setup.config.yml" || return 1
  fi
  [ "$moved" = "true" ] && mi_info "moved previous iCloud snapshot to $history_dir"
  return 0
}

mi_endpoint_write_metadata() {
  local metadata
  [ "${MI_EFFECTIVE_TARGET:-}" = "icloud" ] || return 0
  [ -n "$MI_ENDPOINT_BUNDLE" ] || MI_ENDPOINT_BUNDLE="$(mi_endpoint_iCloud_bundle)"
  metadata="$MI_ENDPOINT_BUNDLE/metadata.yml"
  if [ "$MI_DRY_RUN" = "true" ]; then
    mi_info "dry-run: would write iCloud endpoint metadata to $metadata"
    return 0
  fi
  {
    printf 'version: 1\n'
    printf 'updated_at: %s\n' "$(mi_yaml_scalar "$(mi_timestamp)")"
    printf 'endpoint: icloud\n'
    printf 'snapshot: mac-setup.yml\n'
    printf 'backup_list: backup-list.md\n'
    printf 'readme: README.md\n'
    printf 'config: mac-setup.config.yml\n'
  } >"$metadata"
}
