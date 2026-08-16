# EITS Rust CLI Migration

This document records the current state of the migration from the legacy Bash
`eits` CLI to the Rust CLI.

## Current State

- `eits` is intended to be the primary CLI command for agents and humans.
- The Rust crate is `crates/eits-cli`.
- The Rust binary target `eits` is the primary binary.
- The Rust binary target `eitsr` still exists as a temporary compatibility
  alias.
- `scripts/eits` is now a small Rust-first launcher for repo-local development.
- The legacy Bash implementation is preserved at `scripts/eits-extras`.
- Rust fallback execs `eits-extras` for command families that have not been
  ported yet.
- Local cutover has been smoke-tested with `~/.local/bin/eits` installed as the
  Rust release binary and `~/.local/bin/eits-extras` installed as the legacy
  fallback.

## Rust-Owned Command Families

These command families are owned by Rust today:

- `tasks`
- `dm`
- `sessions`
- `commits`
- `notes`
- `whoami`

Agents should call `eits`, not `eitsr` and not `eits-extras`. The fallback is an
implementation detail for unported command families.

## Legacy Fallback

The legacy Bash CLI is not deleted yet. It remains at `scripts/eits-extras` so
unported commands can keep working during the migration.

Fallback discovery order in Rust is:

1. `EITS_EXTRAS`
2. `../libexec/eits-extras` beside the Rust binary
3. `eits-extras` beside the Rust binary
4. `eits-extras` found on `PATH`

Rust must not fall back to `eits` on `PATH`, because `eits` is now the Rust
binary and that can recurse.

## Compatibility Contracts

Do not change these without updating hooks, skills, and tests:

- `eits sessions get <uuid>` prints the session fields at the top level. Hooks
  read fields such as `.name` directly.
- Rust-owned command stdout is JSON by default, including errors.
- `--quiet` prints bare IDs for supported mutation commands.
- Codex session env files under `~/.eits/codex/sessions/<session>.env` are used
  as CLI process-local fallback config when direct `EITS_*` env vars are not set.
- Explicit process env vars win over Codex env-file values.

## Installer State

`priv/scripts/install-hooks.sh` installs:

- Rust CLI binary to `~/.local/bin/eits`
- legacy fallback to `~/.local/bin/eits-extras` when `EITS_EXTRAS` is provided

The installer should not install the Bash implementation as `eits`.

## Validation Status

The Rust CLI migration path has been validated with:

```bash
cargo test -p eits-cli
bash -n scripts/eits scripts/eits-extras priv/scripts/install-hooks.sh
./scripts/eits --help
./scripts/eits hooks --help
eits --help
eits hooks --help
```

Known full-project status:

- `mix precommit` was run after the cutover.
- CLI-relevant checks passed.
- The full precommit run still had unrelated failures in
  `test/eye_in_the_sky/claude/sdk_test.exs` around SDK message delivery.

## Next Steps

1. Commit the current Rust-first baseline.
2. Audit every installer, release workflow, app bundle path, hook, skill, and
   doc reference that still assumes Bash is `eits`.
3. Port remaining command families from `scripts/eits-extras` into Rust one
   family at a time.
4. Add contract tests before each command-family port.
5. Add telemetry or warnings when Rust falls back to `eits-extras`, so remaining
   fallback usage is visible.
6. Keep `eitsr` for one compatibility window, then remove it after consumers
   have moved to `eits`.
7. After fallback usage is near zero, stop installing `eits-extras` by default.

## Rule For New Work

New automation, hooks, skills, docs, and examples must call `eits`. Do not add
new direct calls to `scripts/eits-extras` unless the work is explicitly about
the legacy fallback.
