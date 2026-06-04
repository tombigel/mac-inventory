# Copilot Instructions

This project is a Bash CLI for macOS setup snapshots and additive restore.

Prefer:

- Small Bash functions.
- Explicit command wrappers that preserve `--dry-run`.
- Bats tests with mocked external commands.
- Clear user-facing messages before long or prompting actions.
- Additive restore flows, including GitHub project restore that clones missing repos only.
- Validation in sandboxed shells with Homebrew paths injected, for example `PATH="/opt/homebrew/bin:/usr/local/bin:$PATH" /opt/homebrew/bin/bats test`.

Avoid:

- `eval` on user-controlled content.
- direct `curl | sh`.
- committing generated setup snapshots, copied dotfiles, resume state, or secrets.
- destructive restore behavior.
- fetching, pulling, resetting, cleaning, overwriting, or deleting existing GitHub project folders during restore.
- timeout tests that rely on real sleepers or long-running package-manager commands.
