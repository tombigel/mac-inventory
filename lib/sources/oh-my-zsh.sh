#!/usr/bin/env bash

oh_my_zsh_path() {
  if [ -n "${ZSH:-}" ]; then
    printf '%s\n' "$ZSH"
  else
    printf '%s\n' "$HOME/.oh-my-zsh"
  fi
}

oh_my_zsh_backup() {
  zsh_dir="$(oh_my_zsh_path)"
  zshrc="$HOME/.zshrc"
  printf 'oh_my_zsh:\n'
  if [ -d "$zsh_dir" ]; then
    printf '  installed: true\n'
  else
    printf '  installed: false\n'
  fi
  printf '  path: %s\n' "$(mi_yaml_scalar "$zsh_dir")"
  if [ -f "$zshrc" ]; then
    theme="$(sed -n 's/^ZSH_THEME=["'\'']*\([^"'\'']*\)["'\'']*$/\1/p' "$zshrc" | head -n 1)"
    plugins="$(sed -n 's/^plugins=(\(.*\)).*/\1/p' "$zshrc" | head -n 1)"
    printf '  theme: %s\n' "$(mi_yaml_scalar "$theme")"
    printf '  plugins: %s\n' "$(mi_yaml_scalar "$plugins")"
    printf '  zshrc: %s\n' "$(mi_yaml_scalar "~/.zshrc")"
  else
    printf '  theme: ""\n'
    printf '  plugins: ""\n'
    printf '  zshrc: ""\n'
  fi
}

oh_my_zsh_restore() {
  zsh_dir="$(oh_my_zsh_path)"
  if [ -d "$zsh_dir" ] && [ "$MI_SKIP_EXISTING" = "true" ]; then
    mi_info "oh-my-zsh: already installed"
    return 0
  fi
  if [ "$MI_OVERWRITE" != "true" ] && [ -d "$zsh_dir" ]; then
    mi_warn "oh-my-zsh: exists; use --overwrite=true to reinstall"
    return 0
  fi
  tmp="${TMPDIR:-/tmp}/oh-my-zsh-install.$$"
  url="https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh"
  mi_download_installer "$url" "$tmp" || return 1
  if [ "$MI_DRY_RUN" = "true" ]; then
    mi_info "dry-run: RUNZSH=no CHSH=no KEEP_ZSHRC=yes sh $tmp"
    return 0
  fi
  RUNZSH=no CHSH=no KEEP_ZSHRC=yes sh "$tmp"
  rc=$?
  rm -f "$tmp"
  return "$rc"
}

oh_my_zsh_doctor() {
  if [ -d "$(oh_my_zsh_path)" ]; then
    mi_info "oh-my-zsh: installed"
  else
    mi_warn "oh-my-zsh: missing"
  fi
}

