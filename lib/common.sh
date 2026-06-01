#!/usr/bin/env bash

MI_VERSION="0.1.0"

mi_info() {
  if [ "${MI_QUIET:-false}" != "true" ]; then
    printf '%s\n' "$*"
  fi
}

mi_verbose() {
  if [ "${MI_VERBOSE:-false}" = "true" ]; then
    printf '%s\n' "$*"
  fi
}

mi_warn() {
  printf 'warning: %s\n' "$*" >&2
}

mi_error() {
  printf 'error: %s\n' "$*" >&2
}

mi_has() {
  command -v "$1" >/dev/null 2>&1
}

mi_bool() {
  case "$1" in
    true|TRUE|yes|YES|1|on|ON) printf 'true' ;;
    false|FALSE|no|NO|0|off|OFF) printf 'false' ;;
    *) return 1 ;;
  esac
}

mi_prompt_yes_no() {
  prompt="$1"
  default="${2:-no}"

  if [ "${MI_YES:-false}" = "true" ]; then
    return 0
  fi
  if [ "${MI_NO:-false}" = "true" ]; then
    return 1
  fi
  if [ "${MI_INTERACTIVE:-true}" != "true" ] || [ ! -t 0 ]; then
    [ "$default" = "yes" ]
    return $?
  fi

  suffix="[y/N]"
  if [ "$default" = "yes" ]; then
    suffix="[Y/n]"
  fi
  printf '%s %s ' "$prompt" "$suffix" >&2
  read answer
  case "$answer" in
    y|Y|yes|YES) return 0 ;;
    n|N|no|NO) return 1 ;;
    *) [ "$default" = "yes" ] ;;
  esac
}

mi_expand_path() {
  case "$1" in
    "~") printf '%s\n' "$HOME" ;;
    "~/"*) printf '%s/%s\n' "$HOME" "${1#~/}" ;;
    *) printf '%s\n' "$1" ;;
  esac
}

mi_timestamp() {
  date -u '+%Y-%m-%dT%H:%M:%SZ'
}

mi_mkdir_parent() {
  dir="$(dirname -- "$1")"
  [ -d "$dir" ] || mkdir -p "$dir"
}

mi_run() {
  if [ "${MI_DRY_RUN:-false}" = "true" ]; then
    printf 'dry-run:'
    for arg in "$@"; do
      printf ' %s' "$arg"
    done
    printf '\n'
    return 0
  fi
  mi_verbose "run: $*"
  "$@"
}

mi_yaml_scalar() {
  value="$1"
  value=${value//\\/\\\\}
  value=${value//\"/\\\"}
  printf '"%s"' "$value"
}

mi_sha256() {
  if mi_has shasum; then
    shasum -a 256 "$1" | awk '{print $1}'
  elif mi_has sha256sum; then
    sha256sum "$1" | awk '{print $1}'
  else
    printf ''
  fi
}

mi_is_enabled() {
  [ "${1:-true}" = "true" ]
}

mi_show_help() {
  cat <<'EOF'
mac-inventory 0.1.0

Usage:
  mac-inventory <command> [options]

Commands:
  backup             Create or update an inventory
  restore            Restore from an inventory
  list               List inventory sections
  doctor             Check local readiness
  config generate    Generate starter config
  gist pull          Pull inventory/config from GitHub Gist
  gist push          Push inventory/config to GitHub Gist
  help               Show this help

Global options:
  -c, --config <path>                 Config path
  -i, --inventory <path>              Inventory path
  -A, --apps true|false               Include Mac App Store apps
  -B, --brew true|false               Include Homebrew
  -N, --npm true|false                Include npm globals
  -P, --pip true|false                Include pip packages
  -Q, --pipx true|false               Include pipx packages
  -O, --oh-my-zsh true|false          Include Oh My Zsh
  -X, --xcode true|false              Include Xcode/CLT
  -D, --dotfiles true|false           Include dotfiles
  -M, --manual-apps true|false        Include manual apps
  -I, --interactive true|false        Prompt for choices
  -y, --yes                           Accept safe prompts
  -n, --no                            Reject optional prompts
  -d, --dry-run                       Print actions without side effects
  -v, --verbose                       Verbose output
  -q, --quiet                         Quiet output
  -h, --help                          Show help

Backup options:
  -u, --update
  -C, --check-manual-brew true|false
      --manual-brew-match ask|never|all
  -V, --versions true|false
  -F, --dotfiles-path <path>
  -o, --output <path>

Restore options:
  -s, --skip-existing true|false
  -w, --overwrite true|false
  -U, --use-versions true|false
  -T, --install-missing-tools true|false
  -L, --login-check true|false
  -S, --section <name>

Gist options:
  -g, --gist-id <id>
      --gist-create true|false
      --gist-visibility secret|public
      --gist-file <name>
      --gist-config-file <name>
      --gist-pull
      --gist-push
      --github-login interactive|gh|token|none
      --github-token <token>
      --github-token-env <name>

List options:
  -S, --section <name>
  -f, --format table|yaml|json
  -e, --installed-only
  -m, --missing-only

Short no-argument flags can be chained, e.g. -dyq.
Value-taking short options must be standalone or last in a chain.
EOF
}

