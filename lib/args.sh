#!/usr/bin/env bash

mi_args_init() {
  MI_COMMAND=""
  MI_SUBCOMMAND=""
  MI_HELP="false"
  MI_CONFIG="mac-inventory.config.yml"
  MI_INVENTORY="mac-inventory.yml"
  MI_SKIP_PREPARE="false"
  MI_PREPARE_ONLY="false"
  MI_PAUSE_AFTER_PREPARE="false"
  MI_CAFFEINATE="auto"
  MI_RESUME_FILE="~/.mac-inventory/resume.yml"
  MI_RESET_RESUME="false"
  MI_CHECK_ONLY="false"
  MI_OUTPUT=""
  MI_APPS="true"
  MI_BREW="true"
  MI_NPM="true"
  MI_PIP="true"
  MI_PIPX="true"
  MI_OH_MY_ZSH="true"
  MI_XCODE="true"
  MI_DOTFILES="true"
  MI_MANUAL_APPS="true"
  MI_INTERACTIVE="true"
  MI_YES="false"
  MI_NO="false"
  MI_DRY_RUN="false"
  MI_VERBOSE="false"
  MI_QUIET="false"
  MI_UPDATE="false"
  MI_CHECK_MANUAL_BREW="false"
  MI_MANUAL_BREW_MATCH="ask"
  MI_RECORD_VERSIONS="true"
  MI_SKIP_EXISTING="true"
  MI_OVERWRITE="false"
  MI_USE_VERSIONS="false"
  MI_INSTALL_MISSING_TOOLS="true"
  MI_LOGIN_CHECK="true"
  MI_APPSTORE_LOGIN="prompt"
  MI_FORMAT="table"
  MI_INSTALLED_ONLY="false"
  MI_MISSING_ONLY="false"
  MI_GIST_ID=""
  MI_GIST_CREATE="false"
  MI_GIST_VISIBILITY="secret"
  MI_GIST_FILE="mac-inventory.yml"
  MI_GIST_CONFIG_FILE="mac-inventory.config.yml"
  MI_GIST_PULL="false"
  MI_GIST_PUSH="false"
  MI_GITHUB_LOGIN="gh"
  MI_GITHUB_TOKEN=""
  MI_GITHUB_TOKEN_ENV="GITHUB_TOKEN"
  MI_COMMAND_TIMEOUT="30"
  MI_REPORT=""
  MI_REPORT_FORMAT="text"
  MI_SKIP_REPORT="false"
  MI_SECTIONS=""
  MI_DOTFILES_PATHS=""
}

mi_parse_args() {
  while [ "$#" -gt 0 ]; do
    arg="$1"
    shift
    case "$arg" in
      --)
        break
        ;;
      --*=*)
        name="${arg%%=*}"
        value="${arg#*=}"
        mi_set_long_option "$name" "$value" || return 2
        ;;
      --*)
        if mi_long_option_needs_value "$arg"; then
          [ "$#" -gt 0 ] || { mi_error "$arg requires a value"; return 2; }
          value="$1"
          shift
          mi_set_long_option "$arg" "$value" || return 2
        else
          mi_set_long_option "$arg" "" || return 2
        fi
        ;;
      -?*)
        mi_parse_short_option "$arg" "$@" || return 2
        consumed="${MI_SHORT_CONSUMED:-0}"
        while [ "$consumed" -gt 0 ]; do
          shift
          consumed=$((consumed - 1))
        done
        ;;
      *)
        mi_set_command_token "$arg" || return 2
        ;;
    esac
  done

  if [ -z "$MI_COMMAND" ]; then
    MI_HELP="true"
  fi
}

mi_set_command_token() {
  token="$1"
  if [ -z "$MI_COMMAND" ]; then
    MI_COMMAND="$token"
    return 0
  fi
  if { [ "$MI_COMMAND" = "config" ] || [ "$MI_COMMAND" = "gist" ]; } && [ -z "$MI_SUBCOMMAND" ]; then
    MI_SUBCOMMAND="$token"
    return 0
  fi
  mi_error "unexpected positional argument: $token"
  return 2
}

mi_long_option_needs_value() {
  case "$1" in
    --config|--inventory|--skip-prepare|--pause-after-prepare|--caffeinate|--resume-file|--check-only|--apps|--brew|--npm|--pip|--pipx|--oh-my-zsh|--xcode|--dotfiles|--manual-apps|--interactive|--check-manual-brew|--manual-brew-match|--versions|--dotfiles-path|--output|--skip-existing|--overwrite|--use-versions|--install-missing-tools|--login-check|--appstore-login|--section|--format|--gist-id|--gist-create|--gist-visibility|--gist-file|--gist-config-file|--github-login|--github-token|--github-token-env|--command-timeout|--report|--report-format)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

mi_set_bool_var() {
  var="$1"
  value="$2"
  normalized="$(mi_bool "$value")" || { mi_error "$var expects true or false"; return 2; }
  printf -v "$var" '%s' "$normalized"
}

mi_set_long_option() {
  name="$1"
  value="$2"
  case "$name" in
    --config) MI_CONFIG="$value" ;;
    --inventory) MI_INVENTORY="$value" ;;
    --skip-prepare) mi_set_bool_var MI_SKIP_PREPARE "$value" || return 2 ;;
    --prepare-only) MI_PREPARE_ONLY="true" ;;
    --pause-after-prepare) mi_set_bool_var MI_PAUSE_AFTER_PREPARE "$value" || return 2 ;;
    --caffeinate)
      if [ "$value" = "auto" ]; then
        MI_CAFFEINATE="auto"
      else
        mi_set_bool_var MI_CAFFEINATE "$value" || return 2
      fi
      ;;
    --resume-file) MI_RESUME_FILE="$value" ;;
    --reset-resume) MI_RESET_RESUME="true" ;;
    --check-only) mi_set_bool_var MI_CHECK_ONLY "$value" || return 2 ;;
    --apps) mi_set_bool_var MI_APPS "$value" || return 2 ;;
    --brew) mi_set_bool_var MI_BREW "$value" || return 2 ;;
    --npm) mi_set_bool_var MI_NPM "$value" || return 2 ;;
    --pip) mi_set_bool_var MI_PIP "$value" || return 2 ;;
    --pipx) mi_set_bool_var MI_PIPX "$value" || return 2 ;;
    --oh-my-zsh) mi_set_bool_var MI_OH_MY_ZSH "$value" || return 2 ;;
    --xcode) mi_set_bool_var MI_XCODE "$value" || return 2 ;;
    --dotfiles) mi_set_bool_var MI_DOTFILES "$value" || return 2 ;;
    --manual-apps) mi_set_bool_var MI_MANUAL_APPS "$value" || return 2 ;;
    --interactive) mi_set_bool_var MI_INTERACTIVE "$value" || return 2 ;;
    --yes) MI_YES="true" ;;
    --no) MI_NO="true" ;;
    --dry-run) MI_DRY_RUN="true" ;;
    --verbose) MI_VERBOSE="true" ;;
    --quiet) MI_QUIET="true" ;;
    --help) MI_HELP="true" ;;
    --update) MI_UPDATE="true" ;;
    --check-manual-brew) mi_set_bool_var MI_CHECK_MANUAL_BREW "$value" || return 2 ;;
    --manual-brew-match)
      case "$value" in ask|never|all) MI_MANUAL_BREW_MATCH="$value" ;; *) mi_error "--manual-brew-match expects ask, never, or all"; return 2 ;; esac
      ;;
    --versions) mi_set_bool_var MI_RECORD_VERSIONS "$value" || return 2 ;;
    --dotfiles-path) MI_DOTFILES_PATHS="${MI_DOTFILES_PATHS}${MI_DOTFILES_PATHS:+
}$value" ;;
    --output) MI_OUTPUT="$value"; MI_INVENTORY="$value" ;;
    --skip-existing) mi_set_bool_var MI_SKIP_EXISTING "$value" || return 2 ;;
    --overwrite) mi_set_bool_var MI_OVERWRITE "$value" || return 2 ;;
    --use-versions) mi_set_bool_var MI_USE_VERSIONS "$value" || return 2 ;;
    --install-missing-tools) mi_set_bool_var MI_INSTALL_MISSING_TOOLS "$value" || return 2 ;;
    --login-check) mi_set_bool_var MI_LOGIN_CHECK "$value" || return 2 ;;
    --appstore-login)
      case "$value" in skip|prompt|pause|require) MI_APPSTORE_LOGIN="$value" ;; *) mi_error "--appstore-login expects skip, prompt, pause, or require"; return 2 ;; esac
      ;;
    --section) MI_SECTIONS="${MI_SECTIONS}${MI_SECTIONS:+
}$value" ;;
    --format)
      case "$value" in table|yaml|json) MI_FORMAT="$value" ;; *) mi_error "--format expects table, yaml, or json"; return 2 ;; esac
      ;;
    --installed-only) MI_INSTALLED_ONLY="true" ;;
    --missing-only) MI_MISSING_ONLY="true" ;;
    --gist-id) MI_GIST_ID="$value" ;;
    --gist-create) mi_set_bool_var MI_GIST_CREATE "$value" || return 2 ;;
    --gist-visibility)
      case "$value" in secret|public) MI_GIST_VISIBILITY="$value" ;; *) mi_error "--gist-visibility expects secret or public"; return 2 ;; esac
      ;;
    --gist-file) MI_GIST_FILE="$value" ;;
    --gist-config-file) MI_GIST_CONFIG_FILE="$value" ;;
    --gist-pull) MI_GIST_PULL="true" ;;
    --gist-push) MI_GIST_PUSH="true" ;;
    --github-login)
      case "$value" in interactive|gh|token|none) MI_GITHUB_LOGIN="$value" ;; *) mi_error "--github-login expects interactive, gh, token, or none"; return 2 ;; esac
      ;;
    --github-token) MI_GITHUB_TOKEN="$value" ;;
    --github-token-env) MI_GITHUB_TOKEN_ENV="$value" ;;
    --command-timeout)
      case "$value" in
        ''|*[!0-9]*) mi_error "--command-timeout expects seconds"; return 2 ;;
        *) MI_COMMAND_TIMEOUT="$value" ;;
      esac
      ;;
    --report) MI_REPORT="$value" ;;
    --report-format)
      case "$value" in text|md|yaml|json) MI_REPORT_FORMAT="$value" ;; *) mi_error "--report-format expects text, md, yaml, or json"; return 2 ;; esac
      ;;
    --skip-report) MI_SKIP_REPORT="true" ;;
    *) mi_error "unknown option: $name"; return 2 ;;
  esac
}

mi_short_option_needs_value() {
  case "$1" in
    c|i|A|B|N|P|Q|O|X|D|M|I|C|V|F|o|s|w|U|T|L|a|S|f|g|t|r|j)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

mi_short_to_long() {
  case "$1" in
    c) printf '%s' --config ;;
    i) printf '%s' --inventory ;;
    A) printf '%s' --apps ;;
    B) printf '%s' --brew ;;
    N) printf '%s' --npm ;;
    P) printf '%s' --pip ;;
    Q) printf '%s' --pipx ;;
    O) printf '%s' --oh-my-zsh ;;
    X) printf '%s' --xcode ;;
    D) printf '%s' --dotfiles ;;
    M) printf '%s' --manual-apps ;;
    I) printf '%s' --interactive ;;
    y) printf '%s' --yes ;;
    n) printf '%s' --no ;;
    d) printf '%s' --dry-run ;;
    v) printf '%s' --verbose ;;
    q) printf '%s' --quiet ;;
    h) printf '%s' --help ;;
    u) printf '%s' --update ;;
    C) printf '%s' --check-manual-brew ;;
    V) printf '%s' --versions ;;
    F) printf '%s' --dotfiles-path ;;
    o) printf '%s' --output ;;
    s) printf '%s' --skip-existing ;;
    w) printf '%s' --overwrite ;;
    U) printf '%s' --use-versions ;;
    T) printf '%s' --install-missing-tools ;;
    L) printf '%s' --login-check ;;
    a) printf '%s' --appstore-login ;;
    S) printf '%s' --section ;;
    f) printf '%s' --format ;;
    e) printf '%s' --installed-only ;;
    m) printf '%s' --missing-only ;;
    g) printf '%s' --gist-id ;;
    t) printf '%s' --command-timeout ;;
    r) printf '%s' --report ;;
    j) printf '%s' --report-format ;;
    R) printf '%s' --skip-report ;;
    *) return 1 ;;
  esac
}

mi_parse_short_option() {
  token="${1#-}"
  shift
  MI_SHORT_CONSUMED=0

  if printf '%s' "$token" | grep -q '='; then
    letter="${token%%=*}"
    value="${token#*=}"
    [ "${#letter}" -eq 1 ] || { mi_error "invalid short option assignment: -$token"; return 2; }
    long="$(mi_short_to_long "$letter")" || { mi_error "unknown option: -$letter"; return 2; }
    mi_short_option_needs_value "$letter" || { mi_error "-$letter does not take a value"; return 2; }
    mi_set_long_option "$long" "$value"
    return $?
  fi

  i=1
  len=${#token}
  while [ "$i" -le "$len" ]; do
    letter="$(printf '%s' "$token" | cut -c "$i")"
    long="$(mi_short_to_long "$letter")" || { mi_error "unknown option: -$letter"; return 2; }
    if mi_short_option_needs_value "$letter"; then
      if [ "$i" -ne "$len" ]; then
        mi_error "value option -$letter must be standalone or last in a chain"
        return 2
      fi
      [ "$#" -gt 0 ] || { mi_error "-$letter requires a value"; return 2; }
      mi_set_long_option "$long" "$1" || return 2
      MI_SHORT_CONSUMED=1
    else
      mi_set_long_option "$long" "" || return 2
    fi
    i=$((i + 1))
  done
}
