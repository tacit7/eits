# EITS CLI setup

Use `eits`, the Rust-primary CLI, for both interactive and spawned agents.
`eitsr` exists only as a temporary compatibility binary; it does not need to
be on PATH. A working installed `eits` needs no replacement.

## Verify the installed command

Run these read-only checks in the shell that will launch the agent:

```bash
command -v eits
eits --help
eits tasks --help
eits hooks --help
```

The standard local install is `~/.local/bin/eits`. Its help identifies it as
`EITS CLI (Rust core; legacy extras fallback)`. The tasks help checks a
Rust-owned command; the hooks help checks legacy fallback discovery without
installing hooks or changing task state.

If `eits` is missing from PATH but `~/.local/bin/eits` exists, add its directory
to the launching shell's PATH and repeat the checks:

```bash
export PATH="$HOME/.local/bin:$PATH"
```

If an older command shadows it, inspect `type -a eits` and correct the shell's
PATH or obsolete alias. Run `eits` directly: `bash eits` cannot execute the
installed Rust binary. Do not create an alias to `eitsr` as a setup workaround.

## Repo-local development

When developing the CLI or when there is no installed binary, build from the
repository root with the Rust toolchain:

```bash
cargo build -p eits-cli --bin eits
./scripts/eits --help
./scripts/eits hooks --help
```

`scripts/eits` is a Rust-first launcher, not the old Bash implementation. It
selects `target/release/eits` before `target/debug/eits`, then accepts older
`eitsr` builds for compatibility. If an older release build exists, invoke
`./target/debug/eits --help` to check the debug binary just built. The launcher
sets `EITS_EXTRAS` to the repository fallback when that variable is unset.

## Installed files and fallback

The hook installer, `priv/scripts/install-hooks.sh`, accepts `--eits-cli`
pointing to a built Rust `eits` binary and copies it to `~/.local/bin/eits`.
When `EITS_EXTRAS` points to the legacy script, it also installs
`~/.local/bin/eits-extras`. The installer registers hooks as well; it is not
needed merely to verify an existing CLI installation.

Unported command families delegate automatically to `eits-extras`. If a
Rust-owned command works but `eits hooks --help` reports missing extras,
check the fallback discovery paths in the
[migration guide](EITS_RUST_CLI_MIGRATION.md#legacy-fallback). For repo-local
development, an explicit fallback can be supplied without installing files:

```bash
EITS_EXTRAS="$PWD/scripts/eits-extras" ./target/debug/eits hooks --help
```

Keep examples and agent instructions on `eits`; direct `eits-extras` calls are
reserved for work on the legacy fallback itself.
