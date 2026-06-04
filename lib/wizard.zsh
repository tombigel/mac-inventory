#!/usr/bin/env zsh

MI_WIZARD_DEFAULT_BACKUP_SOURCES="apps|App Store apps|true
brew|Homebrew|true
npm|npm globals|true
pip|pip packages|true
pipx|pipx packages|true
oh_my_zsh|Oh My Zsh|true
xcode|Xcode|true
dotfiles|dotfiles|true
manual_apps|manual apps|true
github_projects|GitHub projects|false"

MI_WIZARD_DEFAULT_RESTORE_SOURCES="apps|App Store apps|true
brew|Homebrew|true
npm|npm globals|true
pip|pip packages|true
pipx|pipx packages|true
oh_my_zsh|Oh My Zsh|true
xcode|Xcode|true
dotfiles|dotfiles|true
manual_apps|manual apps|true
github_projects|GitHub projects|false"

MI_WIZARD_CONFIG_READY="false"

mi_wizard_valid_flow() {
  case "$1" in
    backup|restore) return 0 ;;
    *) return 1 ;;
  esac
}

mi_wizard_valid_source() {
  case "$1" in
    apps|brew|npm|pip|pipx|oh_my_zsh|xcode|dotfiles|manual_apps|github_projects) return 0 ;;
    *) return 1 ;;
  esac
}

mi_wizard_valid_prompt() {
  local flow="$1"
  local prompt="$2"
  case "$flow:$prompt" in
    backup:dry_run|backup:storage|backup:config|backup:sources|backup:github_projects_folder|backup:manual_brew_match) return 0 ;;
    restore:dry_run|restore:preflight|restore:storage|restore:use_config|restore:sources|restore:appstore_login|restore:step_mode) return 0 ;;
    *) return 1 ;;
  esac
}

mi_wizard_source_var() {
  case "$1" in
    apps) printf 'MI_APPS' ;;
    brew) printf 'MI_BREW' ;;
    npm) printf 'MI_NPM' ;;
    pip) printf 'MI_PIP' ;;
    pipx) printf 'MI_PIPX' ;;
    oh_my_zsh) printf 'MI_OH_MY_ZSH' ;;
    xcode) printf 'MI_XCODE' ;;
    dotfiles) printf 'MI_DOTFILES' ;;
    manual_apps) printf 'MI_MANUAL_APPS' ;;
    github_projects) printf 'MI_GITHUB_PROJECTS' ;;
    *) return 1 ;;
  esac
}

mi_wizard_default_sources() {
  case "$1" in
    backup) printf '%s\n' "$MI_WIZARD_DEFAULT_BACKUP_SOURCES" ;;
    restore) printf '%s\n' "$MI_WIZARD_DEFAULT_RESTORE_SOURCES" ;;
    *) return 1 ;;
  esac
}

mi_wizard_load_config() {
  MI_WIZARD_CONFIG_READY="false"
  [ -f "$MI_WIZARD_CONFIG" ] || return 0
  if ! mi_has yq; then
    mi_warn "wizard config exists but yq is not installed; using built-in wizard defaults"
    return 0
  fi
  MI_WIZARD_CONFIG_READY="true"
  mi_wizard_warn_unsupported_config
}

mi_wizard_warn_unsupported_config() {
  local key flow prompt source
  [ "$MI_WIZARD_CONFIG_READY" = "true" ] || return 0
  yq e -r '.wizard.flows // {} | keys | .[]' "$MI_WIZARD_CONFIG" 2>/dev/null | while IFS= read -r flow; do
    [ -n "$flow" ] || continue
    if ! mi_wizard_valid_flow "$flow"; then
      mi_warn "wizard config flow $flow is unsupported; ignoring"
      continue
    fi
    yq e -r ".wizard.flows.$flow.prompts // {} | keys | .[]" "$MI_WIZARD_CONFIG" 2>/dev/null | while IFS= read -r prompt; do
      [ -n "$prompt" ] || continue
      mi_wizard_valid_prompt "$flow" "$prompt" || mi_warn "wizard config prompt $flow.$prompt is unsupported; ignoring"
    done
    yq e -r ".wizard.flows.$flow.sources[]?.id // \"\"" "$MI_WIZARD_CONFIG" 2>/dev/null | while IFS= read -r source; do
      [ -n "$source" ] || continue
      mi_wizard_valid_source "$source" || mi_warn "wizard config source $flow.$source is unsupported; ignoring"
    done
  done
  yq e -r '.wizard // {} | keys | .[]' "$MI_WIZARD_CONFIG" 2>/dev/null | while IFS= read -r key; do
    case "$key" in
      flows) ;;
      *) mi_warn "wizard config key wizard.$key is unsupported; ignoring" ;;
    esac
  done
}

mi_wizard_config_bool() {
  local key="$1"
  local fallback="$2"
  local value
  [ "$MI_WIZARD_CONFIG_READY" = "true" ] || { printf '%s\n' "$fallback"; return 0; }
  value="$(yq e -r "$key // \"\"" "$MI_WIZARD_CONFIG" 2>/dev/null || true)"
  case "$value" in
    true|false) printf '%s\n' "$value" ;;
    ''|null) printf '%s\n' "$fallback" ;;
    *) mi_warn "wizard config $key must be true or false; using $fallback"; printf '%s\n' "$fallback" ;;
  esac
}

mi_wizard_config_string() {
  local key="$1"
  local fallback="$2"
  local value
  [ "$MI_WIZARD_CONFIG_READY" = "true" ] || { printf '%s\n' "$fallback"; return 0; }
  value="$(yq e -r "$key // \"\"" "$MI_WIZARD_CONFIG" 2>/dev/null || true)"
  case "$value" in
    ''|null) printf '%s\n' "$fallback" ;;
    *) printf '%s\n' "$value" ;;
  esac
}

mi_wizard_flow_enabled() {
  [ "$(mi_wizard_config_bool ".wizard.flows.$1.enabled" true)" = "true" ]
}

mi_wizard_flow_label() {
  case "$1" in
    backup) mi_wizard_config_string ".wizard.flows.backup.label" "Create or update a setup snapshot" ;;
    restore) mi_wizard_config_string ".wizard.flows.restore.label" "Restore from a setup snapshot" ;;
  esac
}

mi_wizard_prompt_enabled() {
  mi_wizard_valid_prompt "$1" "$2" || return 1
  [ "$(mi_wizard_config_bool ".wizard.flows.$1.prompts.$2" true)" = "true" ]
}

mi_wizard_dry_run_default() {
  case "$1" in
    backup) printf 'no' ;;
    restore) printf 'yes' ;;
    *) printf 'yes' ;;
  esac
}

mi_wizard_default_endpoint() {
  local flow="$1"
  local key fallback value
  case "$flow" in
    backup) key=".wizard.flows.backup.default_target"; fallback="${MI_TARGET:-icloud}" ;;
    restore) key=".wizard.flows.restore.default_source"; fallback="${MI_SOURCE:-icloud}" ;;
    *) return 1 ;;
  esac
  value="$(mi_wizard_config_string "$key" "$fallback")"
  if mi_endpoint_valid "$value"; then
    printf '%s\n' "$value"
  else
    mi_warn "wizard config $key has unsupported endpoint $value; using $fallback"
    printf '%s\n' "$fallback"
  fi
}

mi_wizard_sources() {
  local flow="$1"
  local rows id label default
  if [ "$MI_WIZARD_CONFIG_READY" = "true" ]; then
    rows="$(yq e -r ".wizard.flows.$flow.sources[]? | ((.id // \"\") | tostring) + \"|\" + ((.label // \"\") | tostring) + \"|\" + ((.default // true) | tostring)" "$MI_WIZARD_CONFIG" 2>/dev/null || true)"
    if [ -n "$rows" ]; then
      printf '%s\n' "$rows" | while IFS="|" read -r id label default; do
        [ -n "$id" ] || continue
        if ! mi_wizard_valid_source "$id"; then
          continue
        fi
        case "$default" in
          true|false) ;;
          *) mi_warn "wizard config source $flow.$id default must be true or false; using true"; default="true" ;;
        esac
        [ -n "$label" ] || label="$(mi_section_display_name "$id")"
        printf '%s|%s|%s\n' "$id" "$label" "$default"
      done
      return 0
    fi
  fi
  mi_wizard_default_sources "$flow"
}

mi_wizard_interactive() {
  [ "${MI_INTERACTIVE:-true}" = "true" ] && [ -t 0 ] && [ -t 1 ] && [ -t 2 ]
}

mi_wizard_read() {
  local prompt="$1"
  local answer
  mi_live_finish
  printf '%s ' "$(mi_emphasize_dry_run "$prompt")" >&2
  IFS= read -r answer
  printf '%s\n' "$answer"
}

mi_wizard_read_editable_default() {
  local prompt="$1"
  local default="$2"
  local answer styled_prompt
  styled_prompt="$(mi_emphasize_dry_run "$prompt")"

  if mi_wizard_interactive && mi_has zsh; then
    if answer="$(zsh -f -c 'answer=$1; prompt=$2; vared -p "$prompt " answer >/dev/tty 2>/dev/tty || exit $?; printf "%s\n" "$answer"' _ "$default" "$prompt" </dev/tty)"; then
      printf '%s\n' "$answer"
      return 0
    fi
  fi

  if mi_wizard_interactive && help read 2>/dev/null | grep -q -- '-i'; then
    mi_live_finish
    IFS= read -e -i "$default" -r -p "$styled_prompt " answer
    printf '%s\n' "$answer"
    return 0
  fi

  answer="$(mi_wizard_read "$prompt [$default]:")"
  [ -n "$answer" ] || answer="$default"
  printf '%s\n' "$answer"
}

mi_wizard_yes_no_value() {
  local prompt="$1"
  local default="$2"
  local suffix answer
  suffix="[y/N]"
  [ "$default" = "yes" ] && suffix="[Y/n]"
  answer="$(mi_wizard_read "$prompt $suffix")"
  case "$answer" in
    y|Y|yes|YES) printf 'true' ;;
    n|N|no|NO) printf 'false' ;;
    *) [ "$default" = "yes" ] && printf 'true' || printf 'false' ;;
  esac
}

mi_wizard_choice() {
  local title="$1"
  local options="$2"
  local default_index="$3"
  local count answer label value index row
  mi_ux_line ""
  mi_ux_line "$(mi_heading "$title")"
  index=0
  printf '%s\n' "$options" | while IFS="|" read -r value label; do
    [ -n "$value" ] || continue
    index=$((index + 1))
    row="    $index. $label"
    if [ "$index" -eq "$default_index" ] 2>/dev/null; then
      printf '%s\n' "$(mi_style "1;32" "$row")" >&2
    else
      printf '%s\n' "$row" >&2
    fi
  done
  count="$(printf '%s\n' "$options" | sed '/^$/d' | wc -l | tr -d ' ')"
  while :; do
    answer="$(mi_wizard_read "Choose [$default_index]:")"
    [ -n "$answer" ] || answer="$default_index"
    case "$answer" in
      ''|*[!0-9]*) mi_warn "enter a number from 1 to $count"; continue ;;
    esac
    if [ "$answer" -ge 1 ] 2>/dev/null && [ "$answer" -le "$count" ] 2>/dev/null; then
      printf '%s\n' "$options" | sed -n "${answer}p" | cut -d'|' -f1
      return 0
    fi
    mi_warn "enter a number from 1 to $count"
  done
}

mi_wizard_parse_selection_token() {
  local token="$1"
  local count="$2"
  local start end i
  case "$token" in
    all) i=1; while [ "$i" -le "$count" ]; do printf '%s\n' "$i"; i=$((i + 1)); done; return 0 ;;
    none) return 0 ;;
    *-*)
      start="${token%-*}"
      end="${token#*-}"
      case "$start$end" in *[!0-9]*|'') return 1 ;; esac
      [ "$start" -le "$end" ] 2>/dev/null || return 1
      i="$start"
      while [ "$i" -le "$end" ]; do printf '%s\n' "$i"; i=$((i + 1)); done
      ;;
    *[!0-9]*|'') return 1 ;;
    *) printf '%s\n' "$token" ;;
  esac
}

mi_wizard_sources_prompt() {
  local flow="$1"
  local rows count defaults answer selected_indices selected id label default index var selected
  rows="$(mi_wizard_sources "$flow")"
  mi_ux_line ""
  mi_ux_line "$(mi_heading "Sources")"
  index=0
  defaults=""
  printf '%s\n' "$rows" | while IFS="|" read -r id label default; do
    [ -n "$id" ] || continue
    index=$((index + 1))
    if [ "$default" = "true" ]; then
      printf '  %s. [x] %s\n' "$index" "$label" >&2
    else
      printf '  %s. [ ] %s\n' "$index" "$label" >&2
    fi
  done
  count="$(printf '%s\n' "$rows" | sed '/^$/d' | wc -l | tr -d ' ')"
  index=0
  while IFS="|" read -r id _label default; do
    [ -n "$id" ] || continue
    index=$((index + 1))
    [ "$default" = "true" ] && defaults="${defaults}${defaults:+ }$index"
  done <<EOF
$rows
EOF

  while :; do
    answer="$(mi_wizard_read "Select sources (comma/range/all/none) [default]:")"
    selected_indices=""
    if [ -z "$answer" ]; then
      selected_indices="$defaults"
    else
      answer="$(printf '%s\n' "$answer" | tr ',' ' ')"
      for selected in ${(s: :)answer}; do
        if ! mi_wizard_parse_selection_token "$selected" "$count" >/dev/null; then
          mi_warn "invalid source selection: $selected"
          selected_indices=""
          break
        fi
        selected_indices="${selected_indices}${selected_indices:+ }$(mi_wizard_parse_selection_token "$selected" "$count" | tr '\n' ' ')"
      done
      [ -n "$selected_indices" ] || [ "$answer" = "none" ] || continue
    fi
    break
  done

  while IFS="|" read -r id _label _default; do
    [ -n "$id" ] || continue
    var="$(mi_wizard_source_var "$id")" || continue
    printf -v "$var" '%s' "false"
  done <<EOF
$rows
EOF

  for selected in ${(s: :)selected_indices}; do
    id="$(printf '%s\n' "$rows" | sed -n "${selected}p" | cut -d'|' -f1)"
    var="$(mi_wizard_source_var "$id")" || continue
    printf -v "$var" '%s' "true"
  done
}

mi_wizard_endpoint_prompt() {
  local flow="$1"
  local default endpoint options default_index
  default="$(mi_wizard_default_endpoint "$flow")"
  case "$default" in
    icloud) default_index=1 ;;
    local) default_index=2 ;;
    github) default_index=3 ;;
    *) default_index=1 ;;
  esac
  options="icloud|iCloud Drive
local|Local files
github|GitHub Gist"
  endpoint="$(mi_wizard_choice "Storage" "$options" "$default_index")"
  case "$flow" in
    backup) MI_TARGET="$endpoint"; MI_TARGET_EXPLICIT="true" ;;
    restore) MI_SOURCE="$endpoint"; MI_SOURCE_EXPLICIT="true" ;;
  esac
}

mi_wizard_backup_options() {
  local choice options
  mi_wizard_prompt_enabled backup manual_brew_match || return 0
  options="ask|Ask before converting manual app candidates to Homebrew casks
never|Record candidates but keep apps manual
all|Accept all Homebrew cask candidates"
  choice="$(mi_wizard_choice "Manual App Matching" "$options" 3)"
  MI_MANUAL_BREW_MATCH="$choice"
  MI_MANUAL_BREW_MATCH_EXPLICIT="true"
  MI_CHECK_MANUAL_BREW="true"
  MI_CHECK_MANUAL_BREW_EXPLICIT="true"
}

mi_wizard_default_github_projects_root() {
  printf '%s/Projects\n' "$HOME"
}

mi_wizard_validate_absolute_path() {
  local candidate_path="$1"
  [ -n "$candidate_path" ] || return 1
  case "$candidate_path" in
    /*) ;;
    *) return 1 ;;
  esac
  case "$candidate_path" in
    *"/../"*|*"/.."|"../"*|"..") return 1 ;;
  esac
}

mi_wizard_github_projects_folder_prompt() {
  local answer default
  mi_wizard_prompt_enabled backup github_projects_folder || return 0
  [ "$MI_GITHUB_PROJECTS" = "true" ] || return 0
  default="$(mi_wizard_default_github_projects_root)"
  mi_ux_line ""
  mi_ux_line "$(mi_heading "GitHub Projects")"
  while :; do
    answer="$(mi_wizard_read_editable_default "GitHub projects folder absolute path:" "$default")"
    if mi_wizard_validate_absolute_path "$answer"; then
      MI_GITHUB_PROJECTS_ROOT_ITEMS=("$answer")
      MI_GITHUB_PROJECTS_ROOTS="$answer"
      return 0
    fi
    mi_warn "enter an absolute folder path"
  done
}

mi_wizard_restore_options() {
  local choice options default_index
  mi_wizard_prompt_enabled restore appstore_login || return 0
  case "$MI_APPSTORE_LOGIN" in
    skip) default_index=1 ;;
    prompt) default_index=2 ;;
    pause) default_index=3 ;;
    require) default_index=4 ;;
    *) default_index=2 ;;
  esac
  options="skip|Skip App Store work if access is unavailable
prompt|Prompt to open App Store when sign-in is needed
pause|Pause for manual App Store sign-in before continuing
require|Fail unless App Store access is ready"
  choice="$(mi_wizard_choice "App Store Login" "$options" "$default_index")"
  MI_APPSTORE_LOGIN="$choice"
}

mi_wizard_restore_missing_requirements() {
  xcode-select -p >/dev/null 2>&1 || printf '%s\n' "Xcode Command Line Tools"
  mi_has brew || printf '%s\n' "Homebrew"
  mi_yq_is_v4 || printf '%s\n' "yq v4"
}

mi_wizard_restore_preflight_prompt() {
  local missing choice options
  mi_wizard_prompt_enabled restore preflight || return 0
  missing="$(mi_wizard_restore_missing_requirements)"
  mi_ux_line ""
  mi_ux_line "$(mi_heading "Requirements")"
  if [ -z "$missing" ]; then
    mi_ux_line "$(mi_success_text "Required restore tools look ready.")"
    return 0
  fi
  mi_ux_line "$(mi_muted "Missing or unavailable:")"
  printf '%s\n' "$missing" | while IFS= read -r item; do
    [ -n "$item" ] && printf '  - %s\n' "$item" >&2
  done
  options="run|Run prepare preflight before restore
skip|Skip prepare preflight
abort|Abort wizard"
  choice="$(mi_wizard_choice "Preflight" "$options" 1)"
  case "$choice" in
    run) MI_SKIP_PREPARE="false" ;;
    skip) MI_SKIP_PREPARE="true" ;;
    abort)
      mi_error "restore wizard aborted"
      return 1
      ;;
  esac
}

mi_wizard_restore_step_mode_prompt() {
  local choice options
  mi_wizard_prompt_enabled restore step_mode || return 0
  options="auto|Run selected restore steps automatically
pause|Prompt before each restore step"
  choice="$(mi_wizard_choice "Restore Steps" "$options" 1)"
  MI_RESTORE_STEP_MODE="$choice"
}

mi_wizard_backup_config_path() {
  case "${MI_TARGET:-local}" in
    icloud) printf '%s/mac-setup.config.yml\n' "$(mi_endpoint_iCloud_bundle)" ;;
    *) printf '%s/mac-setup.config.yml\n' "$(dirname -- "$MI_INVENTORY")" ;;
  esac
}

mi_wizard_backup_config_new_path() {
  local config_path="$1"
  local dir stamp
  dir="$(dirname -- "$config_path")"
  stamp="$(date -u '+%Y%m%dT%H%M%SZ' 2>/dev/null || printf 'new')"
  printf '%s/mac-setup.config.%s.yml\n' "$dir" "$stamp"
}

mi_wizard_restore_config_path() {
  case "${MI_SOURCE:-local}" in
    icloud) printf '%s/mac-setup.config.yml\n' "$(mi_endpoint_iCloud_bundle)" ;;
    *) printf '%s\n' "$MI_CONFIG" ;;
  esac
}

mi_wizard_use_config() {
  local flow="$1"
  local config_path answer
  mi_wizard_prompt_enabled "$flow" use_config || return 0
  case "$flow" in
    backup) config_path="$(mi_wizard_backup_config_path)" ;;
    restore) config_path="$(mi_wizard_restore_config_path)" ;;
    *) return 0 ;;
  esac

  mi_ux_line ""
  mi_ux_line "$(mi_heading "Config")"
  if [ ! -f "$config_path" ]; then
    mi_ux_line "$(mi_muted "No config found at $config_path")"
    return 0
  fi

  answer="$(mi_wizard_yes_no_value "Use config $config_path?" "yes")"
  if [ "$answer" != "true" ]; then
    MI_CONFIG=""
    MI_CONFIG_EXPLICIT="true"
    return 0
  fi
  MI_CONFIG="$config_path"
  MI_CONFIG_EXPLICIT="true"
  mi_config_apply
}

mi_wizard_generate_config_file() {
  local output="$1"
  local overwrite="${2:-false}"
  local saved_output saved_yes rc
  saved_output="$MI_OUTPUT"
  saved_yes="$MI_YES"
  MI_OUTPUT="$output"
  [ "$overwrite" = "true" ] && MI_YES="true"
  mi_config_generate
  rc=$?
  MI_OUTPUT="$saved_output"
  MI_YES="$saved_yes"
  return "$rc"
}

mi_wizard_generate_configs() {
  local config_path new_config_path choice options
  mi_wizard_prompt_enabled backup config || return 0
  config_path="$(mi_wizard_backup_config_path)"

  if [ ! -f "$config_path" ]; then
    mi_ux_line ""
    mi_ux_line "$(mi_heading "Config")"
    mi_ux_line "$(mi_muted "No config found at $config_path; generating one.")"
    mi_wizard_generate_config_file "$config_path" "false" || return $?
    MI_CONFIG="$config_path"
    MI_CONFIG_EXPLICIT="true"
    mi_has yq && mi_config_apply
    return 0
  fi

  new_config_path="$(mi_wizard_backup_config_new_path "$config_path")"
  options="existing|Use existing config
overwrite|Overwrite existing config
new|Create timestamped config file"
  choice="$(mi_wizard_choice "Config" "$options" 1)"
  case "$choice" in
    new)
      mi_wizard_generate_config_file "$new_config_path" "false" || return $?
      MI_CONFIG="$new_config_path"
      MI_CONFIG_EXPLICIT="true"
      ;;
    overwrite)
      mi_wizard_generate_config_file "$config_path" "true" || return $?
      MI_CONFIG="$config_path"
      MI_CONFIG_EXPLICIT="true"
      ;;
    existing)
      MI_CONFIG="$config_path"
      MI_CONFIG_EXPLICIT="true"
      ;;
  esac
  mi_has yq && mi_config_apply
}

mi_wizard_args_for_sources() {
  local root
  printf '%s\n' "--apps=$MI_APPS"
  printf '%s\n' "--brew=$MI_BREW"
  printf '%s\n' "--npm=$MI_NPM"
  printf '%s\n' "--pip=$MI_PIP"
  printf '%s\n' "--pipx=$MI_PIPX"
  printf '%s\n' "--oh-my-zsh=$MI_OH_MY_ZSH"
  printf '%s\n' "--xcode=$MI_XCODE"
  printf '%s\n' "--dotfiles=$MI_DOTFILES"
  printf '%s\n' "--manual-apps=$MI_MANUAL_APPS"
  printf '%s\n' "--github-projects=$MI_GITHUB_PROJECTS"
  if (( ${+MI_GITHUB_PROJECTS_ROOT_ITEMS} && ${#MI_GITHUB_PROJECTS_ROOT_ITEMS[@]} > 0 )); then
    for root in "${MI_GITHUB_PROJECTS_ROOT_ITEMS[@]}"; do
      [ -n "$root" ] && printf '%s\n' "--github-projects-root" "$root"
    done
  elif [ -n "$MI_GITHUB_PROJECTS_ROOTS" ]; then
    while IFS= read -r root; do
      [ -n "$root" ] && printf '%s\n' "--github-projects-root" "$root"
    done <<EOF
$MI_GITHUB_PROJECTS_ROOTS
EOF
  fi
}

mi_wizard_dispatch() {
  local flow="$1"
  local args=()
  while IFS= read -r arg; do
    [ -n "$arg" ] && args+=("$arg")
  done <<EOF
$(mi_wizard_args_for_flow "$flow")
EOF
  mi_ux_line ""
  mi_ux_line "$(mi_muted "Running: ${MI_PROGRAM_NAME:-mac-setup} ${args[*]}")"
  if [ -r /dev/tty ]; then
    "$MI_SCRIPT_PATH" "${args[@]}" </dev/tty
  else
    "$MI_SCRIPT_PATH" "${args[@]}"
  fi
}

mi_wizard_args_for_flow() {
  local flow="$1"
  printf '%s\n' "$flow"
  [ "$MI_DRY_RUN" = "true" ] && printf '%s\n' "--dry-run"
  case "$flow" in
    backup)
      printf '%s\n' "--target" "$MI_TARGET"
      printf '%s\n' "--check-manual-brew" "$MI_CHECK_MANUAL_BREW"
      printf '%s\n' "--manual-brew-match" "$MI_MANUAL_BREW_MATCH"
      ;;
    restore)
      printf '%s\n' "--source" "$MI_SOURCE"
      printf '%s\n' "--skip-prepare" "$MI_SKIP_PREPARE"
      printf '%s\n' "--appstore-login" "$MI_APPSTORE_LOGIN"
      printf '%s\n' "--restore-step-mode" "$MI_RESTORE_STEP_MODE"
      ;;
  esac
  [ "$MI_CONFIG_EXPLICIT" = "true" ] && printf '%s\n' "--config" "$MI_CONFIG"
  mi_wizard_args_for_sources
}

mi_wizard_run() {
  local forced_flow="${1:-}"
  local flow options dry_run
  if ! mi_wizard_interactive; then
    mi_error "wizard requires an interactive terminal; use backup or restore directly for non-interactive runs"
    return 2
  fi

  mi_wizard_load_config
  options=""
  if [ -n "$forced_flow" ]; then
    mi_wizard_valid_flow "$forced_flow" || { mi_error "unknown wizard workflow: $forced_flow"; return 2; }
    mi_wizard_flow_enabled "$forced_flow" || { mi_error "wizard config disables $forced_flow flow"; return 2; }
    flow="$forced_flow"
  else
    if mi_wizard_flow_enabled backup; then
      options="${options}backup|$(mi_wizard_flow_label backup)"
    fi
    if mi_wizard_flow_enabled restore; then
      options="${options}${options:+
}restore|$(mi_wizard_flow_label restore)"
    fi
    [ -n "$options" ] || { mi_error "wizard config disables all flows"; return 2; }
  fi

  mi_ux_line ""
  mi_ux_line "$(mi_heading "Mac Setup Snapshot Wizard")"
  if [ -z "$forced_flow" ]; then
    flow="$(mi_wizard_choice "Workflow" "$options" 1)"
  else
    mi_ux_line "$(mi_muted "Workflow: $(mi_wizard_flow_label "$flow")")"
  fi

  if mi_wizard_prompt_enabled "$flow" dry_run; then
    dry_run="$(mi_wizard_yes_no_value "Preview only with --dry-run?" "$(mi_wizard_dry_run_default "$flow")")"
    [ "$dry_run" = "true" ] && MI_DRY_RUN="true" || MI_DRY_RUN="false"
  fi

  case "$flow" in
    backup)
      MI_TARGET="$(mi_wizard_default_endpoint backup)"
      MI_TARGET_EXPLICIT="true"
      ;;
    restore)
      MI_SOURCE="$(mi_wizard_default_endpoint restore)"
      MI_SOURCE_EXPLICIT="true"
      ;;
  esac
  if [ "$flow" = "restore" ]; then
    mi_wizard_restore_preflight_prompt || return $?
  fi
  mi_wizard_prompt_enabled "$flow" storage && mi_wizard_endpoint_prompt "$flow"
  case "$flow" in
    backup)
      mi_wizard_generate_configs || return $?
      ;;
    restore)
      mi_wizard_use_config restore || return $?
      ;;
  esac
  mi_wizard_prompt_enabled "$flow" sources && mi_wizard_sources_prompt "$flow"
  [ "$flow" = "backup" ] && mi_wizard_github_projects_folder_prompt
  case "$flow" in
    backup) mi_wizard_backup_options ;;
    restore)
      mi_wizard_restore_options
      mi_wizard_restore_step_mode_prompt
      ;;
  esac
  mi_wizard_dispatch "$flow"
}
