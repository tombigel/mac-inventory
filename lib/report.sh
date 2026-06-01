#!/usr/bin/env bash

MI_REPORT_EVENTS_FILE=""
MI_REPORT_STARTED_AT=""
MI_REPORT_STARTED_EPOCH=""

mi_report_should_emit() {
  [ "${MI_SKIP_REPORT:-false}" = "true" ] && return 1
  [ -n "${MI_REPORT:-}" ] && return 0
  case "${MI_COMMAND:-}" in
    backup|restore|prepare|continue|gist) return 0 ;;
    *) return 1 ;;
  esac
}

mi_report_start() {
  mi_report_should_emit || return 0
  MI_REPORT_STARTED_AT="$(mi_timestamp)"
  MI_REPORT_STARTED_EPOCH="$(date '+%s' 2>/dev/null || printf '0')"
  MI_REPORT_EVENTS_FILE="$(mktemp "${TMPDIR:-/tmp}/mac-inventory-report.XXXXXX")" || {
    mi_warn "report: could not create temporary report event file"
    MI_REPORT_EVENTS_FILE=""
    return 0
  }
}

mi_report_event() {
  [ -n "${MI_REPORT_EVENTS_FILE:-}" ] || return 0
  local severity="$1"
  local section="$2"
  local code="$3"
  local message="$4"
  printf '%s\t%s\t%s\t%s\n' "$severity" "$section" "$code" "$message" >>"$MI_REPORT_EVENTS_FILE"
}

mi_report_duration_seconds() {
  local now
  now="$(date '+%s' 2>/dev/null || printf '0')"
  if [ "${MI_REPORT_STARTED_EPOCH:-0}" -gt 0 ] 2>/dev/null && [ "$now" -ge "$MI_REPORT_STARTED_EPOCH" ] 2>/dev/null; then
    printf '%s\n' "$((now - MI_REPORT_STARTED_EPOCH))"
  else
    printf 'unknown\n'
  fi
}

mi_report_inventory_count() {
  local expr="$1"
  [ -f "$MI_INVENTORY" ] || { printf 'unknown'; return 0; }
  mi_has yq || { printf 'unknown'; return 0; }
  yq e "$expr" "$MI_INVENTORY" 2>/dev/null || printf 'unknown'
}

mi_report_counts_line() {
  local apps formulae casks npm pip pipx manual dotfiles
  if [ "$MI_COMMAND" = "backup" ] && [ "$MI_DRY_RUN" = "true" ]; then
    printf 'not_written_during_dry_run\n'
    return 0
  fi
  apps="$(mi_report_inventory_count '([.apps[]? | select((type == "!!map") and has("id"))] + [(.apps | select(type == "!!map") | .items[]?) | select((type == "!!map") and has("id"))]) | length')"
  formulae="$(mi_report_inventory_count '.brew.formulae // [] | length')"
  casks="$(mi_report_inventory_count '.brew.casks // [] | length')"
  npm="$(mi_report_inventory_count '.npm.globals // [] | length')"
  pip="$(mi_report_inventory_count '.pip.packages // [] | length')"
  pipx="$(mi_report_inventory_count '.pipx.packages // [] | length')"
  manual="$(mi_report_inventory_count '.manual_apps.apps // [] | length')"
  dotfiles="$(mi_report_inventory_count '.dotfiles.files // [] | length')"
  printf 'apps=%s brew_formulae=%s brew_casks=%s npm=%s pip=%s pipx=%s manual_apps=%s dotfiles=%s\n' \
    "$apps" "$formulae" "$casks" "$npm" "$pip" "$pipx" "$manual" "$dotfiles"
}

mi_report_events_text() {
  local severity section code message
  [ -n "${MI_REPORT_EVENTS_FILE:-}" ] && [ -s "$MI_REPORT_EVENTS_FILE" ] || {
    printf '  warnings: none\n'
    return 0
  }
  printf '  warnings/actions:\n'
  while IFS="$(printf '\t')" read -r severity section code message; do
    printf '    - [%s] %s/%s: %s\n' "$severity" "$section" "$code" "$message"
  done <"$MI_REPORT_EVENTS_FILE"
}

mi_report_render_text() {
  local rc="$1"
  local status="ok"
  local duration
  [ "$rc" -eq 0 ] || status="failed"
  duration="$(mi_report_duration_seconds)"
  printf 'Process report\n'
  printf '  command: %s%s\n' "$MI_COMMAND" "${MI_SUBCOMMAND:+ $MI_SUBCOMMAND}"
  printf '  status: %s\n' "$status"
  printf '  dry_run: %s\n' "$MI_DRY_RUN"
  printf '  inventory: %s\n' "$MI_INVENTORY"
  printf '  duration_seconds: %s\n' "$duration"
  printf '  counts: %s\n' "$(mi_report_counts_line)"
  mi_report_events_text
}

mi_report_render_md() {
  local rc="$1"
  local status="ok"
  local severity section code message
  [ "$rc" -eq 0 ] || status="failed"
  printf '# mac-inventory Process Report\n\n'
  printf '%s `%s`\n' "- Command:" "${MI_COMMAND}${MI_SUBCOMMAND:+ $MI_SUBCOMMAND}"
  printf '%s `%s`\n' "- Status:" "$status"
  printf '%s `%s`\n' "- Dry run:" "$MI_DRY_RUN"
  printf '%s `%s`\n' "- Inventory:" "$MI_INVENTORY"
  printf '%s `%s`\n' "- Started:" "$MI_REPORT_STARTED_AT"
  printf '%s `%s`\n' "- Finished:" "$(mi_timestamp)"
  printf '%s `%s`\n' "- Duration seconds:" "$(mi_report_duration_seconds)"
  printf '%s `%s`\n\n' "- Counts:" "$(mi_report_counts_line)"
  printf '## Warnings And Actions\n\n'
  if [ -n "${MI_REPORT_EVENTS_FILE:-}" ] && [ -s "$MI_REPORT_EVENTS_FILE" ]; then
    while IFS="$(printf '\t')" read -r severity section code message; do
      printf '%s `%s` `%s/%s`: %s\n' "-" "$severity" "$section" "$code" "$message"
    done <"$MI_REPORT_EVENTS_FILE"
  else
    printf 'None.\n'
  fi
}

mi_report_json_escape() {
  local value="$1"
  value=${value//\\/\\\\}
  value=${value//\"/\\\"}
  value=${value//$'\n'/\\n}
  printf '%s' "$value"
}

mi_report_render_yaml() {
  local rc="$1"
  local status="ok"
  local severity section code message
  [ "$rc" -eq 0 ] || status="failed"
  printf 'command: %s\n' "$(mi_yaml_scalar "${MI_COMMAND}${MI_SUBCOMMAND:+ $MI_SUBCOMMAND}")"
  printf 'status: %s\n' "$(mi_yaml_scalar "$status")"
  printf 'dry_run: %s\n' "$(mi_yaml_scalar "$MI_DRY_RUN")"
  printf 'inventory: %s\n' "$(mi_yaml_scalar "$MI_INVENTORY")"
  printf 'started_at: %s\n' "$(mi_yaml_scalar "$MI_REPORT_STARTED_AT")"
  printf 'finished_at: %s\n' "$(mi_yaml_scalar "$(mi_timestamp)")"
  printf 'duration_seconds: %s\n' "$(mi_yaml_scalar "$(mi_report_duration_seconds)")"
  printf 'counts: %s\n' "$(mi_yaml_scalar "$(mi_report_counts_line)")"
  printf 'events:\n'
  if [ -n "${MI_REPORT_EVENTS_FILE:-}" ] && [ -s "$MI_REPORT_EVENTS_FILE" ]; then
    while IFS="$(printf '\t')" read -r severity section code message; do
      printf '  - severity: %s\n' "$(mi_yaml_scalar "$severity")"
      printf '    section: %s\n' "$(mi_yaml_scalar "$section")"
      printf '    code: %s\n' "$(mi_yaml_scalar "$code")"
      printf '    message: %s\n' "$(mi_yaml_scalar "$message")"
    done <"$MI_REPORT_EVENTS_FILE"
  fi
}

mi_report_render_json() {
  local rc="$1"
  local status="ok"
  local first severity section code message
  [ "$rc" -eq 0 ] || status="failed"
  printf '{\n'
  printf '  "command": "%s",\n' "$(mi_report_json_escape "${MI_COMMAND}${MI_SUBCOMMAND:+ $MI_SUBCOMMAND}")"
  printf '  "status": "%s",\n' "$status"
  printf '  "dry_run": "%s",\n' "$MI_DRY_RUN"
  printf '  "inventory": "%s",\n' "$(mi_report_json_escape "$MI_INVENTORY")"
  printf '  "started_at": "%s",\n' "$MI_REPORT_STARTED_AT"
  printf '  "finished_at": "%s",\n' "$(mi_timestamp)"
  printf '  "duration_seconds": "%s",\n' "$(mi_report_duration_seconds)"
  printf '  "counts": "%s",\n' "$(mi_report_json_escape "$(mi_report_counts_line)")"
  printf '  "events": [\n'
  first="true"
  if [ -n "${MI_REPORT_EVENTS_FILE:-}" ] && [ -s "$MI_REPORT_EVENTS_FILE" ]; then
    while IFS="$(printf '\t')" read -r severity section code message; do
      [ "$first" = "true" ] || printf ',\n'
      first="false"
      printf '    {"severity": "%s", "section": "%s", "code": "%s", "message": "%s"}' \
        "$(mi_report_json_escape "$severity")" \
        "$(mi_report_json_escape "$section")" \
        "$(mi_report_json_escape "$code")" \
        "$(mi_report_json_escape "$message")"
    done <"$MI_REPORT_EVENTS_FILE"
  fi
  printf '\n  ]\n'
  printf '}\n'
}

mi_report_render() {
  case "$MI_REPORT_FORMAT" in
    text) mi_report_render_text "$1" ;;
    md) mi_report_render_md "$1" ;;
    yaml) mi_report_render_yaml "$1" ;;
    json) mi_report_render_json "$1" ;;
  esac
}

mi_report_finish() {
  local rc="$1"
  local tmp
  mi_report_should_emit || return 0
  [ -n "${MI_REPORT_STARTED_AT:-}" ] || return 0

  if [ -z "${MI_REPORT:-}" ]; then
    mi_report_render_text "$rc"
  else
    mi_mkdir_parent "$MI_REPORT"
    tmp="$(mktemp "${MI_REPORT}.tmp.XXXXXX")" || {
      mi_warn "report: could not create temporary report file"
      return 0
    }
    mi_report_render "$rc" >"$tmp"
    mv "$tmp" "$MI_REPORT"
    mi_info "wrote report $MI_REPORT"
  fi
  [ -n "${MI_REPORT_EVENTS_FILE:-}" ] && rm -f "$MI_REPORT_EVENTS_FILE"
}
