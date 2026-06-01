#!/usr/bin/env bash

mi_validate_identifier() {
  case "$1" in
    *[!A-Za-z0-9._@+:/-]*|"")
      return 1
      ;;
    *)
      return 0
      ;;
  esac
}

mi_safe_home_path() {
  raw="$1"
  expanded="$(mi_expand_path "$raw")"
  case "$expanded" in
    "$HOME"|"$HOME"/*) ;;
    *) return 1 ;;
  esac
  case "$expanded" in
    *"/../"*|*"/.."|"../"*|"..") return 1 ;;
  esac
  if [ -L "$expanded" ]; then
    target="$(readlink "$expanded" 2>/dev/null || true)"
    case "$target" in
      /*)
        case "$target" in "$HOME"|"$HOME"/*) ;; *) return 1 ;; esac
        ;;
    esac
  fi
  printf '%s\n' "$expanded"
}

mi_mask_secret() {
  value="$1"
  if [ "${#value}" -le 8 ]; then
    printf '***'
  else
    printf '%s***%s' "$(printf '%s' "$value" | cut -c 1-4)" "$(printf '%s' "$value" | awk '{print substr($0,length($0)-3)}')"
  fi
}

mi_file_has_secret() {
  file="$1"
  [ -f "$file" ] || return 1
  grep -Eiq '(token|secret|password|passwd|api[_-]?key|access[_-]?key|private[_-]?key|BEGIN (RSA|OPENSSH|DSA|EC|PGP) PRIVATE KEY)' "$file"
}

mi_secret_scan_paths() {
  found="false"
  for path in "$@"; do
    [ -f "$path" ] || continue
    if mi_file_has_secret "$path"; then
      mi_warn "possible secret detected in $path"
      found="true"
    fi
  done
  [ "$found" != "true" ]
}

mi_backup_existing_file() {
  target="$1"
  [ -e "$target" ] || return 0
  stamp="$(date '+%Y%m%d%H%M%S')"
  backup_dir="$HOME/.mac-inventory/restore-backups/$stamp"
  if [ "$MI_DRY_RUN" = "true" ]; then
    mi_info "dry-run: would back up $target to $backup_dir/"
    return 0
  fi
  mkdir -p "$backup_dir"
  cp -p "$target" "$backup_dir/"
}

mi_require_yq() {
  if mi_has yq; then
    return 0
  fi
  mi_install_brew_tool_if_allowed yq yq && return 0
  mi_error "yq v4 is required for this command"
  return 1
}

mi_download_installer() {
  url="$1"
  output="$2"
  case "$url" in
    https://*) ;;
    *) mi_error "refusing non-HTTPS installer URL: $url"; return 1 ;;
  esac
  if [ "$MI_DRY_RUN" = "true" ]; then
    mi_info "dry-run: would download $url to $output"
    return 0
  fi
  mi_has curl || { mi_error "curl is required to download installer"; return 1; }
  curl --fail --location --silent --show-error "$url" --output "$output"
}

mi_run_downloaded_script() {
  script="$1"
  shift
  [ -f "$script" ] || { mi_error "installer script does not exist: $script"; return 1; }
  if [ "$MI_DRY_RUN" = "true" ]; then
    mi_info "dry-run: would run $script"
    return 0
  fi
  sh "$script" "$@"
}
