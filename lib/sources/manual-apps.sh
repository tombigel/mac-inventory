#!/usr/bin/env bash

manual_apps_backup() {
  printf 'manual_apps:\n'
  printf '  apps:\n'
  for dir in /Applications "$HOME/Applications"; do
    [ -d "$dir" ] || continue
    find "$dir" -maxdepth 1 -type d -name '*.app' 2>/dev/null | while IFS= read -r app; do
      name="$(basename "$app")"
      cask=""
      selected=""
      if [ "$MI_CHECK_MANUAL_BREW" = "true" ] && mi_has brew; then
        query="$(printf '%s\n' "$name" | sed 's/\.app$//' | tr '[:upper:] ' '[:lower:]-')"
        if mi_brew_capture cask_matches search --casks "$query"; then
          cask="$(printf '%s\n' "$cask_matches" | head -n 1)"
        fi
        if [ -n "$cask" ]; then
          case "$MI_MANUAL_BREW_MATCH" in
            all) selected="$cask" ;;
            ask)
              if [ "$MI_INTERACTIVE" != "true" ] && [ "$MI_YES" = "true" ]; then
                selected="$cask"
              elif [ "$MI_INTERACTIVE" = "true" ] && mi_prompt_yes_no "Use Homebrew cask $cask for $name?" "no"; then
                selected="$cask"
              fi
              ;;
          esac
        fi
      fi
      if [ -n "$selected" ]; then
        mi_verbose "manual app $name represented by brew cask $selected"
        if [ -n "${MI_MATCHED_CASKS_FILE:-}" ]; then
          printf '%s\n' "$selected" >>"$MI_MATCHED_CASKS_FILE"
        fi
        continue
      fi
      bundle_id="$(/usr/bin/mdls -name kMDItemCFBundleIdentifier -raw "$app" 2>/dev/null || true)"
      version="$(/usr/bin/mdls -name kMDItemVersion -raw "$app" 2>/dev/null || true)"
      printf '    - name: %s\n' "$(mi_yaml_scalar "$name")"
      printf '      path: %s\n' "$(mi_yaml_scalar "$app")"
      printf '      bundle_id: %s\n' "$(mi_yaml_scalar "$bundle_id")"
      printf '      version: %s\n' "$(mi_yaml_scalar "$version")"
      printf '      brew_cask_candidate: %s\n' "$(mi_yaml_scalar "$cask")"
      printf '      selected_brew_cask: %s\n' "$(mi_yaml_scalar "$selected")"
    done
  done
}

manual_apps_restore() {
  count="$(yq e '.manual_apps.apps | length' "$MI_INVENTORY" 2>/dev/null || printf '0')"
  if [ "$count" != "0" ] && [ "$count" != "null" ]; then
    mi_warn "manual apps require manual restore; run list -S manual_apps"
  fi
}
