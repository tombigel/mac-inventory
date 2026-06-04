#!/usr/bin/env bats

load helpers/setup

setup() {
  make_mock_bin
  cd "$BATS_TEST_TMPDIR"
}

make_repo() {
  local repo="$1"
  local remote="$2"
  mkdir -p "$repo"
  git -C "$repo" init >/dev/null
  git -C "$repo" checkout -b main >/dev/null 2>&1
  git -C "$repo" remote add origin "$remote"
  printf 'hello\n' >"$repo/README.md"
  git -C "$repo" add README.md
  git -C "$repo" -c user.name="Test User" -c user.email="test@example.com" commit -m "Initial" >/dev/null
}

@test "github projects are disabled by default" {
  run "$BIN" backup --target local --skip-report --apps=false --brew=false --npm=false --pip=false --pipx=false --oh-my-zsh=false --xcode=false --dotfiles=false --manual-apps=false
  [ "$status" -eq 0 ]
  ! grep -q '^github_projects:' mac-setup.backup.yml
}

@test "backup records GitHub repos recursively with sanitized metadata" {
  command -v git >/dev/null 2>&1 || skip "git is required"
  projects="$BATS_TEST_TMPDIR/Projects"
  make_repo "$projects/client/example" "https://token:secret@github.com/example/example.git"
  make_repo "$projects/vendor/other" "https://gitlab.com/example/other.git"

  run "$BIN" backup --target local --skip-report --apps=false --brew=false --npm=false --pip=false --pipx=false --oh-my-zsh=false --xcode=false --dotfiles=false --manual-apps=false --github-projects=true --github-projects-root "$projects"
  [ "$status" -eq 0 ]
  grep -q '^github_projects:' mac-setup.backup.yml
  grep -q 'path: "'"$projects"'"' mac-setup.backup.yml
  grep -q 'name: "example"' mac-setup.backup.yml
  grep -q 'ref: "github_project:example/example"' mac-setup.backup.yml
  grep -q 'relative_path: "client/example"' mac-setup.backup.yml
  grep -q 'clone_url: "https://github.com/example/example.git"' mac-setup.backup.yml
  grep -q 'origin_url: "https://github.com/example/example.git"' mac-setup.backup.yml
  grep -q 'current_branch: "main"' mac-setup.backup.yml
  ! grep -q 'token:secret' mac-setup.backup.yml
  ! grep -q 'other' mac-setup.backup.yml
}

@test "github projects backup rejects relative roots" {
  run "$BIN" backup --target local --skip-report --apps=false --brew=false --npm=false --pip=false --pipx=false --oh-my-zsh=false --xcode=false --dotfiles=false --manual-apps=false --github-projects=true --github-projects-root Projects
  [ "$status" -eq 1 ]
  [[ "$output" == *"root must be an absolute safe path"* ]]
}

@test "restore dry-run reports missing repo clone without writing" {
  command -v yq >/dev/null 2>&1 || skip "yq is required"
  cat >snapshot.yml <<'YAML'
version: 1
github_projects:
  repos:
    - name: "example"
      ref: "github_project:example/example"
      relative_path: "client/example"
      clone_url: "git@github.com:example/example.git"
      root_path: "/ignored"
YAML

  root="$BATS_TEST_TMPDIR/restore-root"
  run "$BIN" restore --dry-run --skip-prepare=true --skip-report --inventory snapshot.yml --apps=false --brew=false --npm=false --pip=false --pipx=false --oh-my-zsh=false --xcode=false --dotfiles=false --manual-apps=false --github-projects=true --github-projects-root "$root"
  [ "$status" -eq 0 ]
  [[ "$output" == *"dry-run: would create $root/client"* ]]
  [[ "$output" == *"dry-run: would clone git@github.com:example/example.git to $root/client/example"* ]]
  [ ! -e "$root" ]
}

@test "restore clones missing GitHub repos and skips existing repos" {
  command -v yq >/dev/null 2>&1 || skip "yq is required"
  mock_command git 'if [ "$1" = "clone" ]; then printf "%s|%s\n" "$2" "$3" >>"'"$BATS_TEST_TMPDIR"'/git.log"; mkdir -p "$3/.git"; exit 0; fi; exit 0'
  root="$BATS_TEST_TMPDIR/restore-root"
  mkdir -p "$root/client/existing/.git"
  cat >snapshot.yml <<'YAML'
version: 1
github_projects:
  repos:
    - name: "example"
      ref: "github_project:example/example"
      relative_path: "client/example"
      clone_url: "git@github.com:example/example.git"
      root_path: "/ignored"
    - name: "existing"
      ref: "github_project:example/existing"
      relative_path: "client/existing"
      clone_url: "git@github.com:example/existing.git"
      root_path: "/ignored"
YAML

  run "$BIN" restore --skip-prepare=true --skip-report --inventory snapshot.yml --apps=false --brew=false --npm=false --pip=false --pipx=false --oh-my-zsh=false --xcode=false --dotfiles=false --manual-apps=false --github-projects=true --github-projects-root "$root"
  [ "$status" -eq 0 ]
  grep -q "git@github.com:example/example.git|$root/client/example" "$BATS_TEST_TMPDIR/git.log"
  ! grep -q "existing.git" "$BATS_TEST_TMPDIR/git.log"
  [[ "$output" == *"client/existing already exists; skipping"* ]]
}

@test "ignore marks GitHub project refs" {
  command -v yq >/dev/null 2>&1 || skip "yq is required"
  cat >snapshot.yml <<'YAML'
version: 1
github_projects:
  repos:
    - name: "example"
      ref: "github_project:example/example"
      owner_repo: "example/example"
      relative_path: "client/example"
      clone_url: "git@github.com:example/example.git"
      root_path: "/Users/test/Projects"
YAML

  run "$BIN" ignore github_project:example/example --source local --inventory snapshot.yml --config config.yml --skip-report
  [ "$status" -eq 0 ]
  grep -q 'ignored: true' snapshot.yml
  grep -q 'ref: github_project:example/example' config.yml
}

@test "wizard github projects folder prompt uses absolute home default" {
  run env PROJECT_ROOT="$PROJECT_ROOT" HOME="$BATS_TEST_TMPDIR/home" bash -c '
    . "$PROJECT_ROOT/lib/common.sh"
    . "$PROJECT_ROOT/lib/args.sh"
    . "$PROJECT_ROOT/lib/endpoint.sh"
    . "$PROJECT_ROOT/lib/inventory.sh"
    . "$PROJECT_ROOT/lib/wizard.sh"
    mi_args_init
    MI_GITHUB_PROJECTS=true
    mi_wizard_read() { printf "\n"; }
    mi_wizard_github_projects_folder_prompt
    printf "%s\n" "$MI_GITHUB_PROJECTS_ROOTS"
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"$BATS_TEST_TMPDIR/home/Projects" ]]
}

@test "wizard github projects folder prompt rejects relative paths" {
  run env PROJECT_ROOT="$PROJECT_ROOT" HOME="$BATS_TEST_TMPDIR/home" ANSWERS="$BATS_TEST_TMPDIR/answers" bash -c '
    . "$PROJECT_ROOT/lib/common.sh"
    . "$PROJECT_ROOT/lib/args.sh"
    . "$PROJECT_ROOT/lib/endpoint.sh"
    . "$PROJECT_ROOT/lib/inventory.sh"
    . "$PROJECT_ROOT/lib/wizard.sh"
    printf "%s\n" Projects /Users/test/Projects >"$ANSWERS"
    mi_args_init
    MI_GITHUB_PROJECTS=true
    mi_wizard_read() {
      local answer
      IFS= read -r answer <"$ANSWERS" || answer=""
      sed "1d" "$ANSWERS" >"$ANSWERS.next"
      mv "$ANSWERS.next" "$ANSWERS"
      printf "%s\n" "$answer"
    }
    mi_wizard_github_projects_folder_prompt
    printf "%s\n" "$MI_GITHUB_PROJECTS_ROOTS"
  ' 2>&1
  [ "$status" -eq 0 ]
  [[ "$output" == *"enter an absolute folder path"* ]]
  [[ "$output" == *"/Users/test/Projects"* ]]
}
