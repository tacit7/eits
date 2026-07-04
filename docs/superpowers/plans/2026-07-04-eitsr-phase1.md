# eitsr Phase 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship `eitsr`, a Rust CLI implementing the six Phase 1 command families (`tasks`, `dm`, `sessions`, `whoami`, `commits`, `notes`) with the new JSON output contract, falling back to the bash `scripts/eits` for everything else.

**Architecture:** Cargo workspace member `crates/eits-cli` producing binary `eitsr`. Thin layers: config resolution → blocking HTTP client with retry → per-family command modules → JSON output/error-envelope printer. Unknown root subcommands `exec` the bash script.

**Tech Stack:** Rust 2021, clap 4 (derive), reqwest 0.12 (blocking, json), serde_json 1, thiserror 2.

**Spec:** `docs/superpowers/specs/2026-07-04-eits-cli-rust-rewrite-design.md` — read it first; it is the contract. This plan implements it.

## Global Constraints

- Binary name: `eitsr` (cutover to `eits` is out of scope for this plan).
- JSON to stdout, compact by default; `--pretty` / `EITS_PRETTY=1` pretty-prints; exceptions: `--help`, `--version`, successful `--quiet`.
- Errors: JSON envelope `{"error","code","status","hint"}` to **stdout**, never stderr. Stderr = retry chatter only.
- Exit codes: 0 ok · 1 API/permanent · 2 usage/config · 3 connection failure after retries.
- Error `code` enum: `not_found`, `validation`, `unauthorized`, `forbidden`, `conflict`, `server_error`, `connection_failed`, `config_invalid`, `usage`, `extras_not_found`, `extras_exec_failed`, `lock_timeout`.
- `EITS_URL` is the full base including `/api/v1`; never append path segments; trim trailing `/`.
- Headers `x-eits-role: orchestrator` + `x-eits-session: <uuid>` ONLY when `EITS_SESSION_UUID` is set. `Authorization: Bearer` ONLY when `EITS_API_KEY` is set.
- Retry: refused/timeouts/429/502/503/504, 4 attempts, 2s base doubling, ±20% jitter, 30s cap, 10s request timeout.
- DM lock: mkdir on literal `/tmp/eits_dm_<uuid|id|default>.lock`, 0.5s poll, 60 attempts, rmdir release. Match bash exactly.
- Annotation offline queue: failed annotate → append JSON line to `~/.eits/pending-annotations.log`, warn stderr, exit 1.
- Workspace: `mix compile` and existing `cargo check` in `src-tauri` must stay green.
- Commit after every task; run `cargo fmt` + `cargo clippy -- -D warnings` before each commit.

## File Structure

```
Cargo.toml                       # NEW workspace root (members: src-tauri, crates/eits-cli)
crates/eits-cli/
  Cargo.toml
  src/main.rs                    # clap Cli, global flags, dispatch, extras fallback
  src/config.rs                  # base URL + identity resolution
  src/error.rs                   # EitsError, code enum, envelope, exit mapping
  src/output.rs                  # print_json / print_quiet, pretty resolution
  src/http.rs                    # blocking client, headers, retry/backoff
  src/extras.rs                  # extras discovery + exec (self-exec guard)
  src/lock.rs                    # DM mkdir lock
  src/duration.rs                # Nm/Nh/Nd → ISO8601 UTC
  src/commands/mod.rs
  src/commands/{whoami,tasks,notes,commits,sessions,dm}.rs
  tests/common/mod.rs            # in-process mock HTTP server (std TcpListener)
  tests/{contract.rs,fallback.rs,live.rs}
```

### Phase 1 endpoint map (extracted from scripts/eits — authoritative)

| Command | Method + path |
|---|---|
| tasks list | GET `/tasks?{qs}` |
| tasks get | GET `/tasks/{id}` |
| tasks create/begin | POST `/tasks`; begin then PATCH `/tasks/{id}` `{"state":"start","session_id":...}` |
| tasks claim | PATCH `/tasks/{id}` `{"state":"start","session_id":...}` |
| tasks update | PATCH `/tasks/{id}` |
| tasks delete | DELETE `/tasks/{id}` |
| tasks annotate | POST `/tasks/{id}/annotations` `{"body","title"}` (+offline queue) |
| tasks complete | GET `/tasks/{id}` guard (state_id==3 → already_closed) then POST `/tasks/{id}/complete` `{"message","session_id"}`; then optional `--commit` hashes → commits create; `--notify` → dm send |
| tasks active | GET `/tasks?{qs}` filtered states 2,4 |
| tasks search | GET `/tasks?q={query}&...` |
| tasks states | static local table (no API call — port bash text as JSON) |
| tasks link-session | POST `/tasks/{id}/sessions` `{"session_id"}` |
| tasks bulk-update | PATCH `/tasks/{id}` per id (loop) |
| notes list/search | GET `/notes?{qs}` |
| notes get | GET `/notes/{id}` |
| notes add/create | POST `/notes` `{"parent_type","parent_id","body","title","starred"}` |
| notes update | PATCH `/notes/{id}` |
| commits list | GET `/commits?{qs}` (`--since-time` → `since_time` ISO8601 via duration.rs) |
| commits create | POST `/commits` |
| sessions list | GET `/sessions?{qs}` |
| sessions get | GET `/sessions/{uuid}` |
| sessions create | POST `/sessions` |
| sessions update | PATCH `/sessions/{uuid}` |
| sessions end | POST `/sessions/{uuid}/end` `{"final_status"}` or `{}` |
| sessions context | GET/PATCH `/sessions/{uuid}/context` |
| dm inbox/list | GET `/dm?{qs}` |
| dm read | GET `/dm/{id}{qs}` |
| dm send | POST `/dm` under DM lock |
| whoami | no API call — prints env-derived identity JSON |

For flag-by-flag query-string parity, port from these bash regions: tasks 780–1290, notes 1440–1560, commits 2190–2360, sessions 340–730, dm 2460–2660. When in doubt, replicate bash behavior exactly — parity beats elegance.

---

### Task 1: Workspace + crate scaffold + clap skeleton with extras fallback

**Files:**
- Create: `Cargo.toml` (workspace root), `crates/eits-cli/Cargo.toml`, `crates/eits-cli/src/main.rs`, `crates/eits-cli/src/extras.rs`, `crates/eits-cli/tests/fallback.rs`
- Modify: `src-tauri/Cargo.toml` (no content change needed; verify workspace membership works)

**Interfaces:**
- Produces: `extras::find_extras() -> Result<PathBuf, EitsError>` (stub error type until Task 2 refines; use `String` error here, swap in Task 2), `extras::exec_extras(path, args: &[OsString]) -> !` on Unix (`std::os::unix::process::CommandExt::exec`), clap `Cli` with `#[command(external_subcommand)] External(Vec<OsString>)` variant and global `--pretty`/`--quiet` flags.

- [ ] **Step 1: Create workspace root `Cargo.toml`**

```toml
[workspace]
members = ["src-tauri", "crates/eits-cli"]
resolver = "2"
```

Note: `src-tauri/Cargo.toml` has `[profile.release]` settings; move them to the workspace root (cargo requires profiles at workspace root) — copy the `panic/codegen-units/lto/opt-level/strip` block verbatim and delete it from `src-tauri/Cargo.toml`.

- [ ] **Step 2: Verify existing build still green**

Run: `cargo check -p eye-in-the-sky 2>&1 | tail -3`
Expected: `Finished` (warnings about workspace are OK; errors are not)

- [ ] **Step 3: Create `crates/eits-cli/Cargo.toml`**

```toml
[package]
name = "eits-cli"
version = "0.1.0"
edition = "2021"

[[bin]]
name = "eitsr"
path = "src/main.rs"

[dependencies]
clap = { version = "4", features = ["derive"] }
reqwest = { version = "0.12", features = ["blocking", "json"], default-features = false, package = "reqwest" }
serde = { version = "1", features = ["derive"] }
serde_json = "1"
thiserror = "2"
rand = "0.8"

[dev-dependencies]
assert_cmd = "2"
predicates = "3"
tempfile = "3"
```

(reqwest needs a TLS feature for https EITS_URLs: add `"native-tls"` to features.)

- [ ] **Step 4: Write failing fallback test `crates/eits-cli/tests/fallback.rs`**

```rust
use assert_cmd::Command;

fn fake_extras(dir: &tempfile::TempDir) -> std::path::PathBuf {
    let p = dir.path().join("eits-extras");
    std::fs::write(&p, "#!/bin/sh\necho \"EXTRAS:$@\"\nexit 42\n").unwrap();
    use std::os::unix::fs::PermissionsExt;
    std::fs::set_permissions(&p, std::fs::Permissions::from_mode(0o755)).unwrap();
    p
}

#[test]
fn unknown_root_subcommand_execs_extras_with_argv() {
    let dir = tempfile::tempdir().unwrap();
    let extras = fake_extras(&dir);
    Command::cargo_bin("eitsr").unwrap()
        .env("EITS_EXTRAS", &extras)
        .args(["worktree", "list", "--flag", "x y"])
        .assert()
        .code(42)
        .stdout(predicates::str::contains("EXTRAS:worktree list --flag x y"));
}

#[test]
fn missing_extras_is_json_error_exit_1() {
    Command::cargo_bin("eitsr").unwrap()
        .env("EITS_EXTRAS", "/nonexistent/nope")
        .env("PATH", "/usr/bin:/bin") // no bash eits on PATH
        .args(["worktree", "list"])
        .assert()
        .code(1)
        .stdout(predicates::str::contains("\"code\":\"extras_not_found\""));
}

#[test]
fn global_flags_are_not_forwarded_to_extras() {
    let dir = tempfile::tempdir().unwrap();
    let extras = fake_extras(&dir);
    Command::cargo_bin("eitsr").unwrap()
        .env("EITS_EXTRAS", &extras)
        .args(["--pretty", "worktree", "list"])
        .assert()
        .code(2)
        .stdout(predicates::str::contains("\"code\":\"usage\""));
}
```

- [ ] **Step 5: Run tests, verify they fail to compile (no binary yet)**

Run: `cargo test -p eits-cli --test fallback 2>&1 | tail -5`
Expected: compile error — `main.rs` missing.

- [ ] **Step 6: Implement `src/extras.rs`**

```rust
use std::ffi::OsString;
use std::path::PathBuf;

/// Spec: discovery order — EITS_EXTRAS, ../libexec/eits-extras, sibling,
/// bash `eits` on PATH (guarding self-exec), bundled app path (later).
pub fn find_extras() -> Result<PathBuf, String> {
    if let Ok(p) = std::env::var("EITS_EXTRAS") {
        let p = PathBuf::from(p);
        return if is_executable_file(&p) { Ok(p) } else { Err(format!("EITS_EXTRAS={} is not an executable file", p.display())) };
    }
    let me = std::env::current_exe().ok().and_then(|p| p.canonicalize().ok());
    if let Some(me) = &me {
        if let Some(bin_dir) = me.parent() {
            for cand in [bin_dir.join("../libexec/eits-extras"), bin_dir.join("eits-extras")] {
                if is_executable_file(&cand) { return Ok(cand); }
            }
        }
    }
    // Migration period: bash `eits` on PATH, but never ourselves.
    if let Some(path_eits) = which_on_path("eits") {
        let canon = path_eits.canonicalize().ok();
        if canon.as_ref() != me.as_ref().map(|m| m).map(|m| m).as_deref().map(|m| m).map(|m| m as &std::path::Path) {
            // simpler: compare canonicalized paths
        }
        if canon.is_some() && canon != me {
            return Ok(path_eits);
        }
    }
    Err("no extras script found (set EITS_EXTRAS or install scripts/eits on PATH)".into())
}

fn is_executable_file(p: &std::path::Path) -> bool {
    use std::os::unix::fs::PermissionsExt;
    p.is_file() && p.metadata().map(|m| m.permissions().mode() & 0o111 != 0).unwrap_or(false)
}

fn which_on_path(name: &str) -> Option<PathBuf> {
    std::env::var_os("PATH").and_then(|paths| {
        std::env::split_paths(&paths)
            .map(|d| d.join(name))
            .find(|p| is_executable_file(p))
    })
}

pub fn exec_extras(path: &std::path::Path, args: &[OsString]) -> std::io::Error {
    use std::os::unix::process::CommandExt;
    std::process::Command::new(path).args(args).exec()
}
```

(Clean up the self-exec guard when writing real code: `if canon.is_some() && canon != me { return Ok(path_eits); }` is the whole rule — canonicalize both, compare, skip if equal.)

- [ ] **Step 7: Implement `src/main.rs` (skeleton)**

```rust
mod extras;

use clap::Parser;
use std::ffi::OsString;

#[derive(Parser)]
#[command(name = "eitsr", version, about = "EITS CLI (Rust core; bash fallback for extras)")]
struct Cli {
    /// Pretty-print JSON output (default: compact; or EITS_PRETTY=1)
    #[arg(long, global = true)]
    pretty: bool,
    /// Print only the created/affected ID on success (mutations)
    #[arg(long, short, global = true)]
    quiet: bool,
    #[command(subcommand)]
    cmd: Cmd,
}

#[derive(clap::Subcommand)]
enum Cmd {
    /// Anything not Rust-owned falls through to the bash extras script
    #[command(external_subcommand)]
    External(Vec<OsString>),
}

fn main() {
    // Global flags before an external subcommand are a usage error per spec:
    // detect "--pretty/--quiet/-q appear before an unknown root" by checking
    // raw argv when dispatching External.
    let raw: Vec<OsString> = std::env::args_os().skip(1).collect();
    let cli = Cli::parse();
    match cli.cmd {
        Cmd::External(args) => {
            let had_global_flags = raw.len() > args.len();
            if had_global_flags {
                println!("{}", serde_json::json!({
                    "error": "global flags are not supported for bash-extras subcommands",
                    "code": "usage",
                    "hint": "drop --pretty/--quiet or use a Rust-owned command"
                }));
                std::process::exit(2);
            }
            match extras::find_extras() {
                Ok(path) => {
                    let e = extras::exec_extras(&path, &args);
                    println!("{}", serde_json::json!({
                        "error": format!("failed to exec extras: {e}"),
                        "code": "extras_exec_failed"
                    }));
                    std::process::exit(1);
                }
                Err(msg) => {
                    println!("{}", serde_json::json!({
                        "error": msg, "code": "extras_not_found"
                    }));
                    std::process::exit(1);
                }
            }
        }
    }
}
```

- [ ] **Step 8: Run fallback tests**

Run: `cargo test -p eits-cli --test fallback 2>&1 | tail -5`
Expected: 3 passed.

- [ ] **Step 9: fmt, clippy, commit**

```bash
cargo fmt -p eits-cli && cargo clippy -p eits-cli -- -D warnings
git add Cargo.toml src-tauri/Cargo.toml crates/
git commit -m "feat(eitsr): workspace scaffold, clap skeleton, bash-extras fallback"
```

---

### Task 2: Error type + output module

**Files:**
- Create: `crates/eits-cli/src/error.rs`, `crates/eits-cli/src/output.rs`
- Modify: `crates/eits-cli/src/main.rs` (wire modules; route exits through `error::exit_with`), `crates/eits-cli/src/extras.rs` (return `EitsError` instead of `String`)

**Interfaces:**
- Produces:
  - `error::EitsError { message: String, code: Code, status: Option<u16>, hint: Option<String> }`
  - `error::Code` enum (12 variants per Global Constraints) with `serde(rename_all = "snake_case")`
  - `EitsError::exit_code(&self) -> i32` — usage/config_invalid → 2, connection_failed → 3, else 1
  - `error::exit_with(err: EitsError, pretty: bool) -> !` — prints envelope to stdout (compact/pretty rules), exits
  - `output::pretty_enabled(cli_pretty: bool) -> bool` — `cli_pretty || env EITS_PRETTY=1`
  - `output::print_json(value: &serde_json::Value, pretty: bool)`
  - `output::print_quiet_id(value: &serde_json::Value, pointer: &str) -> Result<(), EitsError>` — extracts e.g. `/task/id`, prints raw + newline

- [ ] **Step 1: Write failing unit tests (in-module `#[cfg(test)]`)**

```rust
// in error.rs
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn envelope_shape_and_exit_codes() {
        let e = EitsError::api("Task not found", Code::NotFound, Some(404))
            .with_hint("Run `eitsr tasks list`");
        let v = e.to_envelope();
        assert_eq!(v["code"], "not_found");
        assert_eq!(v["status"], 404);
        assert_eq!(e.exit_code(), 1);
        assert_eq!(EitsError::usage("bad flag").exit_code(), 2);
        assert_eq!(EitsError::api("down", Code::ConnectionFailed, None).exit_code(), 3);
    }
    #[test]
    fn non_http_error_omits_status() {
        let v = EitsError::usage("x").to_envelope();
        assert!(v.get("status").is_none() || v["status"].is_null());
    }
}
// in output.rs
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn quiet_extracts_id_by_pointer() {
        let v = serde_json::json!({"task": {"id": 123}});
        assert_eq!(quiet_id(&v, "/task/id").unwrap(), "123");
        let v2 = serde_json::json!({"session": {"uuid": "abc-def"}});
        assert_eq!(quiet_id(&v2, "/session/uuid").unwrap(), "abc-def");
        assert!(quiet_id(&v, "/nope").is_err());
    }
}
```

- [ ] **Step 2: Run, verify fail** — `cargo test -p eits-cli --lib 2>&1 | tail -3` → compile error.

- [ ] **Step 3: Implement `error.rs`**

```rust
use serde_json::json;

#[derive(Debug, Clone, Copy, PartialEq, serde::Serialize)]
#[serde(rename_all = "snake_case")]
pub enum Code {
    NotFound, Validation, Unauthorized, Forbidden, Conflict, ServerError,
    ConnectionFailed, ConfigInvalid, Usage, ExtrasNotFound, ExtrasExecFailed, LockTimeout,
}

#[derive(Debug)]
pub struct EitsError {
    pub message: String,
    pub code: Code,
    pub status: Option<u16>,
    pub hint: Option<String>,
}

impl EitsError {
    pub fn api(msg: impl Into<String>, code: Code, status: Option<u16>) -> Self {
        Self { message: msg.into(), code, status, hint: None }
    }
    pub fn usage(msg: impl Into<String>) -> Self { Self::api(msg, Code::Usage, None) }
    pub fn config(msg: impl Into<String>) -> Self { Self::api(msg, Code::ConfigInvalid, None) }
    pub fn with_hint(mut self, h: impl Into<String>) -> Self { self.hint = Some(h.into()); self }

    pub fn exit_code(&self) -> i32 {
        match self.code {
            Code::Usage | Code::ConfigInvalid => 2,
            Code::ConnectionFailed => 3,
            _ => 1,
        }
    }

    pub fn to_envelope(&self) -> serde_json::Value {
        let mut v = json!({ "error": self.message, "code": self.code });
        if let Some(s) = self.status { v["status"] = json!(s); }
        if let Some(h) = &self.hint { v["hint"] = json!(h); }
        v
    }
}

pub fn exit_with(err: EitsError, pretty: bool) -> ! {
    crate::output::print_json(&err.to_envelope(), pretty);
    std::process::exit(err.exit_code());
}
```

Map HTTP statuses → codes in one place (used by http.rs in Task 4):
`400 → Validation, 401 → Unauthorized, 403 → Forbidden, 404 → NotFound, 409 → Conflict, 5xx → ServerError`.

- [ ] **Step 4: Implement `output.rs`**

```rust
pub fn pretty_enabled(cli_pretty: bool) -> bool {
    cli_pretty || std::env::var("EITS_PRETTY").map(|v| v == "1").unwrap_or(false)
}

pub fn print_json(v: &serde_json::Value, pretty: bool) {
    if pretty {
        println!("{}", serde_json::to_string_pretty(v).expect("serializable"));
    } else {
        println!("{}", serde_json::to_string(v).expect("serializable"));
    }
}

pub fn quiet_id(v: &serde_json::Value, pointer: &str) -> Result<String, crate::error::EitsError> {
    v.pointer(pointer)
        .map(|id| match id {
            serde_json::Value::String(s) => s.clone(),
            other => other.to_string(),
        })
        .ok_or_else(|| crate::error::EitsError::api(
            format!("response has no id at {pointer}"),
            crate::error::Code::ServerError, None,
        ))
}

pub fn print_quiet_id(v: &serde_json::Value, pointer: &str) -> Result<(), crate::error::EitsError> {
    println!("{}", quiet_id(v, pointer)?);
    Ok(())
}
```

- [ ] **Step 5: Rewire `main.rs` + `extras.rs` to `EitsError`** — extras errors become `Code::ExtrasNotFound` / `Code::ExtrasExecFailed`; the usage-error inline JSON in main becomes `error::exit_with(EitsError::usage(...).with_hint(...), pretty)`.

- [ ] **Step 6: Run all tests** — `cargo test -p eits-cli 2>&1 | tail -3` → all pass (lib + fallback).

- [ ] **Step 7: Commit** — `git add crates && git commit -m "feat(eitsr): error envelope + output module"`

---

### Task 3: Config resolution (base URL + identity)

**Files:**
- Create: `crates/eits-cli/src/config.rs`
- Modify: `crates/eits-cli/src/main.rs` (mod decl)

**Interfaces:**
- Produces:
  - `config::Config { base_url: String, api_key: Option<String>, session_uuid: Option<String>, session_id: Option<String>, project_id: Option<String> }`
  - `Config::resolve() -> Result<Config, EitsError>` — reads real env/files
  - `Config::resolve_from(env: &dyn Fn(&str) -> Option<String>, config_dir: &Path) -> Result<Config, EitsError>` — testable seam
  - `Config::session_identity(&self) -> Option<&str>` — uuid else integer id (CLI defaults + lock identity)

- [ ] **Step 1: Write failing tests** (in-module; use `tempfile` dirs for `desktop.json`/`.env` fixtures)

```rust
#[cfg(test)]
mod tests {
    use super::*;
    fn env(pairs: &[(&str, &str)]) -> impl Fn(&str) -> Option<String> + '_ {
        move |k| pairs.iter().find(|(n, _)| *n == k).map(|(_, v)| v.to_string())
    }

    #[test]
    fn eits_url_env_wins_and_trailing_slash_trimmed() {
        let d = tempfile::tempdir().unwrap();
        let c = Config::resolve_from(&env(&[("EITS_URL", "http://x:9/api/v1/")]), d.path()).unwrap();
        assert_eq!(c.base_url, "http://x:9/api/v1");
    }
    #[test]
    fn malformed_eits_url_is_config_error() {
        let d = tempfile::tempdir().unwrap();
        let e = Config::resolve_from(&env(&[("EITS_URL", "not a url")]), d.path()).unwrap_err();
        assert_eq!(e.exit_code(), 2);
    }
    #[test]
    fn desktop_json_port_builds_url() {
        let d = tempfile::tempdir().unwrap();
        std::fs::write(d.path().join("desktop.json"), r#"{"port": 34877}"#).unwrap();
        let c = Config::resolve_from(&env(&[]), d.path()).unwrap();
        assert_eq!(c.base_url, "http://localhost:34877/api/v1");
    }
    #[test]
    fn invalid_desktop_json_is_config_error_not_silent_skip() {
        let d = tempfile::tempdir().unwrap();
        std::fs::write(d.path().join("desktop.json"), "{oops").unwrap();
        assert_eq!(Config::resolve_from(&env(&[]), d.path()).unwrap_err().exit_code(), 2);
    }
    #[test]
    fn env_file_url_then_default() {
        let d = tempfile::tempdir().unwrap();
        std::fs::write(d.path().join(".env"), "FOO=1\nEITS_URL=http://y:5001/api/v1\n").unwrap();
        let c = Config::resolve_from(&env(&[]), d.path()).unwrap();
        assert_eq!(c.base_url, "http://y:5001/api/v1");
        let d2 = tempfile::tempdir().unwrap();
        let c2 = Config::resolve_from(&env(&[]), d2.path()).unwrap();
        assert_eq!(c2.base_url, "http://localhost:5001/api/v1");
    }
    #[test]
    fn identity_prefers_uuid() {
        let d = tempfile::tempdir().unwrap();
        let c = Config::resolve_from(&env(&[("EITS_SESSION_UUID", "u-1"), ("EITS_SESSION_ID", "7")]), d.path()).unwrap();
        assert_eq!(c.session_identity(), Some("u-1"));
    }
}
```

- [ ] **Step 2: Run/fail, then implement**

```rust
use crate::error::{Code, EitsError};
use std::path::Path;

pub struct Config {
    pub base_url: String,
    pub api_key: Option<String>,
    pub session_uuid: Option<String>,
    pub session_id: Option<String>,
    pub project_id: Option<String>,
}

impl Config {
    pub fn resolve() -> Result<Self, EitsError> {
        let cfg_dir = std::env::var("XDG_CONFIG_HOME")
            .map(std::path::PathBuf::from)
            .unwrap_or_else(|_| {
                std::path::PathBuf::from(std::env::var("HOME").unwrap_or_default()).join(".config")
            })
            .join("eits");
        Self::resolve_from(&|k| std::env::var(k).ok(), &cfg_dir)
    }

    pub fn resolve_from(env: &dyn Fn(&str) -> Option<String>, config_dir: &Path) -> Result<Self, EitsError> {
        let base_url = if let Some(url) = env("EITS_URL") {
            validate_url(&url)?
        } else if config_dir.join("desktop.json").exists() {
            let raw = std::fs::read_to_string(config_dir.join("desktop.json"))
                .map_err(|e| EitsError::config(format!("cannot read desktop.json: {e}")))?;
            let v: serde_json::Value = serde_json::from_str(&raw)
                .map_err(|e| EitsError::config(format!("invalid JSON in desktop.json: {e}"))
                    .with_hint("fix or delete ~/.config/eits/desktop.json"))?;
            match v.get("port").and_then(|p| p.as_u64()) {
                Some(port) => format!("http://localhost:{port}/api/v1"),
                None => fallback_env_file_or_default(config_dir)?,
            }
        } else {
            fallback_env_file_or_default(config_dir)?
        };
        Ok(Self {
            base_url,
            api_key: env("EITS_API_KEY"),
            session_uuid: env("EITS_SESSION_UUID"),
            session_id: env("EITS_SESSION_ID"),
            project_id: env("EITS_PROJECT_ID"),
        })
    }

    pub fn session_identity(&self) -> Option<&str> {
        self.session_uuid.as_deref().or(self.session_id.as_deref())
    }
}

fn fallback_env_file_or_default(config_dir: &Path) -> Result<String, EitsError> {
    let env_file = config_dir.join(".env");
    if let Ok(raw) = std::fs::read_to_string(&env_file) {
        if let Some(line) = raw.lines().find(|l| l.starts_with("EITS_URL=")) {
            return validate_url(line.trim_start_matches("EITS_URL="));
        }
    }
    Ok("http://localhost:5001/api/v1".to_string())
}

fn validate_url(url: &str) -> Result<String, EitsError> {
    let trimmed = url.trim_end_matches('/').to_string();
    if !(trimmed.starts_with("http://") || trimmed.starts_with("https://")) || trimmed.contains(' ') {
        return Err(EitsError::config(format!("invalid EITS_URL: {url}"))
            .with_hint("expected full base URL including /api/v1, e.g. http://localhost:5001/api/v1"));
    }
    Ok(trimmed)
}
```

- [ ] **Step 3: Tests pass, commit** — `git commit -m "feat(eitsr): config + base-URL resolution with strict malformed-source errors"`

---

### Task 4: HTTP client with retry + mock-server test harness

**Files:**
- Create: `crates/eits-cli/src/http.rs`, `crates/eits-cli/tests/common/mod.rs`, `crates/eits-cli/tests/contract.rs`

**Interfaces:**
- Produces:
  - `http::Client::new(config: Config) -> Client` (holds reqwest blocking client, 10s timeout, 10s connect timeout)
  - `Client::get(&self, path_and_query: &str) -> Result<serde_json::Value, EitsError>`
  - `Client::post(&self, path: &str, body: serde_json::Value) -> Result<Value, EitsError>`
  - `Client::patch(&self, path: &str, body: Value) -> Result<Value, EitsError>`
  - `Client::delete(&self, path: &str) -> Result<Value, EitsError>`
  - Headers per spec (bearer iff api_key; role+session iff session_uuid).
  - Retry per spec: refused/timeout/429/502/503/504, 4 attempts, 2s base ×2, ±20% jitter, cap 30s, chatter to stderr. For tests: `EITS_RETRY_BASE_MS` env var overrides the 2000ms base (default 2000) so tests run fast — undocumented, test-only.
  - 4xx/5xx → `EitsError` with code from status map, `error` message extracted from body `.error` or `.message`, raw body as message fallback.
- Consumes: `config::Config`, `error::{EitsError, Code}`.

**tests/common/mod.rs** — hand-rolled single-thread mock server:

```rust
use std::io::{BufRead, BufReader, Read, Write};
use std::net::TcpListener;

pub struct MockServer { pub url: String, handle: Option<std::thread::JoinHandle<Vec<Request>>> }
pub struct Request { pub method: String, pub path: String, pub headers: Vec<(String, String)>, pub body: String }

/// Serve `responses` (status, body) in order, one per connection, then stop.
pub fn serve(responses: Vec<(u16, &'static str)>) -> MockServer {
    let listener = TcpListener::bind("127.0.0.1:0").unwrap();
    let url = format!("http://{}/api/v1", listener.local_addr().unwrap());
    let handle = std::thread::spawn(move || {
        let mut seen = Vec::new();
        for (status, body) in responses {
            let (mut stream, _) = listener.accept().unwrap();
            let mut reader = BufReader::new(stream.try_clone().unwrap());
            let mut line = String::new();
            reader.read_line(&mut line).unwrap();
            let mut parts = line.split_whitespace();
            let method = parts.next().unwrap_or("").to_string();
            let path = parts.next().unwrap_or("").to_string();
            let mut headers = Vec::new();
            let mut content_len = 0usize;
            loop {
                let mut h = String::new();
                reader.read_line(&mut h).unwrap();
                let h = h.trim_end().to_string();
                if h.is_empty() { break; }
                if let Some((k, v)) = h.split_once(": ") {
                    if k.eq_ignore_ascii_case("content-length") { content_len = v.parse().unwrap_or(0); }
                    headers.push((k.to_lowercase(), v.to_string()));
                }
            }
            let mut body_buf = vec![0u8; content_len];
            reader.read_exact(&mut body_buf).unwrap();
            seen.push(Request { method, path, headers, body: String::from_utf8_lossy(&body_buf).into() });
            let resp = format!(
                "HTTP/1.1 {status} X\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{body}",
                body.len()
            );
            stream.write_all(resp.as_bytes()).unwrap();
        }
        seen
    });
    MockServer { url, handle: Some(handle) }
}

impl MockServer {
    pub fn finish(mut self) -> Vec<Request> { self.handle.take().unwrap().join().unwrap() }
}
```

- [ ] **Step 1: Write failing contract tests** (`tests/contract.rs`)

```rust
mod common;
use assert_cmd::Command;

#[test]
fn get_maps_404_to_envelope_on_stdout_exit_1() {
    let srv = common::serve(vec![(404, r#"{"error":"Task not found"}"#)]);
    let out = Command::cargo_bin("eitsr").unwrap()
        .env("EITS_URL", &srv.url)
        .args(["tasks", "get", "999"])
        .assert()
        .code(1);
    let stdout = String::from_utf8(out.get_output().stdout.clone()).unwrap();
    let v: serde_json::Value = serde_json::from_str(stdout.trim()).unwrap(); // stdout is pure JSON
    assert_eq!(v["code"], "not_found");
    assert_eq!(v["status"], 404);
    let stderr = String::from_utf8(out.get_output().stderr.clone()).unwrap();
    assert!(stderr.is_empty(), "stderr must be empty on permanent errors: {stderr}");
}

#[test]
fn retries_503_then_succeeds_chatter_on_stderr_only() {
    let srv = common::serve(vec![
        (503, "{}"),
        (200, r#"{"task":{"id":1,"title":"t","state":"Done"}}"#),
    ]);
    let out = Command::cargo_bin("eitsr").unwrap()
        .env("EITS_URL", &srv.url)
        .env("EITS_RETRY_BASE_MS", "10")
        .args(["tasks", "get", "1"])
        .assert()
        .success();
    let stdout = String::from_utf8(out.get_output().stdout.clone()).unwrap();
    serde_json::from_str::<serde_json::Value>(stdout.trim()).unwrap();
    assert!(!stdout.contains("retrying"));
}

#[test]
fn headers_sent_only_when_env_set() {
    let srv = common::serve(vec![(200, r#"{"task":{"id":1}}"#)]);
    Command::cargo_bin("eitsr").unwrap()
        .env("EITS_URL", &srv.url)
        .env("EITS_SESSION_UUID", "u-123")
        .env("EITS_API_KEY", "k")
        .args(["tasks", "get", "1"]).assert().success();
    let reqs = srv.finish();
    let h = &reqs[0].headers;
    assert!(h.iter().any(|(k, v)| k == "x-eits-session" && v == "u-123"));
    assert!(h.iter().any(|(k, v)| k == "x-eits-role" && v == "orchestrator"));
    assert!(h.iter().any(|(k, v)| k == "authorization" && v == "Bearer k"));

    let srv2 = common::serve(vec![(200, r#"{"task":{"id":1}}"#)]);
    Command::cargo_bin("eitsr").unwrap()
        .env("EITS_URL", &srv2.url)
        .env_remove("EITS_SESSION_UUID").env_remove("EITS_API_KEY")
        .env("EITS_SESSION_ID", "7") // integer-only: NO headers
        .args(["tasks", "get", "1"]).assert().success();
    let reqs2 = srv2.finish();
    assert!(!reqs2[0].headers.iter().any(|(k, _)| k == "x-eits-session" || k == "authorization" || k == "x-eits-role"));
}

#[test]
fn connection_refused_exits_3() {
    Command::cargo_bin("eitsr").unwrap()
        .env("EITS_URL", "http://127.0.0.1:1/api/v1")
        .env("EITS_RETRY_BASE_MS", "10")
        .args(["tasks", "get", "1"])
        .assert()
        .code(3)
        .stdout(predicates::str::contains("\"code\":\"connection_failed\""));
}
```

These tests require `tasks get` to exist — implement the minimal slice of Task 6 (`tasks get` only) as part of this task to make the harness testable end-to-end. That is deliberate.

- [ ] **Step 2: Implement `http.rs`**

```rust
use crate::config::Config;
use crate::error::{Code, EitsError};
use serde_json::Value;
use std::time::Duration;

pub struct Client { cfg: Config, http: reqwest::blocking::Client }

impl Client {
    pub fn new(cfg: Config) -> Self {
        let http = reqwest::blocking::Client::builder()
            .timeout(Duration::from_secs(10))
            .connect_timeout(Duration::from_secs(10))
            .danger_accept_invalid_certs(true) // parity with bash `curl -k`
            .build().expect("client");
        Self { cfg, http }
    }

    pub fn get(&self, pq: &str) -> Result<Value, EitsError> { self.send(reqwest::Method::GET, pq, None) }
    pub fn post(&self, p: &str, b: Value) -> Result<Value, EitsError> { self.send(reqwest::Method::POST, p, Some(b)) }
    pub fn patch(&self, p: &str, b: Value) -> Result<Value, EitsError> { self.send(reqwest::Method::PATCH, p, Some(b)) }
    pub fn delete(&self, p: &str) -> Result<Value, EitsError> { self.send(reqwest::Method::DELETE, p, None) }

    fn send(&self, method: reqwest::Method, path: &str, body: Option<Value>) -> Result<Value, EitsError> {
        let url = format!("{}{}", self.cfg.base_url, path);
        let base_ms: u64 = std::env::var("EITS_RETRY_BASE_MS").ok().and_then(|v| v.parse().ok()).unwrap_or(2000);
        let mut delay_ms = base_ms;
        for attempt in 0..4 {
            let mut req = self.http.request(method.clone(), &url);
            if let Some(k) = &self.cfg.api_key { req = req.bearer_auth(k); }
            if let Some(u) = &self.cfg.session_uuid {
                req = req.header("x-eits-role", "orchestrator").header("x-eits-session", u);
            }
            if let Some(b) = &body { req = req.json(b); }
            match req.send() {
                Ok(resp) => {
                    let status = resp.status().as_u16();
                    if matches!(status, 429 | 502 | 503 | 504) && attempt < 3 {
                        eprintln!("[eitsr] {status}, retrying in {}ms...", jitter(delay_ms));
                        std::thread::sleep(Duration::from_millis(jitter(delay_ms)));
                        delay_ms = (delay_ms * 2).min(30_000);
                        continue;
                    }
                    let text = resp.text().unwrap_or_default();
                    if status >= 400 {
                        return Err(status_error(status, &text));
                    }
                    return serde_json::from_str(&text).map_err(|_| EitsError::api(
                        format!("non-JSON response: {}", text.chars().take(200).collect::<String>()),
                        Code::ServerError, Some(status)));
                }
                Err(e) if (e.is_connect() || e.is_timeout()) && attempt < 3 => {
                    eprintln!("[eitsr] connection error, retrying in {}ms... (server restarting?)", jitter(delay_ms));
                    std::thread::sleep(Duration::from_millis(jitter(delay_ms)));
                    delay_ms = (delay_ms * 2).min(30_000);
                }
                Err(e) => {
                    return Err(EitsError::api(
                        format!("cannot reach {url}: {e}"), Code::ConnectionFailed, None,
                    ).with_hint("is the EITS server running? (mix phx.server, or set EITS_URL)"));
                }
            }
        }
        Err(EitsError::api(format!("cannot reach {url} after 4 attempts"), Code::ConnectionFailed, None)
            .with_hint("is the EITS server running? (mix phx.server, or set EITS_URL)"))
    }
}

fn jitter(ms: u64) -> u64 {
    use rand::Rng;
    let pct: i64 = rand::thread_rng().gen_range(-20..=20);
    ((ms as i64) + (ms as i64) * pct / 100).max(1) as u64
}

fn status_error(status: u16, body: &str) -> EitsError {
    let code = match status {
        400 => Code::Validation, 401 => Code::Unauthorized, 403 => Code::Forbidden,
        404 => Code::NotFound, 409 => Code::Conflict, _ => Code::ServerError,
    };
    let msg = serde_json::from_str::<Value>(body).ok()
        .and_then(|v| v.get("error").or(v.get("message")).and_then(|m| m.as_str()).map(String::from))
        .unwrap_or_else(|| if body.contains("<html") || body.contains("<!DOCTYPE") {
            "server returned HTML — check server logs".into()
        } else { body.chars().take(300).collect() });
    EitsError::api(msg, code, Some(status))
}
```

- [ ] **Step 3: Implement minimal `commands/tasks.rs` slice (`tasks get`)** — see Task 6 Step 3 for the module shape; only the `get` arm here, printing `{"task": {...}}` normalized (unwrap the bash duplication: prefer response `.task`, else whole object under `"task"`).

- [ ] **Step 4: Run contract tests** — `cargo test -p eits-cli --test contract 2>&1 | tail -3` → 4 passed.

- [ ] **Step 5: Commit** — `git commit -m "feat(eitsr): http client with retry/backoff + contract test harness + tasks get"`

---

### Task 5: whoami + duration + DM lock utilities

**Files:**
- Create: `crates/eits-cli/src/commands/mod.rs`, `crates/eits-cli/src/commands/whoami.rs`, `crates/eits-cli/src/duration.rs`, `crates/eits-cli/src/lock.rs`

**Interfaces:**
- Produces:
  - `commands::whoami::run(cfg: &Config, pretty: bool)` — prints `{"session_uuid","session_id","agent_uuid","agent_id","project_id"}` from env (nulls when unset; include `agent_uuid` from `EITS_AGENT_UUID`), no API call.
  - `duration::to_iso8601_utc(spec: &str, now: SystemTime) -> Result<String, EitsError>` — `Nm|Nh|Nd` ago → `YYYY-MM-DDTHH:MM:SSZ`; anything else → usage error.
  - `lock::DmLock::acquire(identity: &str) -> Result<DmLock, EitsError>` — mkdir `/tmp/eits_dm_<identity>.lock`, poll 500ms, 60 attempts, `Code::LockTimeout` on expiry; `Drop` does rmdir.

- [ ] **Step 1: Failing tests** — whoami via assert_cmd (env set/unset → JSON keys), duration unit tests (`"24h"`, `"7d"`, `"30m"`, reject `"xyz"`, `"5w"`), lock unit test (acquire → second acquire with 1-attempt override times out → drop releases → third acquires). For the lock test add a test-only `acquire_with(identity, attempts, poll_ms)` used by `acquire` with (60, 500).

- [ ] **Step 2: Implement.** `duration.rs`:

```rust
pub fn to_iso8601_utc(spec: &str, now: std::time::SystemTime) -> Result<String, crate::error::EitsError> {
    let (num, unit) = spec.split_at(spec.len().saturating_sub(1));
    let n: u64 = num.parse().map_err(|_| crate::error::EitsError::usage(
        format!("invalid duration: {spec} (expected <N>m, <N>h, or <N>d)")))?;
    let secs = match unit { "m" => n * 60, "h" => n * 3600, "d" => n * 86400,
        _ => return Err(crate::error::EitsError::usage(format!("invalid duration unit: {spec}"))) };
    let ts = now.duration_since(std::time::UNIX_EPOCH).unwrap().as_secs() - secs;
    // days-since-epoch → civil date (Howard Hinnant algorithm), no chrono dep
    let (days, rem) = (ts / 86400, ts % 86400);
    let (h, m, s) = (rem / 3600, (rem % 3600) / 60, rem % 60);
    let z = days as i64 + 719_468;
    let era = z.div_euclid(146_097);
    let doe = z.rem_euclid(146_097);
    let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365;
    let y = yoe + era * 400;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let d = doy - (153 * mp + 2) / 5 + 1;
    let mo = if mp < 10 { mp + 3 } else { mp - 9 };
    let y = if mo <= 2 { y + 1 } else { y };
    Ok(format!("{y:04}-{mo:02}-{d:02}T{h:02}:{m:02}:{s:02}Z"))
}
```

`lock.rs`:

```rust
pub struct DmLock { path: std::path::PathBuf }

impl DmLock {
    pub fn acquire(identity: &str) -> Result<Self, crate::error::EitsError> {
        Self::acquire_with(identity, 60, 500)
    }
    pub fn acquire_with(identity: &str, attempts: u32, poll_ms: u64) -> Result<Self, crate::error::EitsError> {
        // Literal /tmp for parity with bash _dm_post — see spec "DM serialization lock".
        let path = std::path::PathBuf::from(format!("/tmp/eits_dm_{identity}.lock"));
        for _ in 0..=attempts {
            if std::fs::create_dir(&path).is_ok() { return Ok(Self { path }); }
            std::thread::sleep(std::time::Duration::from_millis(poll_ms));
        }
        Err(crate::error::EitsError::api(
            "DM lock acquire timeout (possible deadlock) — try again",
            crate::error::Code::LockTimeout, None))
    }
}
impl Drop for DmLock {
    fn drop(&mut self) { let _ = std::fs::remove_dir(&self.path); }
}
```

- [ ] **Step 3: Wire `whoami` into main dispatch, tests pass, commit** — `git commit -m "feat(eitsr): whoami, duration parsing, DM lock"`

---

### Task 6: tasks family (complete)

**Files:**
- Create/Modify: `crates/eits-cli/src/commands/tasks.rs`, main dispatch, `crates/eits-cli/tests/contract.rs` (append)

**Interfaces:**
- Consumes: `http::Client`, `output::*`, `duration`, `config::Config`.
- Produces: `commands::tasks::run(client: &Client, cfg: &Config, args: TasksCmd, pretty: bool, quiet: bool) -> Result<(), EitsError>` where `TasksCmd` is the clap subcommand enum with variants `List, Get, Begin, Complete, Annotate, Update, Search, States, Create, Claim, Delete, Active, BulkUpdate, LinkSession`.

Subcommand behaviors (port flag parity from scripts/eits:780–1290; endpoint map above):

- `list`: flags `-s/--session`, `-p/--project`, `-l/--limit`, `-q/--query`, `--tag`, `--mine`, `--all`. Default scope: session (EITS_SESSION_UUID) unless `--all`; project default from EITS_PROJECT_ID. Output `{"items": [...], "count": N}` from response `.tasks // .results`.
- `get <id>`: normalize to `{"task": {...}}` — take response `.task` if present else whole object; drop duplicated top-level fields.
- `begin`: `--id` (claim existing: PATCH state start) or `-t/--title` (+`-d`, `-p`, `--priority`) → POST `/tasks` then PATCH claim. Quiet pointer `/task/id`.
- `complete <id> -m <msg> [--commit <hash>]... [--notify <session>]`: GET guard → if `state_id == 3` print `{"status":"already_closed","message":"task is already Done — no change made","task_id":N}` exit 0; else POST `/tasks/{id}/complete` `{"message","session_id"}`; then loop `--commit` hashes through commits create (warn-only on failure), `--notify` through dm send (warn-only). Quiet pointer `/task/id` falling back to printing the input id.
- `annotate <id> -b <body> [-t <title>]`: POST `/tasks/{id}/annotations`; on **any** post-retry failure append `{"task_id":N,"body":"...","title":"..."}\n` to `~/.eits/pending-annotations.log` (create dir), warn stderr, exit 1 — byte-compatible with bash queue format.
- `update <id> -s <state> [-t] [-d]`: PATCH; accept state aliases todo/start/done/review → 1/2/3/4 (port bash alias table).
- `states`: no API call; print `{"items":[{"id":1,"name":"To Do","aliases":["todo"]},{"id":2,"name":"In Progress","aliases":["start","begin"]},{"id":3,"name":"Done","aliases":["done","complete"]},{"id":4,"name":"In Review","aliases":["review"]}],"count":4}` (verify against `eits tasks states` live before hardcoding).
- `active`: GET `/tasks?...` with session scope + states 2,4 client-side filter if no server param (check bash 780–860 for exact qs).
- `bulk-update --ids <csv> --state <s>` and `--session <id> --state <s>`: loop PATCH; output `{"items":[per-task results],"count":N}`.

- [ ] **Step 1: Append failing contract tests** — cover: `tasks get` normalization (mock returns the bash-style duplicated envelope; assert output has exactly one `task` key and no top-level `id`), `begin --quiet` prints bare integer, `complete` already-closed guard (mock GET returns `state_id: 3`; assert exit 0 + `"already_closed"`; assert only ONE request reached the server), `annotate` failure writes the queue line (point HOME at a tempdir; mock 500×4; assert file content + exit 1).

- [ ] **Step 2: Implement the module.** Shape:

```rust
use clap::Subcommand;

#[derive(Subcommand)]
pub enum TasksCmd {
    List { #[arg(short, long)] session: Option<String>, /* ...all flags... */ },
    Get { id: String },
    // ... one variant per subcommand, flags mirroring bash help exactly
}

pub fn run(client: &crate::http::Client, cfg: &crate::config::Config,
           cmd: TasksCmd, pretty: bool, quiet: bool) -> Result<(), crate::error::EitsError> {
    match cmd {
        TasksCmd::Get { id } => {
            let v = client.get(&format!("/tasks/{id}"))?;
            let task = v.get("task").cloned().unwrap_or(v);
            crate::output::print_json(&serde_json::json!({"task": task}), pretty);
            Ok(())
        }
        // ...
    }
}
```

- [ ] **Step 3: Run all tests, fix, verify against live dev server manually:**

```bash
cargo run -p eits-cli -- tasks get 8051          # compare with: eits tasks get 8051
cargo run -p eits-cli -- tasks list --all | head -2
```

- [ ] **Step 4: fmt/clippy/commit** — `git commit -m "feat(eitsr): tasks family"`

---

### Task 7: notes + commits families

**Files:** `crates/eits-cli/src/commands/notes.rs`, `crates/eits-cli/src/commands/commits.rs`, main dispatch, contract tests.

**Interfaces:** same `run(...)` shape as tasks. Notes normalize lists from `.results // .notes`; commits list supports `--since-time <dur>` → `since_time=<iso>` query param and `--since <hash>`; `commits create --hash <h>` POST `/commits` — response `{errors,commits,duplicates}` normalizes to `{"status":"created","commits":[...]}` or `{"status":"already_tracked","duplicates":[...]}` (exit 0 both ways — idempotency envelope per spec). Quiet: notes → `/note/id` (verify response key live), commits create → first `/commits/0/id`, or with `already_tracked` print the existing record id from `duplicates[0]` if present else the input hash is NOT printed — use record id or omit quiet support if the API returns none (then `--quiet` is a usage error for commits create, matching the dm rule).

- [ ] Steps: failing contract tests (list normalization incl. `.results` key, `--since-time` query param assertion via mock request capture, `commits create` dup → `already_tracked` exit 0) → implement → live spot-check (`notes list --mine`, `commits list --since-time 24h`) → commit `feat(eitsr): notes + commits families`.

---

### Task 8: sessions family

**Files:** `crates/eits-cli/src/commands/sessions.rs`, main dispatch, contract tests.

**Interfaces:** `SessionsCmd: List, Get, Create, Update, End, Context`. Port flags from bash 340–730: list (`--search`, `--status`, `--project`, `--agent`, `--mine`, `--limit`, `--parent`, `--include-archived`, `--with-tasks`), get `<uuid>`, create (`--name`, `--description`, `--project-name`, `--model`, ...), update (`--status`, `--name`, `--intent`, ...), end (`--final-status`), context get/set (`--text`, `--metadata`). List normalizes `.results // .sessions` → `{"items","count"}`. Quiet: create → `/session/uuid`.

- [ ] Steps: failing tests (list normalization from both response keys; create quiet UUID) → implement → live spot-check (`sessions list --mine`) → commit `feat(eitsr): sessions family`.

---

### Task 9: dm family (with lock)

**Files:** `crates/eits-cli/src/commands/dm.rs`, main dispatch, contract tests.

**Interfaces:** `DmCmd: Inbox` (alias list; flags `--session`, `--from`, `--limit`, `--since`, `--since-session`, `--team-only`), `Read { id }`, `Send { to, message, from, metadata, response_required }` — send is the default when `--to/--message` given with no subcommand (match bash UX: `eitsr dm --to 123 --message hi`). Send: validate `--metadata` is parseable JSON (usage error otherwise, port bash line 2603 check), acquire `lock::DmLock` with `cfg.session_identity().unwrap_or("default")`, POST `/dm`, drop lock. Do NOT re-fetch the recipient for `to_name` (bash does; spec's terse contract drops it). `--quiet`: message id if response has one; else usage error (verify live which).

- [ ] Steps: failing tests (send holds lock — create the lock dir manually with 2-attempt override → expect `lock_timeout` envelope exit 1; inbox list normalization; bad `--metadata` → usage exit 2) → implement → live spot-check (`dm inbox --limit 2`) → commit `feat(eitsr): dm family with serialization lock`.

---

### Task 10: Usage-error JSON rendering + help goldens

**Files:** `crates/eits-cli/src/main.rs` (clap error interception), `crates/eits-cli/tests/contract.rs` (append), `crates/eits-cli/tests/goldens/{help_root.txt,help_tasks.txt,...}`

- [ ] **Step 1: Failing tests:**

```rust
#[test]
fn usage_error_is_json_envelope_exit_2() {
    let out = Command::cargo_bin("eitsr").unwrap()
        .args(["tasks", "get"]) // missing required id
        .assert().code(2);
    let stdout = String::from_utf8(out.get_output().stdout.clone()).unwrap();
    let v: serde_json::Value = serde_json::from_str(stdout.trim()).unwrap();
    assert_eq!(v["code"], "usage");
}

#[test]
fn help_is_human_text_exit_0() {
    Command::cargo_bin("eitsr").unwrap().args(["--help"]).assert().success()
        .stdout(predicates::str::contains("EITS CLI"));
}
```

- [ ] **Step 2: Implement:** in `main`, replace `Cli::parse()` with `Cli::try_parse()`; on `Err(e)`: if `e.kind()` is `DisplayHelp` or `DisplayVersion`, `e.exit()` (human text, exit 0); otherwise print `EitsError::usage(e.to_string().lines().next().unwrap_or("invalid arguments"))` envelope with `.with_hint("run `eitsr <cmd> --help`")` and exit 2.

- [ ] **Step 3: Goldens:** generate once (`cargo run -p eits-cli -- --help > tests/goldens/help_root.txt` and per Phase 1 family), add a test comparing current output to the files. Note in a comment: intentional clap upgrades update goldens in the same commit.

- [ ] **Step 4: Commit** — `git commit -m "feat(eitsr): JSON usage errors + help goldens"`

---

### Task 11: Live integration suite + parity check + docs

**Files:**
- Create: `crates/eits-cli/tests/live.rs` (all `#[ignore]`)
- Modify: `CLAUDE.md` (eitsr opt-in note), `docs/superpowers/specs/2026-07-04-eits-cli-rust-rewrite-design.md` (record any parity deviations found)

- [ ] **Step 1: Write `live.rs`** — `#[ignore]`d tests hitting the real dev server (skip cleanly when it's down): `whoami` matches `eits whoami` fields; `tasks get <known-id>` returns normalized single-`task` shape; `tasks begin --quiet` + `tasks complete` round-trip (creates + closes a real task titled "eitsr live test — safe to delete"); `dm inbox --limit 1` parses. Run: `cargo test -p eits-cli --test live -- --ignored`.

- [ ] **Step 2: Side-by-side parity sweep** — for each Phase 1 family run the bash and Rust versions of the read-only commands and diff the *data* (not shape — shapes intentionally differ): document in the spec's consumer-migration section anything that surfaced.

- [ ] **Step 3: CLAUDE.md note** — add under "EITS Command Protocol": `eitsr` is the Rust CLI (Phase 1: tasks/dm/sessions/whoami/commits/notes) with JSON-by-default output and `{"error","code","status","hint"}` errors on stdout; falls back to bash `eits` for everything else; agents may opt in per-session.

- [ ] **Step 4: Final check + commit**

```bash
cargo fmt -p eits-cli && cargo clippy -p eits-cli -- -D warnings && cargo test -p eits-cli
cargo check -p eye-in-the-sky   # workspace didn't break the Tauri app
git commit -m "feat(eitsr): live integration suite, parity notes, CLAUDE.md opt-in docs"
```
