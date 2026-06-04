# Mac Setup Snapshot Skill

Use this skill when working on the `mac-setup-snapshot` repository.

## Workflow

1. Read `AGENTS.md` and `docs/MANUAL.md`.
2. Check `git status --short --branch`.
3. Keep generated user artifacts out of commits.
4. For code changes, run:

```bash
find bin lib -type f \( -name '*.sh' -o -name 'mac-setup' \) -print0 | xargs -0 -n1 bash -n
```

5. Run `shellcheck` and `bats test` when installed.

## Safety Defaults

- Restore is additive-only.
- Dry-run means no user-state mutation.
- Resume state lives under `~/.mac-setup/resume.yml`.
- Remote installers are downloaded first; never pipe directly into a shell.
- GitHub project restore clones missing repos only; never fetch, pull, reset, clean, overwrite, or delete existing project folders.
