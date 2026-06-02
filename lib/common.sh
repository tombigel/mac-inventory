#!/usr/bin/env bash

MI_VERSION="0.5.0"

mi_info() {
  if [ "${MI_QUIET:-false}" != "true" ]; then
    printf '%s\n' "$*"
  fi
}

mi_verbose() {
  if [ "${MI_VERBOSE:-false}" = "true" ]; then
    printf '%s\n' "$*" >&2
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
  local prompt="$1"
  local default="${2:-no}"
  local suffix answer

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
  read -r answer
  case "$answer" in
    y|Y|yes|YES) return 0 ;;
    n|N|no|NO) return 1 ;;
    *) [ "$default" = "yes" ] ;;
  esac
}

mi_expand_path() {
  case "$1" in
    \~) printf '%s\n' "$HOME" ;;
    \~/*) printf '%s/%s\n' "$HOME" "${1#\~/}" ;;
    *) printf '%s\n' "$1" ;;
  esac
}

mi_timestamp() {
  date -u '+%Y-%m-%dT%H:%M:%SZ'
}

mi_mkdir_parent() {
  local dir
  dir="$(dirname -- "$1")"
  [ -d "$dir" ] || mkdir -p "$dir"
}

mi_cleanup_temp_files() {
  [ -n "${MI_REPORT_EVENTS_FILE:-}" ] && rm -f -- "$MI_REPORT_EVENTS_FILE"
  [ -n "${MI_MATCHED_CASKS_FILE:-}" ] && rm -f -- "$MI_MATCHED_CASKS_FILE"
  [ -n "${MI_APP_INDEX_FILE:-}" ] && rm -f -- "$MI_APP_INDEX_FILE"
  [ -n "${MI_ACTIVE_RESUME_FILE:-}" ] && rm -f -- "$MI_ACTIVE_RESUME_FILE"
  MI_REPORT_EVENTS_FILE=""
  MI_MATCHED_CASKS_FILE=""
  MI_APP_INDEX_FILE=""
  MI_ACTIVE_RESUME_FILE=""
}

mi_cleanup_inventory_temp_files() {
  [ -n "${MI_MATCHED_CASKS_FILE:-}" ] && rm -f -- "$MI_MATCHED_CASKS_FILE"
  [ -n "${MI_APP_INDEX_FILE:-}" ] && rm -f -- "$MI_APP_INDEX_FILE"
  MI_MATCHED_CASKS_FILE=""
  MI_APP_INDEX_FILE=""
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
  mi_command_run "$*:" "$@"
}

mi_install_brew_tool_if_allowed() {
  local tool="$1"
  local formula="${2:-$1}"
  mi_has "$tool" && return 0
  [ "${MI_INSTALL_MISSING_TOOLS:-true}" = "true" ] || return 1
  mi_has brew || return 1
  mi_prompt_yes_no "Install missing tool $tool with Homebrew?" "yes" || return 1
  mi_brew_run install "$formula" || return 1
  mi_has "$tool"
}

mi_command_timeout() {
  printf '%s\n' "${MI_COMMAND_TIMEOUT:-30}"
}

mi_command_run() {
  local label="$1"
  local out err rc
  shift
  out="$(mktemp "${TMPDIR:-/tmp}/mac-setup-command-out.XXXXXX")" || return 1
  err="$(mktemp "${TMPDIR:-/tmp}/mac-setup-command-err.XXXXXX")" || { rm -f "$out"; return 1; }
  mi_verbose "$label starting"
  mi_command_capture_files "$label" "$out" "$err" "$@"
  rc=$?
  mi_verbose "$label exited with status $rc"
  cat "$out"
  cat "$err" >&2
  rm -f "$out" "$err"
  return "$rc"
}

mi_command_capture() {
  local __var="$1"
  local label="$2"
  local out err rc value detail
  shift 2
  out="$(mktemp "${TMPDIR:-/tmp}/mac-setup-command-out.XXXXXX")" || return 1
  err="$(mktemp "${TMPDIR:-/tmp}/mac-setup-command-err.XXXXXX")" || { rm -f "$out"; return 1; }
  mi_verbose "$label: starting"
  mi_command_capture_files "$label" "$out" "$err" "$@"
  rc=$?
  if [ "$rc" -eq 0 ]; then
    value="$(cat "$out")"
    printf -v "$__var" '%s' "$value"
    mi_verbose "$label: captured $(wc -l <"$out" | tr -d ' ') line(s)"
  else
    detail="$(tr '\n' ' ' <"$err" | sed 's/[[:space:]][[:space:]]*/ /g')"
    mi_verbose "$label: failed with status $rc"
    [ -n "$detail" ] && mi_verbose "$label failed: $detail"
  fi
  rm -f "$out" "$err"
  return "$rc"
}

mi_command_capture_files() {
  local label="$1"
  local out="$2"
  local err="$3"
  local timeout_seconds cmd_pid watchdog_pid rc
  shift 3
  timeout_seconds="$(mi_command_timeout)"

  if [ "$timeout_seconds" -le 0 ] 2>/dev/null; then
    "$@" >"$out" 2>"$err"
    return $?
  fi

  if mi_has perl; then
    perl -e '
      my $timeout = shift @ARGV;
      my $pid = fork();
      die "fork failed\n" unless defined $pid;
      if ($pid == 0) { exec @ARGV; die "exec failed: $!\n"; }
      local $SIG{ALRM} = sub {
        kill "TERM", $pid;
        sleep 1;
        kill "KILL", $pid;
        exit 124;
      };
      alarm $timeout;
      waitpid($pid, 0);
      my $status = $?;
      alarm 0;
      exit($status & 127 ? 128 + ($status & 127) : $status >> 8);
    ' "$timeout_seconds" "$@" >"$out" 2>"$err"
    rc=$?
    case "$rc" in
      124)
        mi_warn "$label timed out after ${timeout_seconds}s"
        return 124
        ;;
      *)
        return "$rc"
        ;;
    esac
  fi

  "$@" >"$out" 2>"$err" &
  cmd_pid=$!
  (
    sleep "$timeout_seconds"
    kill -TERM "$cmd_pid" 2>/dev/null || exit 0
    sleep 1
    kill -KILL "$cmd_pid" 2>/dev/null || true
  ) &
  watchdog_pid=$!

  wait "$cmd_pid"
  rc=$?
  kill "$watchdog_pid" 2>/dev/null || true
  wait "$watchdog_pid" 2>/dev/null || true

  case "$rc" in
    137|143)
      mi_warn "$label timed out after ${timeout_seconds}s"
      return 124
      ;;
    *)
      return "$rc"
      ;;
  esac
}

mi_brew_capture() {
  local __var="$1"
  shift
  mi_command_capture "$__var" "brew $*" \
    env HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_ANALYTICS=1 HOMEBREW_NO_INSTALL_CLEANUP=1 HOMEBREW_NO_ENV_HINTS=1 brew "$@"
}

mi_brew_run() {
  mi_run env HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_ANALYTICS=1 HOMEBREW_NO_INSTALL_CLEANUP=1 HOMEBREW_NO_ENV_HINTS=1 brew "$@"
}

mi_mas_capture() {
  local __var="$1"
  shift
  mi_command_capture "$__var" "mas $*" mas "$@"
}

mi_npm_capture() {
  local __var="$1"
  shift
  mi_command_capture "$__var" "npm $*" npm "$@"
}

mi_yaml_scalar() {
  local value="$1"
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
  cat <<EOF
${MI_PROGRAM_NAME:-mac-setup} $MI_VERSION

Usage:
  ${MI_PROGRAM_NAME:-mac-setup} <command> [options]

Commands:
  backup             Create or update a setup snapshot
  restore            Restore from a setup snapshot
  list               List snapshot sections
  doctor             Check local readiness
  prepare            Install/check prerequisites before restore
  continue           Resume an interrupted workflow
  status             Show current resume checklist
  config generate    Generate starter config
  gist pull          Pull snapshot/config from GitHub Gist
  gist push          Push snapshot/config to GitHub Gist
  help               Show this help

Global options:
  -c, --config <path>                 Config path
  -i, --inventory <path>              Setup snapshot path
      --target icloud|local|github    Backup endpoint
      --source icloud|local|github    Restore endpoint
      --icloud-folder <name>           iCloud Drive endpoint folder
      --icloud-root <path>             iCloud Drive root path
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
  -t, --command-timeout <seconds>      Timeout for external commands
  -r, --report <path>                  Write an end-of-process report
  -j, --report-format text|md|yaml|json Report file format
  -R, --skip-report                    Suppress final process report
      --skip-prepare true|false        Skip restore prepare preflight
      --prepare-only                   Stop after prepare
      --pause-after-prepare true|false Pause after prepare completes
      --caffeinate true|false          Prevent sleep for long workflows
      --resume-file <path>             Resume checklist path
      --reset-resume                   Remove stale resume state
      --check-only true|false          Check without installing

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
  -a, --appstore-login skip|prompt|pause|require
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
  -f, --format table|yaml|json|md
  -e, --installed-only
  -m, --missing-only

Short no-argument flags can be chained, e.g. -dyq.
Value-taking short options must be standalone or last in a chain.
EOF
}
