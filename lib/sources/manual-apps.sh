#!/usr/bin/env bash

manual_apps_backup() {
  local app_index installed_casks cask_catalog app_count app_number app name bundle_id version adam_id receipt query cask cask_catalog_ready selected installed_cask search_matches
  printf 'manual_apps:\n'
  printf '  apps:\n'
  mi_app_index_ensure || return 1
  app_index="$MI_APP_INDEX_FILE"
  app_count="$(wc -l <"$app_index" | tr -d ' ')"
  installed_casks=""
  cask_catalog=""
  cask_catalog_ready="false"
  if [ "$MI_CHECK_MANUAL_BREW" = "true" ] && mi_has brew; then
    mi_brew_capture installed_casks list --cask || installed_casks=""
    mi_verbose "manual_apps: found $(printf '%s\n' "$installed_casks" | sed '/^$/d' | wc -l | tr -d ' ') installed Homebrew cask(s)"
    if mi_brew_capture cask_catalog search --casks '/.*/'; then
      cask_catalog_ready="true"
      mi_verbose "manual_apps: loaded $(printf '%s\n' "$cask_catalog" | sed '/^$/d' | wc -l | tr -d ' ') Homebrew cask catalog entr$( [ "$(printf '%s\n' "$cask_catalog" | sed '/^$/d' | wc -l | tr -d ' ')" = "1" ] && printf 'y' || printf 'ies' )"
    else
      mi_warn "manual_apps: could not load Homebrew cask catalog; using per-app cask search fallback"
    fi
  elif [ "$MI_CHECK_MANUAL_BREW" = "true" ]; then
    mi_verbose "manual_apps: Homebrew not found; cask matching disabled"
  else
    mi_verbose "manual_apps: Homebrew cask matching disabled"
  fi
  app_number=0
  while IFS="|" read -r app name bundle_id version adam_id receipt; do
    [ -n "$app" ] || continue
    app_number=$((app_number + 1))
    mi_inventory_progress_detail manual_apps "checking $app_number/$app_count $name"
    cask=""
    selected=""
    if mi_app_is_appstore_app "$adam_id" "$receipt"; then
      mi_verbose "manual app $name represented by App Store"
      continue
    fi
    if [ "$MI_CHECK_MANUAL_BREW" = "true" ] && mi_has brew; then
      query="$(printf '%s\n' "$name" | sed 's/\.app$//' | tr '[:upper:] ' '[:lower:]-')"
      installed_cask="$(manual_apps_find_cask_candidate "$query" "$installed_casks")"
      if [ -n "$installed_cask" ]; then
        mi_verbose "manual app $name represented by installed brew cask $installed_cask"
        continue
      fi
      if [ "$cask_catalog_ready" = "true" ]; then
        cask="$(manual_apps_find_cask_candidate "$query" "$cask_catalog")"
        if [ -n "$cask" ]; then
          cask="$(manual_apps_verified_cask_candidate "$name" "$cask" "catalog" || true)"
          [ -n "$cask" ] && mi_verbose "manual_apps: $name matched Homebrew cask candidate $cask"
        else
          mi_verbose "manual_apps: $name has no Homebrew cask candidate for query $query"
        fi
      fi
      if [ -z "$cask" ]; then
        search_matches=""
        if mi_brew_capture search_matches search --casks "$query"; then
          cask="$(manual_apps_find_cask_candidate "$query" "$search_matches")"
          if [ -n "$cask" ]; then
            cask="$(manual_apps_verified_cask_candidate "$name" "$cask" "search" || true)"
            [ -n "$cask" ] && mi_verbose "manual_apps: $name matched Homebrew cask candidate $cask from search"
          else
            mi_verbose "manual_apps: $name has no Homebrew cask candidate from search query $query"
          fi
        else
          mi_verbose "manual_apps: Homebrew cask search failed for $name query $query"
        fi
      fi
      if [ -n "$cask" ]; then
        case "$MI_MANUAL_BREW_MATCH" in
          all) selected="$cask" ;;
          ask)
            if [ "$MI_YES" = "true" ]; then
              selected="$cask"
            elif [ "$MI_NO" = "true" ]; then
              :
            elif [ "$MI_INTERACTIVE" = "true" ]; then
              if [ -t 0 ]; then
                if mi_prompt_yes_no "Use Homebrew cask $cask for $name?" "no"; then
                  selected="$cask"
                fi
              else
                mi_warn "manual_apps: cannot ask about Homebrew cask $cask for $name because stdin is not a TTY; recording candidate without converting"
              fi
            fi
            ;;
        esac
      elif [ "$cask_catalog_ready" = "true" ]; then
        mi_verbose "manual_apps: recording $name as manual app with no cask candidate"
      fi
    fi
    if [ -n "$selected" ]; then
      mi_verbose "manual app $name represented by brew cask $selected"
      if [ -n "${MI_MATCHED_CASKS_FILE:-}" ]; then
        printf '%s|%s|%s|%s\n' "$selected" "$name" "$app" "$version" >>"$MI_MATCHED_CASKS_FILE"
      fi
      continue
    fi
    printf '    - name: %s\n' "$(mi_yaml_scalar "$name")"
    printf '      ref: %s\n' "$(mi_yaml_scalar "$(mi_manual_app_ref "$bundle_id" "$name" "$app")")"
    printf '      path: %s\n' "$(mi_yaml_scalar "$app")"
    printf '      bundle_id: %s\n' "$(mi_yaml_scalar "$bundle_id")"
    printf '      version: %s\n' "$(mi_yaml_scalar "$version")"
    printf '      brew_cask_candidate: %s\n' "$(mi_yaml_scalar "$cask")"
    printf '      selected_brew_cask: %s\n' "$(mi_yaml_scalar "$selected")"
    mi_verbose "manual_apps: recorded $name path=$app cask_candidate=${cask:-none}"
  done <"$app_index"
}

manual_apps_cask_key() {
  mi_app_cask_key "$1"
}

manual_apps_find_cask_candidate() {
  local query="$1"
  local catalog="$2"
  local query_key
  [ -n "$query" ] || return 0
  query_key="$(manual_apps_cask_key "$query")"
  printf '%s\n' "$catalog" | awk -v query="$query" -v query_key="$query_key" '
    function key(value) {
      value = tolower(value)
      gsub(/[^a-z0-9]/, "", value)
      return value
    }
    $0 == query || key($0) == query_key {
      print
      found=1
      exit
    }
    index(key($0), query_key) == 1 && fallback == "" {
      fallback=$0
    }
    END {
      if (!found && fallback != "") {
        print fallback
      }
    }
  ' 2>/dev/null
}

manual_apps_verified_cask_candidate() {
  local name="$1"
  local cask="$2"
  local source="$3"
  local cask_info cask_status
  [ -n "$cask" ] || return 0
  if ! mi_validate_identifier "$cask"; then
    mi_verbose "manual_apps: skipped invalid Homebrew cask candidate $cask for $name from $source"
    return 0
  fi
  if mi_brew_capture cask_info info --json=v2 --cask "$cask"; then
    cask_status="$(manual_apps_cask_info_status "$cask_info")"
    case "$cask_status" in
      deprecated|disabled)
        mi_verbose "manual_apps: skipped $cask_status Homebrew cask candidate $cask for $name from $source"
        return 0
        ;;
    esac
    printf '%s\n' "$cask"
  else
    mi_verbose "manual_apps: skipped Homebrew cask candidate $cask for $name from $source because brew info --cask failed"
  fi
}

manual_apps_cask_info_status() {
  local cask_info="$1"
  local deprecated disabled
  [ -n "$cask_info" ] || { printf 'ok\n'; return 0; }
  mi_has yq || { printf 'ok\n'; return 0; }
  deprecated="$(printf '%s\n' "$cask_info" | yq e -p=json -r '(.casks[0].deprecated // false)' - 2>/dev/null || true)"
  disabled="$(printf '%s\n' "$cask_info" | yq e -p=json -r '(.casks[0].disabled // false)' - 2>/dev/null || true)"
  if [ "$disabled" = "true" ]; then
    printf 'disabled\n'
  elif [ "$deprecated" = "true" ]; then
    printf 'deprecated\n'
  else
    printf 'ok\n'
  fi
}

manual_apps_restore() {
  local rows name path candidate ref ignored rc
  rows="$(yq e -r '
    (.manual_apps.apps // [])[]? |
    (.name // "" | tostring) + "|" +
    (.path // "" | tostring) + "|" +
    ((.selected_brew_cask | select(. != null and . != "")) // (.brew_cask_candidate | select(. != null and . != "")) // "" | tostring) + "|" +
    (.ref // "" | tostring) + "|" +
    (.ignored // false | tostring)
  ' "$MI_INVENTORY" 2>/dev/null || true)"
  rc=0
  while IFS="|" read -r name path candidate ref ignored; do
    [ -n "$name" ] || continue
    if [ "$ignored" = "true" ]; then
      mi_info "manual app: ignored ${ref:-$name} ($name); skipping"
      continue
    fi
    if [ -n "$candidate" ]; then
      manual_apps_restore_cask_candidate "$name" "$candidate" || rc=$?
    else
      if [ -n "$path" ]; then
        mi_warn "manual app requires manual restore: $name ($path)"
      else
        mi_warn "manual app requires manual restore: $name"
      fi
    fi
  done <<EOF
$rows
EOF
  return "$rc"
}

manual_apps_restore_cask_candidate() {
  local name="$1"
  local candidate="$2"
  local candidate_info candidate_status
  if ! mi_validate_identifier "$candidate"; then
    mi_warn "manual app $name has invalid Homebrew cask candidate: $candidate"
    return 0
  fi
  if ! mi_has brew; then
    mi_warn "manual app $name can use Homebrew cask $candidate, but brew is missing"
    return 0
  fi
  if ! mi_brew_capture candidate_info info --json=v2 --cask "$candidate"; then
    mi_warn "manual app $name has Homebrew cask candidate $candidate, but brew info --cask could not resolve it"
    return 0
  fi
  candidate_status="$(manual_apps_cask_info_status "$candidate_info")"
  case "$candidate_status" in
    deprecated|disabled)
      mi_warn "manual app $name has $candidate_status Homebrew cask candidate $candidate"
      return 0
      ;;
  esac

  if [ "$MI_DRY_RUN" = "true" ]; then
    if [ "$MI_YES" = "true" ]; then
      mi_info "dry-run: would install Homebrew cask $candidate for manual app $name"
      mi_brew_run install --cask "$candidate"
    elif [ "$MI_NO" = "true" ]; then
      mi_info "dry-run: would skip Homebrew cask $candidate for manual app $name"
    elif [ "$MI_INTERACTIVE" = "true" ]; then
      mi_info "dry-run: would prompt to install Homebrew cask $candidate for manual app $name"
    else
      mi_info "dry-run: would report Homebrew cask candidate $candidate for manual app $name"
    fi
    return 0
  fi

  if mi_brew_capture manual_cask_check list --cask "$candidate" && [ "$MI_SKIP_EXISTING" = "true" ]; then
    mi_info "manual app cask: $candidate already installed for $name"
    return 0
  fi

  if [ "$MI_YES" = "true" ]; then
    mi_brew_run install --cask "$candidate"
    return $?
  fi
  if [ "$MI_NO" = "true" ]; then
    mi_warn "manual app $name requires manual restore; skipped Homebrew cask candidate $candidate"
    return 0
  fi
  if [ "$MI_INTERACTIVE" = "true" ] && [ -t 0 ]; then
    if mi_prompt_yes_no "Install Homebrew cask $candidate for manual app $name?" "yes"; then
      mi_brew_run install --cask "$candidate"
      return $?
    fi
    mi_warn "manual app $name requires manual restore; skipped Homebrew cask candidate $candidate"
    return 0
  fi

  mi_warn "manual app $name can be restored with Homebrew cask $candidate; rerun interactively or pass --yes to install it"
}
