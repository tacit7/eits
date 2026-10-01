# CLI migration diagnostics

Run `eits doctor cli` (or `eits doctor cli --pretty`) to inspect the running Rust
CLI without server access, credential/config loading, or subprocess execution.
Bare `eits doctor` retains its existing configuration, identity, server, git,
hooks, and capability checks.

The migration report is JSON by default, including when `--quiet` is supplied.
It reports:

- `executable`: the actual running executable from the operating system, rather
  than a PATH guess or shell alias; null if the OS cannot provide it.
- `implementation`, `version`, and `build`: Rust implementation, Cargo package
  version, target OS/architecture, and whether debug assertions were enabled.
  This is not a Git revision or a build timestamp.
- `fallback`: whether the normal fallback resolver found an executable file,
  its path and discovery source, and `executed: false`. Missing or invalid
  fallback returns `available: false` and `error: "extras_not_found"`, with null
  path/source. Raw resolver errors are omitted because they may echo environment
  values. Missing fallback is diagnostic information, so the command exits zero.
- `command_families.rust`: native families taken from the CLI command parser.
- `command_families.legacy`: known families in the bundled legacy script. A
  custom fallback may implement different commands. Unknown families are routed
  to extras; their support is decided by that script.

Discovery uses exactly the same resolver as delegation, in this order:

1. `EITS_EXTRAS` (an invalid explicit override stops discovery).
2. `../libexec/eits-extras` beside the canonical running binary.
3. `eits-extras` beside that binary.
4. `eits-extras` on PATH.

The report exposes selected filesystem paths, but does not dump the environment,
authentication values, configuration files, or server URLs. It does not execute
or validate the contents of the fallback script. `executed: false` describes
this invocation, not historical fallback usage. Actual delegation emits the
existing `[eits] delegating to legacy eits-extras` notice on stderr.

For example, if an installed binary reports an older version or an unexpected
executable path, inspect your shell's command resolution and reinstall the
intended binary. If fallback is unavailable, install `eits-extras` alongside the
Rust binary or set `EITS_EXTRAS` to its executable path. See
[EITS CLI setup](EITS_CLI_SETUP.md) for installation details.
