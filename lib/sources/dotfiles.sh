#!/usr/bin/env bash

dotfiles_default_paths() {
  if [ -n "$MI_DOTFILES_PATHS" ]; then
    printf '%s\n' "$MI_DOTFILES_PATHS"
  else
    printf '%s\n' "~/.zshrc" "~/.gitconfig" "~/.gitignore_global" "~/.ssh/config"
  fi
}

dotfiles_backup() {
  printf 'dotfiles:\n'
  printf '  files:\n'
  base_dir="$(dirname "$MI_INVENTORY")/files"
  dotfiles_default_paths | while IFS= read -r raw; do
    [ -n "$raw" ] || continue
    if ! safe_path="$(mi_safe_home_path "$raw")"; then
      mi_warn "dotfiles: unsafe path skipped: $raw"
      continue
    fi
    rel="${safe_path#$HOME/}"
    backup_path="files/$rel"
    if [ -f "$safe_path" ]; then
      mi_file_has_secret "$safe_path" && mi_warn "dotfiles: possible secret in $raw"
      if [ "$MI_DRY_RUN" != "true" ]; then
        mkdir -p "$(dirname "$base_dir/$rel")"
        cp -p "$safe_path" "$base_dir/$rel"
      fi
      exists="true"
      sha="$(mi_sha256 "$safe_path")"
    else
      exists="false"
      sha=""
    fi
    printf '    - path: %s\n' "$(mi_yaml_scalar "$raw")"
    printf '      exists: %s\n' "$exists"
    printf '      sha256: %s\n' "$(mi_yaml_scalar "$sha")"
    printf '      backup_path: %s\n' "$(mi_yaml_scalar "$backup_path")"
  done
}

dotfiles_restore() {
  yq e '.dotfiles.files[]?.path' "$MI_INVENTORY" 2>/dev/null | while IFS= read -r raw; do
    [ -n "$raw" ] && [ "$raw" != "null" ] || continue
    safe_path="$(mi_safe_home_path "$raw")" || { mi_warn "dotfiles: unsafe restore path skipped: $raw"; continue; }
    rel="${safe_path#$HOME/}"
    source_path="$(dirname "$MI_INVENTORY")/files/$rel"
    [ -f "$source_path" ] || { mi_warn "dotfiles: backup missing for $raw"; continue; }
    if [ -e "$safe_path" ] && [ "$MI_OVERWRITE" != "true" ]; then
      mi_info "dotfiles: $raw exists; skipping"
      continue
    fi
    if [ -e "$safe_path" ]; then
      mi_backup_existing_file "$safe_path" || continue
    fi
    if [ "$MI_DRY_RUN" = "true" ]; then
      mi_info "dry-run: would restore $raw"
      continue
    fi
    mkdir -p "$(dirname "$safe_path")"
    cp -p "$source_path" "$safe_path"
    mi_info "dotfiles: restored $raw"
  done
}

