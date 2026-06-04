#!/usr/bin/env bash
# shellcheck disable=SC2034

MI_WORKFLOW_STEPS=""
MI_WORKFLOW_TOTAL=0
MI_WORKFLOW_INDEX=0
MI_RESUME_ACTIVE="false"

mi_resume_path() {
  if [ -n "${MI_ACTIVE_RESUME_FILE:-}" ]; then
    printf '%s\n' "$MI_ACTIVE_RESUME_FILE"
    return 0
  fi
  mi_expand_path "$MI_RESUME_FILE"
}

mi_step_line() {
  id="$1"
  status="$2"
  printf '  - id: %s\n' "$(mi_yaml_scalar "$id")"
  printf '    status: %s\n' "$(mi_yaml_scalar "$status")"
}

mi_workflow_build_steps() {
  workflow="$1"
  MI_WORKFLOW_STEPS="check_xcode_cli
install_homebrew
install_yq"
  if [ "$MI_GITHUB_PROJECTS" = "true" ]; then
    MI_WORKFLOW_STEPS="${MI_WORKFLOW_STEPS}
check_git"
  fi
  if [ "$MI_APPS" = "true" ] || [ "$MI_XCODE" = "true" ]; then
    MI_WORKFLOW_STEPS="${MI_WORKFLOW_STEPS}
install_mas"
  fi
  if [ "$MI_PIPX" = "true" ]; then
    MI_WORKFLOW_STEPS="${MI_WORKFLOW_STEPS}
install_pipx"
  fi
  if [ "$MI_GIST_PULL" = "true" ] || [ "$MI_GIST_PUSH" = "true" ]; then
    MI_WORKFLOW_STEPS="${MI_WORKFLOW_STEPS}
check_github_auth"
  fi
  if [ "$MI_APPS" = "true" ] || [ "$MI_XCODE" = "true" ]; then
    MI_WORKFLOW_STEPS="${MI_WORKFLOW_STEPS}
check_appstore_login"
  fi
  if [ "$workflow" = "restore" ]; then
    MI_WORKFLOW_STEPS="${MI_WORKFLOW_STEPS}
restore_inventory"
  fi
  MI_WORKFLOW_TOTAL="$(printf '%s\n' "$MI_WORKFLOW_STEPS" | sed '/^$/d' | wc -l | tr -d ' ')"
}

mi_resume_workflow() {
  resume="$(mi_resume_path)"
  [ -f "$resume" ] || return 1
  awk -F': ' '/^workflow:/ { gsub(/"/, "", $2); print $2; exit }' "$resume"
}

mi_resume_load_steps() {
  resume="$(mi_resume_path)"
  [ -f "$resume" ] || return 1
  MI_WORKFLOW_STEPS="$(awk '/^[[:space:]]*- id:/ { gsub(/"/, "", $3); print $3 }' "$resume")"
  MI_WORKFLOW_TOTAL="$(printf '%s\n' "$MI_WORKFLOW_STEPS" | sed '/^$/d' | wc -l | tr -d ' ')"
}

mi_resume_init() {
  workflow="$1"
  resume="$(mi_resume_path)"
  mi_mkdir_parent "$resume"
  {
    printf 'version: 1\n'
    printf 'workflow: %s\n' "$(mi_yaml_scalar "$workflow")"
    printf 'created_at: %s\n' "$(mi_yaml_scalar "$(mi_timestamp)")"
    printf 'updated_at: %s\n' "$(mi_yaml_scalar "$(mi_timestamp)")"
    printf 'inventory: %s\n' "$(mi_yaml_scalar "$MI_INVENTORY")"
    printf 'current_step: ""\n'
    printf 'steps:\n'
    printf '%s\n' "$MI_WORKFLOW_STEPS" | sed '/^$/d' | while IFS= read -r step; do
      mi_step_line "$step" "pending"
    done
  } >"$resume"
}

mi_resume_status() {
  resume="$(mi_resume_path)"
  [ -f "$resume" ] || { mi_info "No resume state found at $resume"; return 0; }
  cat "$resume"
}

mi_resume_remove() {
  resume="$(mi_resume_path)"
  [ -f "$resume" ] || return 0
  if [ "$MI_DRY_RUN" = "true" ]; then
    mi_info "dry-run: would remove resume state $resume"
    return 0
  fi
  rm -f "$resume"
}

mi_resume_reset_if_requested() {
  [ "$MI_RESET_RESUME" = "true" ] || return 0
  resume="$(mi_resume_path)"
  [ -f "$resume" ] || return 0
  if mi_prompt_yes_no "Remove existing resume state $resume?" "yes"; then
    mi_resume_remove
  else
    mi_error "resume state reset cancelled"
    return 1
  fi
}

mi_resume_existing_policy() {
  resume="$(mi_resume_path)"
  [ -f "$resume" ] || return 0
  if [ "$MI_COMMAND" = "continue" ] || [ "$MI_COMMAND" = "status" ] || [ "$MI_RESET_RESUME" = "true" ]; then
    return 0
  fi

  if [ "$MI_INTERACTIVE" != "true" ] || [ ! -t 0 ]; then
    mi_error "resume state exists at $resume; run '${MI_PROGRAM_NAME:-mac-setup} continue' or --reset-resume"
    return 1
  fi
  mi_warn "resume state exists at $resume"
  if mi_prompt_yes_no "Continue the interrupted workflow now?" "yes"; then
    MI_COMMAND="continue"
    return 0
  fi
  mi_warn "starting a fresh workflow and replacing stale resume state"
  mi_resume_remove
}

mi_resume_step_status() {
  step="$1"
  resume="$(mi_resume_path)"
  [ -f "$resume" ] || return 1
  awk -v step="$step" '
    $0 ~ "id: \"" step "\"" {found=1; next}
    found && /status:/ {
      gsub(/"/, "", $2)
      print $2
      exit
    }
  ' "$resume"
}

mi_resume_mark_step() {
  step="$1"
  status="$2"
  resume="$(mi_resume_path)"
  [ -f "$resume" ] || return 0
  tmp="$(mktemp "${resume}.tmp.XXXXXX")" || return 1
  awk -v step="$step" -v status="$status" -v now="$(mi_timestamp)" '
    /^updated_at:/ { print "updated_at: \"" now "\""; next }
    /^current_step:/ { print "current_step: \"" step "\""; next }
    $0 ~ "id: \"" step "\"" { print; found=1; next }
    found && /status:/ { print "    status: \"" status "\""; found=0; next }
    { print }
  ' "$resume" >"$tmp"
  mv "$tmp" "$resume"
}

mi_action_intro() {
  title="$1"
  why="$2"
  command_preview="${3:-}"
  prompt_note="${4:-}"
  [ "$MI_QUIET" = "true" ] && return 0
  printf '\nStep %s/%s: %s\n' "$MI_WORKFLOW_INDEX" "$MI_WORKFLOW_TOTAL" "$title"
  printf '%s\n' "$why"
  [ -n "$command_preview" ] && printf 'Command: %s\n' "$command_preview"
  [ -n "$prompt_note" ] && printf '%s\n' "$prompt_note"
  printf 'Press Ctrl-C to stop safely; resume later with: %s continue\n' "${MI_PROGRAM_NAME:-mac-setup}"
}

mi_caffeinate_enabled() {
  case "$MI_CAFFEINATE" in
    true) return 0 ;;
    false) return 1 ;;
    auto)
      [ "$MI_INTERACTIVE" = "true" ] && { [ "$MI_COMMAND" = "prepare" ] || [ "$MI_COMMAND" = "restore" ] || [ "$MI_COMMAND" = "continue" ]; }
      ;;
  esac
}

mi_caffeinate_start() {
  MI_CAFFEINATE_PID=""
  mi_caffeinate_enabled || return 0
  if [ "$MI_DRY_RUN" = "true" ]; then
    mi_info "dry-run: would use caffeinate to prevent sleep during this workflow"
    return 0
  fi
  if ! mi_has caffeinate; then
    mi_warn "caffeinate is unavailable; continuing without sleep prevention"
    return 0
  fi
  caffeinate -dimsu -w "$$" >/dev/null 2>&1 &
  MI_CAFFEINATE_PID=$!
  mi_verbose "caffeinate started with pid $MI_CAFFEINATE_PID"
}

mi_caffeinate_stop() {
  [ -n "${MI_CAFFEINATE_PID:-}" ] || return 0
  kill "$MI_CAFFEINATE_PID" 2>/dev/null || true
  wait "$MI_CAFFEINATE_PID" 2>/dev/null || true
}

mi_workflow_run() {
  workflow="$1"
  mode="${2:-full}"
  MI_ACTIVE_RESUME_FILE=""
  mi_resume_reset_if_requested || return 1
  if [ "$mode" != "continue" ]; then
    mi_workflow_build_steps "$workflow"
    mi_resume_existing_policy || return 1
    if [ "$MI_DRY_RUN" = "true" ]; then
      MI_ACTIVE_RESUME_FILE="$(mktemp "${TMPDIR:-/tmp}/mac-setup-resume-dry.XXXXXX")" || return 1
    fi
    mi_resume_init "$workflow"
  else
    [ -f "$(mi_resume_path)" ] || { mi_error "no resume state found"; return 1; }
    mi_resume_load_steps || return 1
    if [ "$MI_DRY_RUN" = "true" ]; then
      real_resume="$(mi_resume_path)"
      MI_ACTIVE_RESUME_FILE="$(mktemp "${TMPDIR:-/tmp}/mac-setup-resume-dry.XXXXXX")" || return 1
      cp "$real_resume" "$MI_ACTIVE_RESUME_FILE"
    fi
  fi

  trap 'mi_caffeinate_stop; mi_warn "workflow interrupted; resume with: ${MI_PROGRAM_NAME:-mac-setup} continue"; exit 130' INT TERM
  mi_caffeinate_start
  MI_WORKFLOW_INDEX=0
  workflow_rc=0
  while IFS= read -r step; do
    [ -n "$step" ] || continue
    MI_WORKFLOW_INDEX=$((MI_WORKFLOW_INDEX + 1))
    if [ "$mode" = "continue" ]; then
      existing="$(mi_resume_step_status "$step")"
      [ "$existing" = "done" ] || [ "$existing" = "skipped" ] && continue
    fi
    mi_resume_mark_step "$step" "running"
    if "mi_workflow_step_$step"; then
      mi_resume_mark_step "$step" "done"
    else
      rc=$?
      mi_resume_mark_step "$step" "failed"
      mi_caffeinate_stop
      trap - INT TERM
      mi_error "workflow failed at step $step; resume with: ${MI_PROGRAM_NAME:-mac-setup} continue"
      workflow_rc="$rc"
      break
    fi
  done <<EOF
$MI_WORKFLOW_STEPS
EOF
  mi_caffeinate_stop
  trap - INT TERM
  if [ "$workflow_rc" -eq 0 ]; then
    if [ "$MI_DRY_RUN" = "true" ]; then
      rm -f "$(mi_resume_path)"
    else
      mi_resume_remove
    fi
    mi_info "workflow complete"
  elif [ "$MI_DRY_RUN" = "true" ]; then
    rm -f "$(mi_resume_path)"
  fi
  return "$workflow_rc"
}

mi_workflow_continue() {
  workflow="$(mi_resume_workflow)" || { mi_error "no resume state found"; return 1; }
  mi_workflow_run "$workflow" "continue"
}

mi_workflow_step_check_xcode_cli() {
  mi_action_intro "Check Xcode Command Line Tools" "Required before many developer tools and Homebrew packages can build." "xcode-select -p" "macOS may show a GUI install prompt if tools are missing."
  if xcode-select -p >/dev/null 2>&1; then
    mi_info "xcode cli: found"
    return 0
  fi
  [ "$MI_CHECK_ONLY" = "true" ] && { mi_warn "xcode cli: missing"; return 0; }
  mi_prompt_yes_no "Install Xcode Command Line Tools now?" "yes" || return 0
  mi_run xcode-select --install
}

mi_workflow_step_install_homebrew() {
  local installer rc
  mi_action_intro "Check Homebrew" "Required to install yq, mas, pipx, and Homebrew inventory items." "/bin/bash homebrew-install.sh" "The installer may prompt for your password."
  if mi_has brew; then
    mi_info "homebrew: found"
    return 0
  fi
  [ "$MI_CHECK_ONLY" = "true" ] && { mi_warn "homebrew: missing"; return 0; }
  if [ "$MI_DRY_RUN" = "true" ]; then
    mi_info "dry-run: would install Homebrew"
    return 0
  fi
  mi_prompt_yes_no "Install Homebrew now?" "yes" || return 0
  installer="${TMPDIR:-/tmp}/mac-setup-homebrew-install.sh"
  mi_download_installer "https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh" "$installer" || return 1
  mi_run /bin/bash "$installer" || { rc=$?; rm -f "$installer"; return "$rc"; }
  rm -f "$installer"
  if [ -x /opt/homebrew/bin/brew ]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
    mi_info "homebrew: applied /opt/homebrew/bin/brew shellenv for this process"
  elif [ -x /usr/local/bin/brew ]; then
    eval "$(/usr/local/bin/brew shellenv)"
    mi_info "homebrew: applied /usr/local/bin/brew shellenv for this process"
  fi
}

mi_workflow_step_install_yq() {
  mi_action_intro "Install yq" "Required to parse YAML inventory and config files during restore." "brew install yq"
  mi_has yq && { mi_info "yq: found"; return 0; }
  [ "$MI_CHECK_ONLY" = "true" ] && { mi_warn "yq: missing"; return 0; }
  [ "$MI_DRY_RUN" = "true" ] && { mi_info "dry-run: would install yq"; return 0; }
  mi_install_brew_tool_if_allowed yq yq
}

mi_workflow_step_check_git() {
  mi_action_intro "Check Git" "Required to restore GitHub project repositories." "git --version"
  if mi_has git; then
    mi_info "git: found"
    return 0
  fi
  mi_warn "git: missing"
  return 0
}

mi_workflow_step_install_mas() {
  mi_action_intro "Install mas" "Required for Mac App Store inventory and App Store-based Xcode restore." "brew install mas" "Homebrew or macOS may prompt for administrator credentials; App Store login still requires manual sign-in."
  mi_has mas && { mi_info "mas: found"; return 0; }
  [ "$MI_CHECK_ONLY" = "true" ] && { mi_warn "mas: missing"; return 0; }
  appstore_ensure_mas "prepare"
}

mi_workflow_step_install_pipx() {
  mi_action_intro "Install pipx" "Required to restore pipx-managed CLI tools." "brew install pipx"
  mi_has pipx && { mi_info "pipx: found"; return 0; }
  [ "$MI_CHECK_ONLY" = "true" ] && { mi_warn "pipx: missing"; return 0; }
  [ "$MI_DRY_RUN" = "true" ] && { mi_info "dry-run: would install pipx"; return 0; }
  mi_install_brew_tool_if_allowed pipx pipx
}

mi_workflow_step_check_github_auth() {
  mi_action_intro "Check GitHub authentication" "Required for GitHub Gist pull or push." "gh auth status"
  mi_github_ensure_auth || { mi_warn "github: authentication unavailable"; return 0; }
}

mi_workflow_step_check_appstore_login() {
  mi_action_intro "Check App Store access" "Required for mas install/list operations." "mas list" "mas may prompt for administrator credentials or App Store authentication."
  if ! mi_has mas; then
    mi_warn "appstore: mas missing"
    mi_report_event warn apps mas_missing "mas is missing; App Store access could not be checked"
    return 0
  fi
  if [ "$MI_DRY_RUN" = "true" ]; then
    mi_info "dry-run: would run mas list to check App Store access"
    return 0
  fi
  if appstore_access_ready; then
    mi_info "appstore: mas list succeeded"
  else
    appstore_handle_missing_login "prepare"
  fi
}

mi_workflow_step_restore_inventory() {
  mi_action_intro "Restore setup snapshot" "Runs the selected additive restore steps from the setup snapshot." "${MI_PROGRAM_NAME:-mac-setup} restore --skip-prepare=true"
  if [ "$MI_PAUSE_AFTER_PREPARE" = "true" ]; then
    mi_prompt_yes_no "Prepare completed. Continue with restore now?" "yes" || return 0
  fi
  MI_SKIP_PREPARE="true"
  mi_inventory_restore_body
}
