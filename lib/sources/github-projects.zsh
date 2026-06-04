#!/usr/bin/env zsh

github_projects_roots() {
  if (( ${+MI_GITHUB_PROJECTS_ROOT_ITEMS} && ${#MI_GITHUB_PROJECTS_ROOT_ITEMS[@]} > 0 )); then
    mi_print_lines "${MI_GITHUB_PROJECTS_ROOT_ITEMS[@]}"
  elif [ -n "${MI_GITHUB_PROJECTS_ROOTS:-}" ]; then
    printf '%s\n' "$MI_GITHUB_PROJECTS_ROOTS"
  fi
}

github_projects_validate_root() {
  local root="$1"
  [ -n "$root" ] || return 1
  case "$root" in
    /*) ;;
    *) return 1 ;;
  esac
  case "$root" in
    *"/../"*|*"/.."|"../"*|"..") return 1 ;;
  esac
}

github_projects_first_root() {
  github_projects_roots | sed -n '1p'
}

github_projects_backup_preflight() {
  local roots root
  mi_has git || { mi_error "github_projects: git is required"; return 1; }
  roots="$(github_projects_roots)"
  [ -n "$roots" ] || { mi_error "github_projects: at least one --github-projects-root absolute path is required"; return 1; }
  while IFS= read -r root; do
    [ -n "$root" ] || continue
    github_projects_validate_root "$root" || { mi_error "github_projects: root must be an absolute safe path: $root"; return 1; }
  done <<EOF
$roots
EOF
}

github_projects_sanitize_url() {
  local url="$1"
  local sanitized="$url"
  local rest
  case "$sanitized" in
    https://*@*)
      rest="${sanitized#https://}"
      sanitized="https://${rest#*@}"
      mi_warn "github_projects: stripped credentials from remote URL"
      ;;
  esac
  printf '%s\n' "$sanitized"
}

github_projects_owner_repo_from_url() {
  local url="$1"
  local rest owner repo
  case "$url" in
    git@github.com:*)
      rest="${url#git@github.com:}"
      ;;
    ssh://git@github.com/*)
      rest="${url#ssh://git@github.com/}"
      ;;
    https://github.com/*)
      rest="${url#https://github.com/}"
      ;;
    *)
      return 1
      ;;
  esac
  rest="${rest%%\?*}"
  rest="${rest%%#*}"
  rest="${rest%.git}"
  owner="${rest%%/*}"
  repo="${rest#*/}"
  [ -n "$owner" ] && [ "$repo" != "$rest" ] && [ -n "$repo" ] || return 1
  printf '%s/%s\n' "$owner" "$repo"
}

github_projects_remote_url() {
  local repo="$1"
  local remote="$2"
  local remote_url=""
  if mi_command_capture remote_url "git -C $repo config remote.$remote.url" git -C "$repo" config --get "remote.$remote.url"; then
    [ -n "$remote_url" ] && github_projects_sanitize_url "$remote_url"
  fi
}

github_projects_upstream_branch() {
  local repo="$1"
  local upstream_ref="" remote branch
  if mi_command_capture upstream_ref "git -C $repo rev-parse upstream" git -C "$repo" rev-parse --abbrev-ref --symbolic-full-name '@{upstream}'; then
    remote="${upstream_ref%%/*}"
    branch="${upstream_ref#*/}"
    [ -n "$remote" ] && [ "$branch" != "$upstream_ref" ] || return 1
    printf '%s|%s\n' "$remote" "$branch"
  fi
}

github_projects_dirty_state() {
  local repo="$1"
  local git_status="" dirty untracked line
  dirty="false"
  untracked="false"
  if mi_command_capture git_status "git -C $repo status porcelain" git -C "$repo" status --porcelain; then
    while IFS= read -r line; do
      [ -n "$line" ] || continue
      case "$line" in
        '?? '*) untracked="true" ;;
        *) dirty="true" ;;
      esac
    done <<EOF
$git_status
EOF
  fi
  printf '%s|%s\n' "$dirty" "$untracked"
}

github_projects_ahead_behind() {
  local repo="$1"
  local counts=""
  if mi_command_capture counts "git -C $repo rev-list upstream counts" git -C "$repo" rev-list --left-right --count HEAD...'@{upstream}'; then
    printf '%s\n' "$counts" | awk '{print ($1 == "" ? 0 : $1) "|" ($2 == "" ? 0 : $2)}'
  else
    printf '0|0\n'
  fi
}

github_projects_skip_dir_name() {
  case "$1" in
    .cache|.git|.hg|.svn|node_modules) return 0 ;;
    *) return 1 ;;
  esac
}

github_projects_discover_repos() {
  local root="$1"
  local found_dir
  find "$root" -type d \( -name .cache -o -name .git -o -name .hg -o -name .svn -o -name node_modules \) -prune -print0 2>/dev/null |
    while IFS= read -r -d '' found_dir; do
      if [ "$(basename -- "$found_dir")" = ".git" ]; then
        printf '%s\0' "$(dirname -- "$found_dir")"
      fi
    done
}

github_projects_has_parent_git_repo() {
  local root="$1"
  local repo="$2"
  local parent
  parent="$(dirname -- "$repo")"
  while [ "$parent" != "$root" ] && [ "$parent" != "/" ] && [ -n "$parent" ]; do
    if [ -d "$parent/.git" ] || [ -f "$parent/.git" ]; then
      return 0
    fi
    parent="$(dirname -- "$parent")"
  done
  return 1
}

github_projects_emit_repo() {
  local root="$1"
  local repo="$2"
  local rel origin_url upstream_url upstream_pair upstream_remote upstream_branch clone_url owner_repo name
  local current_branch="" head_sha="" dirty_pair dirty untracked ahead_pair ahead behind superproject=""
  rel="${repo#"$root"/}"
  [ "$rel" != "$repo" ] || rel="$(basename -- "$repo")"

  if github_projects_has_parent_git_repo "$root" "$repo"; then
    mi_verbose "github_projects: skipped nested repo $repo"
    return 0
  fi

  if mi_command_capture superproject "git -C $repo superproject" git -C "$repo" rev-parse --show-superproject-working-tree && [ -n "$superproject" ]; then
    mi_verbose "github_projects: skipped submodule $repo"
    return 0
  fi

  upstream_pair="$(github_projects_upstream_branch "$repo" || true)"
  upstream_remote="${upstream_pair%%|*}"
  upstream_branch="${upstream_pair#*|}"
  [ "$upstream_branch" != "$upstream_pair" ] || { upstream_remote=""; upstream_branch=""; }

  [ -n "$upstream_remote" ] && upstream_url="$(github_projects_remote_url "$repo" "$upstream_remote" || true)" || upstream_url=""
  origin_url="$(github_projects_remote_url "$repo" origin || true)"
  clone_url="$upstream_url"
  [ -n "$clone_url" ] || clone_url="$origin_url"
  owner_repo="$(github_projects_owner_repo_from_url "$clone_url" || true)"
  [ -n "$owner_repo" ] || { mi_verbose "github_projects: skipped non-GitHub repo $repo"; return 0; }

  name="${owner_repo#*/}"
  mi_command_capture current_branch "git -C $repo current branch" git -C "$repo" branch --show-current || current_branch=""
  mi_command_capture head_sha "git -C $repo HEAD" git -C "$repo" rev-parse HEAD || head_sha=""
  dirty_pair="$(github_projects_dirty_state "$repo")"
  dirty="${dirty_pair%%|*}"
  untracked="${dirty_pair#*|}"
  ahead_pair="$(github_projects_ahead_behind "$repo")"
  ahead="${ahead_pair%%|*}"
  behind="${ahead_pair#*|}"

  printf '    - name: %s\n' "$(mi_yaml_scalar "$name")"
  printf '      ref: %s\n' "$(mi_yaml_scalar "$(mi_github_project_ref "$owner_repo" "$rel")")"
  printf '      owner_repo: %s\n' "$(mi_yaml_scalar "$owner_repo")"
  printf '      root_path: %s\n' "$(mi_yaml_scalar "$root")"
  printf '      relative_path: %s\n' "$(mi_yaml_scalar "$rel")"
  printf '      clone_url: %s\n' "$(mi_yaml_scalar "$clone_url")"
  printf '      upstream_url: %s\n' "$(mi_yaml_scalar "$upstream_url")"
  printf '      upstream_remote: %s\n' "$(mi_yaml_scalar "$upstream_remote")"
  printf '      upstream_branch: %s\n' "$(mi_yaml_scalar "$upstream_branch")"
  printf '      origin_url: %s\n' "$(mi_yaml_scalar "$origin_url")"
  printf '      current_branch: %s\n' "$(mi_yaml_scalar "$current_branch")"
  printf '      head_sha: %s\n' "$(mi_yaml_scalar "$head_sha")"
  printf '      dirty: %s\n' "$dirty"
  printf '      untracked: %s\n' "$untracked"
  printf '      ahead: %s\n' "$ahead"
  printf '      behind: %s\n' "$behind"
}

github_projects_backup() {
  local roots root repo rel count root_count root_total
  roots="$(github_projects_roots)"
  printf 'github_projects:\n'
  printf '  roots:\n'
  while IFS= read -r root; do
    [ -n "$root" ] || continue
    printf '    - path: %s\n' "$(mi_yaml_scalar "$root")"
  done <<EOF
$roots
EOF
  printf '  repos:\n'
  count=0
  while IFS= read -r root; do
    [ -n "$root" ] || continue
    [ -d "$root" ] || { mi_warn "github_projects: root does not exist; skipping $root"; continue; }
    root_total=0
    while IFS= read -r -d '' repo; do
      root_total=$((root_total + 1))
    done < <(github_projects_discover_repos "$root")
    root_count=0
    while IFS= read -r -d '' repo; do
      root_count=$((root_count + 1))
      rel="${repo#"$root"/}"
      [ "$rel" != "$repo" ] || rel="$(basename -- "$repo")"
      mi_inventory_progress_detail github_projects "checking $root_count/$root_total $rel"
      github_projects_emit_repo "$root" "$repo"
      count=$((count + 1))
    done < <(github_projects_discover_repos "$root")
  done <<EOF
$roots
EOF
  [ "$count" -gt 0 ] || mi_verbose "github_projects: no Git repos found"
}

github_projects_restore_root() {
  local override="$1"
  local recorded="$2"
  [ -n "$override" ] && { printf '%s\n' "$override"; return 0; }
  printf '%s\n' "$recorded"
}

github_projects_restore() {
  local rows override_root name ref rel clone_url root_path ignored root dest parent
  mi_has git || { mi_warn "github_projects: git missing; skipping GitHub projects restore"; return 0; }
  override_root="$(github_projects_first_root)"
  rows="$(yq e -r '
    (.github_projects.repos // [])[]? |
    (.name // "" | tostring) + "|" +
    (.ref // "" | tostring) + "|" +
    (.relative_path // "" | tostring) + "|" +
    (.clone_url // "" | tostring) + "|" +
    (.root_path // "" | tostring) + "|" +
    (.ignored // false | tostring)
  ' "$MI_INVENTORY" 2>/dev/null || true)"
  printf '%s\n' "$rows" | while IFS="|" read -r name ref rel clone_url root_path ignored; do
    [ -n "$rel" ] && [ "$rel" != "null" ] || continue
    if [ "$ignored" = "true" ]; then
      mi_info "github_projects: ignored ${ref:-$name}; skipping"
      continue
    fi
    root="$(github_projects_restore_root "$override_root" "$root_path")"
    if ! github_projects_validate_root "$root"; then
      mi_warn "github_projects: unsafe restore root skipped: $root"
      continue
    fi
    case "$rel" in
      /*|*"/../"*|*"/.."|"../"*|"..")
        mi_warn "github_projects: unsafe relative path skipped: $rel"
        continue
        ;;
    esac
    [ -n "$clone_url" ] || { mi_warn "github_projects: missing clone URL for ${ref:-$rel}; skipping"; continue; }
    if ! github_projects_owner_repo_from_url "$clone_url" >/dev/null 2>&1; then
      mi_warn "github_projects: non-GitHub clone URL skipped for ${ref:-$rel}"
      continue
    fi
    dest="$root/$rel"
    if [ -d "$dest/.git" ] || [ -f "$dest/.git" ]; then
      mi_info "github_projects: $rel already exists; skipping"
      continue
    fi
    if [ -e "$dest" ]; then
      mi_warn "github_projects: $dest exists but is not a Git repo; skipping"
      continue
    fi
    parent="$(dirname -- "$dest")"
    if [ "$MI_DRY_RUN" = "true" ]; then
      mi_info "dry-run: would create $parent"
      mi_info "dry-run: would clone $clone_url to $dest"
      continue
    fi
    mkdir -p "$parent" || continue
    mi_run git clone "$clone_url" "$dest"
  done
}
