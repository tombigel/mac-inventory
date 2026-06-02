#!/usr/bin/env bash
# shellcheck disable=SC2016

mi_source_enabled() {
  case "$1" in
    apps) [ "$MI_APPS" = "true" ] ;;
    brew) [ "$MI_BREW" = "true" ] ;;
    npm) [ "$MI_NPM" = "true" ] ;;
    pip) [ "$MI_PIP" = "true" ] ;;
    pipx) [ "$MI_PIPX" = "true" ] ;;
    oh_my_zsh) [ "$MI_OH_MY_ZSH" = "true" ] ;;
    xcode) [ "$MI_XCODE" = "true" ] ;;
    dotfiles) [ "$MI_DOTFILES" = "true" ] ;;
    manual_apps) [ "$MI_MANUAL_APPS" = "true" ] ;;
    *) return 1 ;;
  esac
}

mi_section_selected() {
  local section="$1"
  if [ -z "$MI_SECTIONS" ]; then
    return 0
  fi
  printf '%s\n' "$MI_SECTIONS" | grep -Fxq "$section"
}

mi_progress_bar() {
  local index="$1"
  local total="$2"
  local width=12
  local filled empty i
  if [ "$total" -le 0 ] 2>/dev/null; then
    total=1
  fi
  filled=$((index * width / total))
  [ "$filled" -lt 1 ] && filled=1
  [ "$filled" -gt "$width" ] && filled="$width"
  empty=$((width - filled))
  printf '['
  i=0
  while [ "$i" -lt "$filled" ]; do
    printf '#'
    i=$((i + 1))
  done
  i=0
  while [ "$i" -lt "$empty" ]; do
    printf '-'
    i=$((i + 1))
  done
  printf '] %s/%s' "$index" "$total"
}

mi_section_display_name() {
  case "$1" in
    apps) printf 'App Store apps' ;;
    manual_apps) printf 'manual apps' ;;
    brew) printf 'Homebrew' ;;
    npm) printf 'npm globals' ;;
    pip) printf 'pip packages' ;;
    pipx) printf 'pipx packages' ;;
    oh_my_zsh) printf 'Oh My Zsh' ;;
    xcode) printf 'Xcode' ;;
    dotfiles) printf 'dotfiles' ;;
    *) printf '%s' "$1" ;;
  esac
}

mi_sections_for_backup() {
  local section
  for section in apps manual_apps brew npm pip pipx oh_my_zsh xcode dotfiles; do
    if mi_source_enabled "$section" && mi_section_selected "$section"; then
      printf '%s\n' "$section"
    fi
  done
}

mi_sections_for_restore() {
  local section
  for section in apps brew npm pip pipx oh_my_zsh xcode dotfiles manual_apps; do
    if mi_source_enabled "$section" && mi_section_selected "$section"; then
      printf '%s\n' "$section"
    fi
  done
}

mi_sections_count() {
  sed '/^$/d' | wc -l | tr -d ' '
}

mi_section_index() {
  local target="$1"
  local section index
  index=0
  while IFS= read -r section; do
    [ -n "$section" ] || continue
    index=$((index + 1))
    if [ "$section" = "$target" ]; then
      printf '%s\n' "$index"
      return 0
    fi
  done
  printf '0\n'
}

mi_next_section_after() {
  local target="$1"
  local section found
  found="false"
  while IFS= read -r section; do
    [ -n "$section" ] || continue
    if [ "$found" = "true" ]; then
      printf '%s\n' "$section"
      return 0
    fi
    [ "$section" = "$target" ] && found="true"
  done
}

mi_ux_line() {
  [ "${MI_QUIET:-false}" = "true" ] && return 0
  printf '%s\n' "$*" >&2
}

mi_backup_welcome() {
  local sections total next target list_path readme_path
  [ "${MI_QUIET:-false}" = "true" ] && return 0
  sections="$(mi_sections_for_backup)"
  total="$(printf '%s\n' "$sections" | mi_sections_count)"
  next="$(printf '%s\n' "$sections" | sed -n '1p')"
  target="${MI_EFFECTIVE_TARGET:-local}"
  list_path="$(mi_inventory_backup_list_path 2>/dev/null || true)"
  readme_path="$(mi_inventory_backup_readme_path 2>/dev/null || true)"
  mi_ux_line ""
  mi_ux_line "Mac Setup Snapshot $MI_VERSION"
  mi_ux_line "Backup starting"
  mi_ux_line "What will happen: capture $total enabled section(s), then write the setup snapshot, backup-list, and README."
  mi_ux_line "Target: $target"
  mi_ux_line "Snapshot: $MI_INVENTORY"
  [ -n "$list_path" ] && mi_ux_line "Readable list: $list_path"
  [ -n "$readme_path" ] && mi_ux_line "Restore notes: $readme_path"
  if [ -n "$next" ]; then
    mi_ux_line "Next step: $(mi_section_display_name "$next")"
  else
    mi_ux_line "Next step: write the snapshot shell only; no inventory sections are enabled."
  fi
  mi_ux_line ""
}

mi_restore_welcome() {
  local sections total next source prepare_note
  [ "${MI_QUIET:-false}" = "true" ] && return 0
  sections="$(mi_sections_for_restore)"
  total="$(printf '%s\n' "$sections" | mi_sections_count)"
  next="$(printf '%s\n' "$sections" | sed -n '1p')"
  source="${MI_EFFECTIVE_SOURCE:-local}"
  if [ "$MI_SKIP_PREPARE" = "true" ]; then
    prepare_note="Prepare preflight: skipped by flag"
  else
    prepare_note="Prepare preflight: will run before restore"
  fi
  mi_ux_line ""
  mi_ux_line "Mac Setup Snapshot $MI_VERSION"
  mi_ux_line "Restore starting"
  mi_ux_line "What will happen: restore $total enabled section(s) additively from the setup snapshot."
  mi_ux_line "$prepare_note"
  mi_ux_line "Source: $source"
  mi_ux_line "Snapshot: $MI_INVENTORY"
  mi_ux_line "Existing items are skipped by default; no uninstall or cleanup will be performed."
  if [ -n "$next" ]; then
    mi_ux_line "Next step: $(mi_section_display_name "$next")"
  else
    mi_ux_line "Next step: validate the snapshot; no restore sections are enabled."
  fi
  mi_ux_line ""
}

mi_inventory_backup() {
  local tmp tmp_dry
  mi_backup_welcome

  if [ "$MI_DRY_RUN" = "true" ]; then
    mi_info "dry-run: would write setup snapshot to $MI_INVENTORY"
    tmp_dry="$(mktemp "${TMPDIR:-/tmp}/mac-setup-dry.XXXXXX")" || return 1
    mi_verbose "backup: dry-run inventory temp file $tmp_dry"
    mi_inventory_emit_backup "$tmp_dry" || { rm -f "$tmp_dry"; return 1; }
    mi_ignore_apply_config_to_inventory "$tmp_dry" || { rm -f "$tmp_dry"; return 1; }
    cat "$tmp_dry"
    mi_inventory_write_backup_list "$tmp_dry"
    mi_inventory_write_backup_readme "$tmp_dry"
    rm -f "$tmp_dry"
    return 0
  fi

  mi_mkdir_parent "$MI_INVENTORY"
  tmp="$(mktemp "${MI_INVENTORY}.tmp.XXXXXX")" || return 1
  mi_verbose "backup: inventory temp file $tmp"
  mi_inventory_emit_backup "$tmp" || { rm -f "$tmp"; return 1; }
  mi_ignore_apply_config_to_inventory "$tmp" || { rm -f "$tmp"; return 1; }
  mv "$tmp" "$MI_INVENTORY"
  mi_info "wrote $MI_INVENTORY"
  mi_inventory_write_backup_list "$MI_INVENTORY"
  mi_inventory_write_backup_readme "$MI_INVENTORY"
}

mi_inventory_emit_backup() {
  local inventory_out="$1"
  {
    printf 'version: 1\n'
    printf 'created_at: %s\n' "$(mi_yaml_scalar "$(mi_timestamp)")"
    printf 'updated_at: %s\n' "$(mi_yaml_scalar "$(mi_timestamp)")"
    printf 'host:\n'
    printf '  hostname: %s\n' "$(mi_yaml_scalar "$(hostname 2>/dev/null || printf unknown)")"
    printf '  macos: %s\n' "$(mi_yaml_scalar "$(sw_vers -productVersion 2>/dev/null || uname -r)")"
    printf '  arch: %s\n' "$(mi_yaml_scalar "$(uname -m)")"
  } >"$inventory_out"

  mi_inventory_emit_or_copy "$inventory_out" apps appstore_backup || return 1
  MI_MATCHED_CASKS_FILE="$(mktemp "${TMPDIR:-/tmp}/mac-setup-casks.XXXXXX")"
  export MI_MATCHED_CASKS_FILE
  mi_inventory_emit_or_copy "$inventory_out" manual_apps manual_apps_backup || return 1
  mi_inventory_emit_or_copy "$inventory_out" brew brew_backup || return 1
  mi_inventory_emit_or_copy "$inventory_out" npm npm_backup || return 1
  mi_inventory_emit_or_copy "$inventory_out" pip pip_backup || return 1
  mi_inventory_emit_or_copy "$inventory_out" pipx pipx_backup || return 1
  mi_inventory_emit_or_copy "$inventory_out" oh_my_zsh oh_my_zsh_backup || return 1
  mi_inventory_emit_or_copy "$inventory_out" xcode xcode_backup || return 1
  mi_inventory_emit_or_copy "$inventory_out" dotfiles dotfiles_backup || return 1
  mi_cleanup_inventory_temp_files
}

mi_inventory_emit_or_copy() {
  local target_out="$1"
  local section="$2"
  local fn="$3"
  local section_tmp start_epoch rc
  if mi_source_enabled "$section" && mi_section_selected "$section"; then
    section_tmp="$(mktemp "${TMPDIR:-/tmp}/mac-setup-section.XXXXXX")" || return 1
    mi_verbose "backup: section $section temp file $section_tmp"
    start_epoch="$(date '+%s' 2>/dev/null || printf '0')"
    mi_inventory_progress_start "$section"
    mi_verbose "backup: section $section invoking $fn"
    "$fn" >"$section_tmp"
    rc=$?
    mi_verbose "backup: section $section function $fn exited with status $rc"
    mi_inventory_progress_done "$section" "$section_tmp" "$start_epoch"
    if [ "$rc" -ne 0 ]; then
      if [ "$section" = "apps" ] && [ "$MI_APPSTORE_LOGIN" != "skip" ]; then
        cat "$section_tmp" >>"$target_out"
        rm -f "$section_tmp"
        mi_error "backup: App Store inventory is required; pass --apps=false or --appstore-login=skip to skip it"
        return 1
      fi
      mi_warn "backup: section $section reported a non-fatal error; continuing"
    fi
    cat "$section_tmp" >>"$target_out"
    rm -f "$section_tmp"
  elif [ "$MI_UPDATE" = "true" ] && [ -f "$MI_INVENTORY" ]; then
    mi_verbose "backup: preserving unselected section $section from $MI_INVENTORY"
    mi_inventory_copy_section "$MI_INVENTORY" "$section" >>"$target_out"
  fi
  return 0
}

mi_inventory_progress_start() {
  local section="$1"
  local sections total index bar
  [ "${MI_QUIET:-false}" = "true" ] && return 0
  sections="$(mi_sections_for_backup)"
  total="$(printf '%s\n' "$sections" | mi_sections_count)"
  index="$(printf '%s\n' "$sections" | mi_section_index "$section")"
  bar="$(mi_progress_bar "$index" "$total")"
  printf 'backup: %s... %s\n' "$section" "$bar" >&2
}

mi_inventory_progress_done() {
  local section="$1"
  local section_file="$2"
  local start_epoch="$3"
  local now elapsed count sections total index bar next
  [ "${MI_QUIET:-false}" = "true" ] && return 0
  now="$(date '+%s' 2>/dev/null || printf '0')"
  if [ "$start_epoch" -gt 0 ] 2>/dev/null && [ "$now" -ge "$start_epoch" ] 2>/dev/null; then
    elapsed="$((now - start_epoch))"
  else
    elapsed="unknown"
  fi
  sections="$(mi_sections_for_backup)"
  total="$(printf '%s\n' "$sections" | mi_sections_count)"
  index="$(printf '%s\n' "$sections" | mi_section_index "$section")"
  bar="$(mi_progress_bar "$index" "$total")"
  count="$(mi_inventory_section_count "$section" "$section_file")"
  if [ -n "$count" ]; then
    printf 'backup: %s done (%s items, %ss) %s\n' "$section" "$count" "$elapsed" "$bar" >&2
  else
    printf 'backup: %s done (%ss) %s\n' "$section" "$elapsed" "$bar" >&2
  fi
  next="$(printf '%s\n' "$sections" | mi_next_section_after "$section")"
  if [ -n "$next" ]; then
    printf 'backup: next step: %s\n' "$(mi_section_display_name "$next")" >&2
  else
    printf 'backup: next step: write output files\n' >&2
  fi
}

mi_inventory_progress_detail() {
  local section="$1"
  local message="$2"
  [ "${MI_QUIET:-false}" = "true" ] && return 0
  printf 'backup: %s %s\n' "$section" "$message" >&2
}

mi_inventory_section_count() {
  local section="$1"
  local section_file="$2"
  mi_yq_is_v4 || return 0
  case "$section" in
    apps) yq e '(.apps.items // []) | length' "$section_file" 2>/dev/null ;;
    brew) yq e '((.brew.formulae // []) | length) + ((.brew.casks // []) | length)' "$section_file" 2>/dev/null ;;
    npm) yq e '(.npm.globals // []) | length' "$section_file" 2>/dev/null ;;
    pip) yq e '(.pip.packages // []) | length' "$section_file" 2>/dev/null ;;
    pipx) yq e '(.pipx.packages // []) | length' "$section_file" 2>/dev/null ;;
    manual_apps) yq e '(.manual_apps.apps // []) | length' "$section_file" 2>/dev/null ;;
    dotfiles) yq e '(.dotfiles.files // []) | length' "$section_file" 2>/dev/null ;;
    *) printf '' ;;
  esac
}

mi_inventory_backup_list_path() {
  case "${MI_EFFECTIVE_TARGET:-local}" in
    github) return 1 ;;
    icloud)
      [ -n "${MI_ENDPOINT_BUNDLE:-}" ] || MI_ENDPOINT_BUNDLE="$(mi_endpoint_iCloud_bundle)"
      printf '%s/backup-list.md\n' "$MI_ENDPOINT_BUNDLE"
      ;;
    *)
      printf '%s/backup-list.md\n' "$(dirname -- "$MI_INVENTORY")"
      ;;
  esac
}

mi_inventory_backup_readme_path() {
  case "${MI_EFFECTIVE_TARGET:-local}" in
    github) return 1 ;;
    icloud)
      [ -n "${MI_ENDPOINT_BUNDLE:-}" ] || MI_ENDPOINT_BUNDLE="$(mi_endpoint_iCloud_bundle)"
      printf '%s/README.md\n' "$MI_ENDPOINT_BUNDLE"
      ;;
    *)
      printf '%s/README.md\n' "$(dirname -- "$MI_INVENTORY")"
      ;;
  esac
}

mi_inventory_write_backup_list() {
  local source_inventory="$1"
  local backup_list tmp old_inventory old_sections rc
  backup_list="$(mi_inventory_backup_list_path)" || return 0
  if [ "$MI_DRY_RUN" = "true" ]; then
    mi_info "dry-run: would write backup list to $backup_list"
    return 0
  fi
  if ! mi_yq_is_v4; then
    mi_warn "backup-list: yq v4 is required to render $backup_list; skipping"
    return 0
  fi
  mi_mkdir_parent "$backup_list"
  tmp="$(mktemp "${backup_list}.tmp.XXXXXX")" || {
    mi_warn "backup-list: could not create temporary file"
    return 0
  }
  old_inventory="$MI_INVENTORY"
  old_sections="$MI_SECTIONS"
  MI_INVENTORY="$source_inventory"
  MI_SECTIONS=""
  mi_verbose "backup-list: rendering $source_inventory to $backup_list via $tmp"
  mi_inventory_list_md >"$tmp"
  rc=$?
  MI_INVENTORY="$old_inventory"
  MI_SECTIONS="$old_sections"
  if [ "$rc" -ne 0 ]; then
    rm -f "$tmp"
    mi_warn "backup-list: could not render $backup_list"
    return 0
  fi
  mv "$tmp" "$backup_list"
  mi_info "wrote $backup_list"
}

mi_inventory_write_backup_readme() {
  local source_inventory="$1"
  local readme tmp rc
  readme="$(mi_inventory_backup_readme_path)" || return 0
  if [ "$MI_DRY_RUN" = "true" ]; then
    mi_info "dry-run: would write backup README to $readme"
    return 0
  fi
  mi_mkdir_parent "$readme"
  tmp="$(mktemp "${readme}.tmp.XXXXXX")" || {
    mi_warn "backup-readme: could not create temporary file"
    return 0
  }
  mi_inventory_backup_readme_content "$source_inventory" >"$tmp"
  rc=$?
  if [ "$rc" -ne 0 ]; then
    rm -f "$tmp"
    mi_warn "backup-readme: could not render $readme"
    return 0
  fi
  mv "$tmp" "$readme"
  mi_info "wrote $readme"
}

mi_inventory_backup_readme_content() {
  local source_inventory="$1"
  local restore_command dry_restore_command prepare_command
  prepare_command="${MI_PROGRAM_NAME:-mac-setup} prepare"
  case "${MI_EFFECTIVE_TARGET:-local}" in
    icloud)
      restore_command="${MI_PROGRAM_NAME:-mac-setup} restore --source icloud --icloud-root \"$MI_ICLOUD_ROOT\""
      dry_restore_command="${MI_PROGRAM_NAME:-mac-setup} restore --dry-run --skip-prepare=true --source icloud --icloud-root \"$MI_ICLOUD_ROOT\""
      ;;
    *)
      restore_command="${MI_PROGRAM_NAME:-mac-setup} restore --source local --inventory mac-setup.yml"
      dry_restore_command="${MI_PROGRAM_NAME:-mac-setup} restore --dry-run --skip-prepare=true --source local --inventory mac-setup.yml"
      ;;
  esac

  cat <<EOF
# Mac Setup Snapshot Backup

Generated: $(mi_timestamp)
Snapshot: $(basename "$source_inventory")

## Files

- \`mac-setup.yml\`: machine-readable setup snapshot used by restore.
- \`backup-list.md\`: human-readable summary generated from the snapshot.
- \`README.md\`: these restore notes.
- \`metadata.yml\`: iCloud endpoint metadata, when this backup is stored in iCloud.
- \`files/\`: copied dotfiles selected for backup. This folder may contain sensitive local configuration; review before sharing.

## Restore

1. Install or check out Mac Setup Snapshot so the \`${MI_PROGRAM_NAME:-mac-setup}\` command is available.
2. Run prepare to check clean-Mac prerequisites:

\`\`\`bash
$prepare_command
\`\`\`

3. Preview restore actions:

\`\`\`bash
$dry_restore_command
\`\`\`

4. Restore additively:

\`\`\`bash
$restore_command
\`\`\`

Restore is additive: it installs, copies, checks, and reports. It does not uninstall apps, remove packages, or clean up existing files. Dotfile restore skips existing files unless you pass \`--overwrite=true\`.

## Useful Commands

\`\`\`bash
${MI_PROGRAM_NAME:-mac-setup} list --format md --source local --inventory mac-setup.yml
${MI_PROGRAM_NAME:-mac-setup} status
${MI_PROGRAM_NAME:-mac-setup} continue
\`\`\`

EOF
}

mi_inventory_copy_section() {
  local file="$1"
  local section="$2"
  awk -v section="$section" '
    $0 ~ "^" section ":" {printing=1; print; next}
    printing && /^[A-Za-z0-9_]+:/ {printing=0}
    printing {print}
  ' "$file"
}

mi_inventory_list() {
  [ -f "$MI_INVENTORY" ] || { mi_error "setup snapshot not found: $MI_INVENTORY"; return 1; }
  case "$MI_FORMAT" in
    yaml)
      if [ -z "$MI_SECTIONS" ]; then
        cat "$MI_INVENTORY"
      else
        while IFS= read -r section; do
          mi_inventory_copy_section "$MI_INVENTORY" "$section"
        done <<EOF
$MI_SECTIONS
EOF
      fi
      ;;
    json)
      mi_require_yq || return 1
      yq e -o=json "$MI_INVENTORY"
      ;;
    md)
      mi_inventory_list_md
      ;;
    table)
      if [ -z "$MI_SECTIONS" ]; then
        awk -F: '/^[A-Za-z0-9_]+:/ {print $1}' "$MI_INVENTORY"
      else
        printf '%s\n' "$MI_SECTIONS"
      fi
      ;;
  esac
}

mi_inventory_md_section_selected() {
  mi_section_selected "$1" || return 1
}

mi_inventory_md_table() {
  local title="$1"
  local header="$2"
  local query="$3"
  local rows
  printf '\n## %s\n\n' "$title"
  printf '%s\n' "$header"
  rows="$(yq e -r "$query" "$MI_INVENTORY" 2>/dev/null || true)"
  if [ -n "$rows" ]; then
    printf '%s\n' "$rows"
  else
    printf '_None recorded._\n'
  fi
}

mi_inventory_list_md() {
  local value
  mi_require_yq || return 1

  printf '# Mac Setup Snapshot\n\n'
  value="$(yq e '.created_at // ""' "$MI_INVENTORY" 2>/dev/null)"
  [ -n "$value" ] && [ "$value" != "null" ] && printf "%s \`%s\`\n" "- Created:" "$value"
  value="$(yq e '.updated_at // ""' "$MI_INVENTORY" 2>/dev/null)"
  [ -n "$value" ] && [ "$value" != "null" ] && printf "%s \`%s\`\n" "- Updated:" "$value"
  printf "%s \`%s\`\n" "- Snapshot:" "$MI_INVENTORY"

  if mi_inventory_md_section_selected host; then
    printf '\n## Host\n\n'
    yq e -r '
      .host // {} |
      ["| Field | Value |", "| --- | --- |"] +
      (to_entries | map("| " + .key + " | " + (.value // "" | tostring) + " |")) |
      .[]
    ' "$MI_INVENTORY"
  fi

  mi_inventory_md_section_selected apps && mi_inventory_md_table "App Store Apps" "| Ref | ID | Name | Path | Version | Ignored |
| --- | --- | --- | --- | --- | --- |" '
    (.apps.items // .apps // [])[]? |
    "| " + (.ref // "" | tostring) + " | " + (.id // "" | tostring) + " | " + (.name // "" | tostring) + " | " + (.path // "" | tostring) + " | " + (.version // "" | tostring) + " | " + (.ignored // false | tostring) + " |"
  '

  if mi_inventory_md_section_selected brew; then
    mi_inventory_md_table "Homebrew Formulae" "| Name | Version |
| --- | --- |" '
      (.brew.formulae // [])[]? |
      "| " + (.name // "" | tostring) + " | " + (.version // "" | tostring) + " |"
    '
    mi_inventory_md_table "Homebrew Casks" "| Ref | Cask | App | Path | Version | Ignored |
| --- | --- | --- | --- | --- | --- |" '
      (.brew.casks // [])[]? |
      "| " + (.ref // "" | tostring) + " | " + (.name // "" | tostring) + " | " + (.display_name // "" | tostring) + " | " + (.path // "" | tostring) + " | " + (.version // "" | tostring) + " | " + (.ignored // false | tostring) + " |"
    '
  fi

  mi_inventory_md_section_selected npm && mi_inventory_md_table "npm Globals" "| Name | Version |
| --- | --- |" '
    (.npm.globals // [])[]? |
    "| " + (.name // "" | tostring) + " | " + (.version // "" | tostring) + " |"
  '

  mi_inventory_md_section_selected pip && mi_inventory_md_table "pip Packages" "| Name | Version |
| --- | --- |" '
    (.pip.packages // [])[]? |
    "| " + (.name // "" | tostring) + " | " + (.version // "" | tostring) + " |"
  '

  mi_inventory_md_section_selected pipx && mi_inventory_md_table "pipx Packages" "| Name | Version |
| --- | --- |" '
    (.pipx.packages // [])[]? |
    "| " + (.name // "" | tostring) + " | " + (.version // "" | tostring) + " |"
  '

  if mi_inventory_md_section_selected oh_my_zsh; then
    printf '\n## Oh My Zsh\n\n'
    yq e -r '
      .oh_my_zsh // {} |
      ["| Field | Value |", "| --- | --- |"] +
      (to_entries | map("| " + .key + " | " + (.value // "" | tostring) + " |")) |
      .[]
    ' "$MI_INVENTORY"
  fi

  if mi_inventory_md_section_selected xcode; then
    printf '\n## Xcode\n\n'
    yq e -r '
      .xcode // {} |
      ["| Field | Value |", "| --- | --- |"] +
      (to_entries | map("| " + .key + " | " + (.value // "" | tostring) + " |")) |
      .[]
    ' "$MI_INVENTORY"
  fi

  mi_inventory_md_section_selected dotfiles && mi_inventory_md_table "Dotfiles" "| Path | Exists | Backup Path |
| --- | --- | --- |" '
    (.dotfiles.files // [])[]? |
    "| " + (.path // "" | tostring) + " | " + (.exists // "" | tostring) + " | " + (.backup_path // "" | tostring) + " |"
  '

  mi_inventory_md_section_selected manual_apps && mi_inventory_md_table "Manual Apps" "| Ref | Name | Path | Version | Brew Cask | Ignored |
| --- | --- | --- | --- | --- | --- |" '
    (.manual_apps.apps // [])[]? |
    "| " + (.ref // "" | tostring) + " | " + (.name // "" | tostring) + " | " + (.path // "" | tostring) + " | " + (.version // "" | tostring) + " | " + ((.selected_brew_cask | select(. != null and . != "")) // (.brew_cask_candidate | select(. != null and . != "")) // "" | tostring) + " | " + (.ignored // false | tostring) + " |"
  '
}

mi_inventory_restore() {
  mi_restore_welcome
  if [ "$MI_SKIP_PREPARE" != "true" ]; then
    if [ "$MI_PREPARE_ONLY" = "true" ]; then
      mi_workflow_run "prepare"
      return $?
    fi
    mi_workflow_run "restore"
    return $?
  fi
  mi_inventory_restore_body
}

mi_inventory_restore_body() {
  [ -f "$MI_INVENTORY" ] || { mi_error "setup snapshot not found: $MI_INVENTORY"; return 1; }
  mi_require_yq || return 1

  mi_restore_section apps appstore_restore || return 1
  mi_restore_section brew brew_restore || return 1
  mi_restore_section npm npm_restore || return 1
  mi_restore_section pip pip_restore || return 1
  mi_restore_section pipx pipx_restore || return 1
  mi_restore_section oh_my_zsh oh_my_zsh_restore || return 1
  mi_restore_section xcode xcode_restore || return 1
  mi_restore_section dotfiles dotfiles_restore || return 1
  mi_restore_section manual_apps manual_apps_restore || return 1
}

mi_restore_section() {
  local section="$1"
  local fn="$2"
  local start_epoch rc
  mi_source_enabled "$section" || return 0
  mi_section_selected "$section" || return 0
  start_epoch="$(date '+%s' 2>/dev/null || printf '0')"
  mi_restore_progress_start "$section"
  "$fn"
  rc=$?
  mi_restore_progress_done "$section" "$start_epoch" "$rc"
  return "$rc"
}

mi_restore_progress_start() {
  local section="$1"
  local sections total index bar
  [ "${MI_QUIET:-false}" = "true" ] && return 0
  sections="$(mi_sections_for_restore)"
  total="$(printf '%s\n' "$sections" | mi_sections_count)"
  index="$(printf '%s\n' "$sections" | mi_section_index "$section")"
  bar="$(mi_progress_bar "$index" "$total")"
  printf 'restore: %s... %s\n' "$section" "$bar" >&2
}

mi_restore_progress_done() {
  local section="$1"
  local start_epoch="$2"
  local rc="$3"
  local sections total index bar next now elapsed status
  [ "${MI_QUIET:-false}" = "true" ] && return 0
  now="$(date '+%s' 2>/dev/null || printf '0')"
  if [ "$start_epoch" -gt 0 ] 2>/dev/null && [ "$now" -ge "$start_epoch" ] 2>/dev/null; then
    elapsed="$((now - start_epoch))"
  else
    elapsed="unknown"
  fi
  status="done"
  [ "$rc" -eq 0 ] || status="failed"
  sections="$(mi_sections_for_restore)"
  total="$(printf '%s\n' "$sections" | mi_sections_count)"
  index="$(printf '%s\n' "$sections" | mi_section_index "$section")"
  bar="$(mi_progress_bar "$index" "$total")"
  printf 'restore: %s %s (%ss) %s\n' "$section" "$status" "$elapsed" "$bar" >&2
  if [ "$rc" -eq 0 ]; then
    next="$(printf '%s\n' "$sections" | mi_next_section_after "$section")"
    if [ -n "$next" ]; then
      printf 'restore: next step: %s\n' "$(mi_section_display_name "$next")" >&2
    else
      printf 'restore: next step: final summary\n' >&2
    fi
  fi
}

mi_doctor() {
  mi_doctor_tool brew
  mi_doctor_tool yq
  mi_doctor_tool mas
  mi_doctor_tool npm
  mi_doctor_tool pip3
  mi_doctor_tool pipx
  mi_doctor_github
  appstore_doctor
  oh_my_zsh_doctor
  xcode_doctor
}

mi_doctor_tool() {
  if mi_has "$1"; then
    mi_info "$1: found"
  else
    mi_warn "$1: missing"
  fi
}
