#!/usr/bin/env bash

xcode_backup() {
  printf 'xcode:\n'
  if xcode-select -p >/dev/null 2>&1; then
    developer_dir="$(xcode-select -p 2>/dev/null)"
    printf '  command_line_tools: true\n'
    printf '  developer_dir: %s\n' "$(mi_yaml_scalar "$developer_dir")"
  else
    printf '  command_line_tools: false\n'
    printf '  developer_dir: ""\n'
  fi
  if [ -d "/Applications/Xcode.app" ]; then
    printf '  app_installed: true\n'
    version="$(/usr/bin/mdls -name kMDItemVersion -raw /Applications/Xcode.app 2>/dev/null || true)"
    printf '  version: %s\n' "$(mi_yaml_scalar "$version")"
  else
    printf '  app_installed: false\n'
    printf '  version: ""\n'
  fi
  if mi_has xcodebuild; then
    if xcodebuild -checkFirstLaunchStatus >/dev/null 2>&1; then
      printf '  first_launch_complete: true\n'
    else
      printf '  first_launch_complete: false\n'
    fi
    if xcodebuild -license check >/dev/null 2>&1; then
      printf '  license_accepted: true\n'
    else
      printf '  license_accepted: false\n'
    fi
  else
    printf '  first_launch_complete: false\n'
    printf '  license_accepted: false\n'
  fi
  printf '  app_store_id: "497799835"\n'
}

xcode_restore() {
  if ! xcode-select -p >/dev/null 2>&1; then
    mi_run xcode-select --install
  else
    mi_info "xcode: command line tools already selected"
  fi
  if [ -d "/Applications/Xcode.app" ] && [ "$MI_SKIP_EXISTING" = "true" ]; then
    mi_info "xcode: Xcode.app already installed"
    return 0
  fi
  if mi_has mas; then
    if ! appstore_login_ready; then
      appstore_handle_missing_login "Xcode App Store restore"
      return $?
    fi
    mi_run mas install 497799835
  else
    mi_warn "xcode: mas missing; install Xcode manually from the App Store"
  fi
}

xcode_doctor() {
  if xcode-select -p >/dev/null 2>&1; then
    mi_info "xcode: developer dir $(xcode-select -p 2>/dev/null)"
  else
    mi_warn "xcode: command line tools missing"
  fi
  if [ -d "/Applications/Xcode.app" ]; then
    mi_info "xcode: Xcode.app installed"
  else
    mi_warn "xcode: Xcode.app missing"
  fi
  if mi_has xcodebuild; then
    xcodebuild -license check >/dev/null 2>&1 && mi_info "xcode: license accepted" || mi_warn "xcode: license not accepted or unavailable"
    xcodebuild -checkFirstLaunchStatus >/dev/null 2>&1 && mi_info "xcode: first launch complete" || mi_warn "xcode: first launch incomplete or unavailable"
  fi
}
