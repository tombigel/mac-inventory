#!/usr/bin/env zsh

dotfiles_default_paths() {
  if (( ${+MI_DOTFILES_PATH_ITEMS} && ${#MI_DOTFILES_PATH_ITEMS[@]} > 0 )); then
    mi_print_lines "${MI_DOTFILES_PATH_ITEMS[@]}"
  elif [ -n "$MI_DOTFILES_PATHS" ]; then
    printf '%s\n' "$MI_DOTFILES_PATHS"
  else
    printf '%s\n' \
      "~/.zshrc" \
      "~/.zprofile" \
      "~/.zshenv" \
      "~/.bashrc" \
      "~/.bash_profile" \
      "~/.profile" \
      "~/.gitconfig" \
      "~/.gitignore_global" \
      "~/.editorconfig" \
      "~/.hushlogin" \
      "~/.inputrc" \
      "~/.vimrc" \
      "~/.ideavimrc" \
      "~/.tmux.conf" \
      "~/.screenrc" \
      "~/.asdfrc" \
      "~/.tool-versions" \
      "~/.default-npm-packages" \
      "~/.ripgreprc" \
      "~/.config/git/config" \
      "~/.config/starship.toml" \
      "~/.config/bat/config" \
      "~/.config/direnv/direnvrc" \
      "~/.config/atuin/config.toml" \
      "~/.config/zellij/config.kdl" \
      "~/.config/ghostty/config" \
      "~/.config/wezterm/wezterm.lua" \
      "~/.config/alacritty/alacritty.toml" \
      "~/.config/kitty/kitty.conf" \
      "~/.config/fish/config.fish" \
      "~/.config/nvim/init.lua" \
      "~/.config/nvim/init.vim" \
      "~/.config/helix/config.toml" \
      "~/.config/lazygit/config.yml" \
      "~/.ssh/config"
  fi
}

dotfiles_backup() {
  local base_dir raw safe_path rel backup_path sha
  printf 'dotfiles:\n'
  printf '  files:\n'
  base_dir="$(dirname "$MI_INVENTORY")/files"
  dotfiles_default_paths | while IFS= read -r raw; do
    [ -n "$raw" ] || continue
    if ! safe_path="$(mi_safe_home_path "$raw")"; then
      mi_warn "dotfiles: unsafe path skipped: $raw"
      continue
    fi
    rel="${safe_path#"$HOME"/}"
    backup_path="files/$rel"
    if [ ! -f "$safe_path" ]; then
      mi_verbose "dotfiles: skipped missing $raw"
      continue
    fi
    mi_file_has_secret "$safe_path" && mi_warn "dotfiles: possible secret in $raw"
    if [ "$MI_DRY_RUN" != "true" ]; then
      mkdir -p "$(dirname "$base_dir/$rel")"
      cp -p "$safe_path" "$base_dir/$rel"
    fi
    sha="$(mi_sha256 "$safe_path")"
    printf '    - path: %s\n' "$(mi_yaml_scalar "$raw")"
    printf '      ref: %s\n' "$(mi_yaml_scalar "$(mi_dotfile_ref "$raw")")"
    printf '      exists: true\n'
    printf '      sha256: %s\n' "$(mi_yaml_scalar "$sha")"
    printf '      backup_path: %s\n' "$(mi_yaml_scalar "$backup_path")"
  done
}

dotfiles_restore() {
  local rows raw ref ignored safe_path rel source_path
  rows="$(yq e -r '
    (.dotfiles.files // [])[]? |
    (.path // "" | tostring) + "|" + (.ref // "" | tostring) + "|" + (.ignored // false | tostring)
  ' "$MI_INVENTORY" 2>/dev/null || true)"
  printf '%s\n' "$rows" | while IFS="|" read -r raw ref ignored; do
    [ -n "$raw" ] && [ "$raw" != "null" ] || continue
    if [ "$ignored" = "true" ]; then
      mi_info "dotfiles: ignored ${ref:-$raw}; skipping"
      continue
    fi
    safe_path="$(mi_safe_home_path "$raw")" || { mi_warn "dotfiles: unsafe restore path skipped: $raw"; continue; }
    rel="${safe_path#"$HOME"/}"
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
