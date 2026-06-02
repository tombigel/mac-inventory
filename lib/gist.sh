#!/usr/bin/env bash

mi_github_token_value() {
  if [ -n "$MI_GITHUB_TOKEN" ]; then
    printf '%s\n' "$MI_GITHUB_TOKEN"
    return 0
  fi
  if [ -n "$MI_GITHUB_TOKEN_ENV" ]; then
    token_value="$(printenv "$MI_GITHUB_TOKEN_ENV" 2>/dev/null || true)"
    if [ -n "${token_value:-}" ]; then
      printf '%s\n' "$token_value"
      return 0
    fi
  fi
  return 1
}

mi_github_has_gh_auth() {
  mi_has gh && gh auth status >/dev/null 2>&1
}

mi_github_ensure_auth() {
  case "$MI_GITHUB_LOGIN" in
    none)
      mi_github_token_value >/dev/null 2>&1 || mi_github_has_gh_auth
      return $?
      ;;
    token)
      mi_github_token_value >/dev/null 2>&1
      return $?
      ;;
    gh)
      if mi_github_has_gh_auth; then
        return 0
      fi
      mi_github_token_value >/dev/null 2>&1
      return $?
      ;;
    interactive)
      if mi_github_has_gh_auth || mi_github_token_value >/dev/null 2>&1; then
        return 0
      fi
      if [ "$MI_INTERACTIVE" = "true" ] && mi_has gh; then
        mi_run gh auth login
        return $?
      fi
      return 1
      ;;
  esac
}

mi_gist_pull() {
  local tmpdir rc
  [ -n "$MI_GIST_ID" ] || { mi_error "--gist-id is required for gist pull"; return 2; }

  if [ "$MI_DRY_RUN" = "true" ]; then
    mi_info "dry-run: would pull gist $MI_GIST_ID"
    return 0
  fi

  mi_github_ensure_auth || { mi_error "GitHub auth is required for gist pull"; return 1; }

  if mi_github_has_gh_auth; then
    tmpdir="$(mktemp -d)"
    gh gist clone "$MI_GIST_ID" "$tmpdir" >/dev/null || { rc=$?; rm -rf "$tmpdir"; return "$rc"; }
    mi_gist_copy_pulled_file "$tmpdir/$MI_GIST_FILE" "$MI_INVENTORY" || { rc=$?; rm -rf "$tmpdir"; return "$rc"; }
    mi_gist_copy_pulled_file "$tmpdir/$MI_GIST_CONFIG_FILE" "$MI_CONFIG" || { rc=$?; rm -rf "$tmpdir"; return "$rc"; }
    rm -rf "$tmpdir"
    return 0
  fi

  mi_error "gist pull without gh auth is not implemented; run gh auth login or use gh mode"
  return 1
}

mi_gist_copy_pulled_file() {
  source="$1"
  dest="$2"
  [ -f "$source" ] || return 0
  if [ -e "$dest" ]; then
    mi_backup_existing_file "$dest" || return 1
  fi
  mi_mkdir_parent "$dest"
  cp "$source" "$dest"
  mi_info "pulled $dest"
}

mi_gist_push() {
  if [ "$MI_DRY_RUN" = "true" ]; then
    mi_info "dry-run: would push snapshot/config to GitHub Gist"
    return 0
  fi

  mi_github_ensure_auth || { mi_error "GitHub auth is required for gist push"; return 1; }

  files_to_scan=""
  [ -f "$MI_INVENTORY" ] && files_to_scan="${files_to_scan}${files_to_scan:+
}$MI_INVENTORY"
  [ -f "$MI_CONFIG" ] && files_to_scan="${files_to_scan}${files_to_scan:+
}$MI_CONFIG"
  if [ -n "$files_to_scan" ]; then
    # shellcheck disable=SC2086
    mi_secret_scan_paths $files_to_scan || {
      mi_prompt_yes_no "Possible secrets detected. Continue with Gist upload?" "no" || return 1
    }
  fi

  if [ "$MI_GIST_VISIBILITY" = "public" ]; then
    if [ "$MI_INTERACTIVE" = "true" ]; then
      mi_prompt_yes_no "Upload snapshot/config as a public Gist?" "no" || return 1
    elif [ "$MI_YES" != "true" ]; then
      mi_error "public Gist upload in non-interactive mode requires --yes"
      return 1
    fi
  fi

  if mi_github_has_gh_auth; then
    mi_gist_push_with_gh
    return $?
  fi

  mi_gist_push_with_api
}

mi_gist_push_with_gh() {
  files=""
  [ -f "$MI_INVENTORY" ] && files="$files $MI_INVENTORY"
  [ -f "$MI_CONFIG" ] && files="$files $MI_CONFIG"
  [ -n "$files" ] || { mi_error "nothing to upload"; return 1; }

  if [ -n "$MI_GIST_ID" ]; then
    # shellcheck disable=SC2086
    gh gist edit "$MI_GIST_ID" $files
  else
    [ "$MI_GIST_CREATE" = "true" ] || { mi_error "--gist-create=true or --gist-id is required"; return 2; }
    public_flag=""
    [ "$MI_GIST_VISIBILITY" = "public" ] && public_flag="--public"
    # shellcheck disable=SC2086
    gh gist create $public_flag $files
  fi
}

mi_gist_push_with_api() {
  local tmp rc
  token="$(mi_github_token_value)" || { mi_error "GitHub token is required"; return 1; }
  mi_has python3 || { mi_error "python3 is required for token-based Gist upload fallback"; return 1; }
  mi_has curl || { mi_error "curl is required for token-based Gist upload fallback"; return 1; }

  tmp="$(mktemp)" || return 1
  if ! python3 - "$MI_INVENTORY" "$MI_CONFIG" "$MI_GIST_VISIBILITY" >"$tmp" <<'PY'
import json
import os
import sys

inventory, config, visibility = sys.argv[1:4]
files = {}
for path in (inventory, config):
    if path and os.path.exists(path):
        files[os.path.basename(path)] = {"content": open(path, encoding="utf-8").read()}
payload = {"public": visibility == "public", "files": files}
print(json.dumps(payload))
PY
  then
    rc=$?
    rm -f "$tmp"
    return "$rc"
  fi

  if [ -n "$MI_GIST_ID" ]; then
    curl --fail --silent --show-error \
      -H "Authorization: Bearer $token" \
      -H "Accept: application/vnd.github+json" \
      -X PATCH \
      "https://api.github.com/gists/$MI_GIST_ID" \
      --data @"$tmp"
  else
    [ "$MI_GIST_CREATE" = "true" ] || { rm -f "$tmp"; mi_error "--gist-create=true or --gist-id is required"; return 2; }
    curl --fail --silent --show-error \
      -H "Authorization: Bearer $token" \
      -H "Accept: application/vnd.github+json" \
      "https://api.github.com/gists" \
      --data @"$tmp"
  fi
  rc=$?
  rm -f "$tmp"
  return "$rc"
}

mi_doctor_github() {
  if mi_github_has_gh_auth; then
    mi_info "github: gh authenticated"
  elif mi_github_token_value >/dev/null 2>&1; then
    mi_info "github: token available via $(mi_mask_secret "$MI_GITHUB_TOKEN_ENV")"
  else
    mi_warn "github: not authenticated"
  fi
}
