//! Live integration suite for `eits` against a real EITS dev server.
//!
//! Every test here is `#[ignore]`: they hit the network, mutate real data
//! (a throwaway task), and depend on env vars (`EITS_SESSION_UUID` /
//! `EITS_SESSION_ID`) that only exist in an agent session. Run explicitly:
//!
//! ```sh
//! cargo test -p eits-cli --test live -- --ignored
//! ```
//!
//! Each test probes the server with a raw TCP connect before doing anything
//! else, and skips (prints + returns `Ok`) rather than failing when the
//! server is unreachable, so this suite is safe to leave in CI defaults
//! (which never pass `--ignored`) and safe to run locally without a server.

use assert_cmd::Command;
use serde_json::Value;
use std::net::TcpStream;
use std::process::Command as StdCommand;
use std::time::Duration;

/// Resolve `host:port` the same way `Config::resolve` would for the
/// default case: `EITS_URL` env var if set, else `localhost:5001`.
fn server_addr() -> String {
    let url = std::env::var("EITS_URL").unwrap_or_else(|_| "http://localhost:5001".to_string());
    let without_scheme = url
        .trim_start_matches("http://")
        .trim_start_matches("https://");
    let host_port = without_scheme.split('/').next().unwrap_or(without_scheme);
    if host_port.contains(':') {
        host_port.to_string()
    } else {
        format!("{host_port}:5001")
    }
}

/// Returns `true` if a live server is reachable within a short timeout.
fn server_up() -> bool {
    let addr = server_addr();
    match addr.parse() {
        Ok(socket_addr) => {
            TcpStream::connect_timeout(&socket_addr, Duration::from_millis(500)).is_ok()
        }
        Err(_) => {
            // Hostname (not a bare IP:port) — fall back to the resolving connect.
            TcpStream::connect(&addr).is_ok()
        }
    }
}

macro_rules! skip_unless_live {
    () => {
        if !server_up() {
            eprintln!("live server unreachable at {} — skipping", server_addr());
            return;
        }
    };
}

fn run_eits(args: &[&str]) -> Value {
    let out = Command::cargo_bin("eits")
        .unwrap()
        .args(args)
        .assert()
        .success();
    let stdout = String::from_utf8(out.get_output().stdout.clone()).unwrap();
    serde_json::from_str(stdout.trim()).unwrap()
}

fn run_bash_eits(args: &[&str]) -> Value {
    let manifest_dir = env!("CARGO_MANIFEST_DIR");
    let repo_root = std::path::Path::new(manifest_dir)
        .parent()
        .and_then(|p| p.parent())
        .expect("crates/eits-cli is two levels below repo root");
    let out = StdCommand::new(repo_root.join("scripts/eits-extras"))
        .args(args)
        .current_dir(repo_root)
        .output()
        .expect("failed to run scripts/eits-extras");
    assert!(
        out.status.success(),
        "legacy eits extras {:?} failed: {}",
        args,
        String::from_utf8_lossy(&out.stderr)
    );
    serde_json::from_slice(&out.stdout).expect("legacy eits extras did not emit JSON on stdout")
}

/// `eits whoami` derives its fields from `GET /sessions/:id` + `/agents/:id`.
/// Legacy extras `whoami` is broken upstream (agent_id in the session response
/// is actually the session's own uuid, so the `/agents/:id` lookup 404s —
/// see scripts/eits-extras cmd_whoami and CLAUDE.md notes), so we cross-check
/// against `eits sessions get self` instead, which returns the same
/// underlying fields under different names.
#[test]
#[ignore]
fn whoami_matches_sessions_get_self_fields() {
    skip_unless_live!();
    let whoami = run_eits(&["whoami"]);
    let session = run_bash_eits(&["sessions", "get", "self", "--json"]);

    assert_eq!(whoami["session_uuid"], session["uuid"]);
    assert_eq!(whoami["session_id"], session["id"]);
    assert_eq!(whoami["project_id"], session["project_id"]);
    assert_eq!(whoami["agent_id"], session["agent_int_id"]);
}

/// `tasks get` on a real task returns the normalized single-`task` shape.
#[test]
#[ignore]
fn tasks_get_returns_normalized_task_shape() {
    skip_unless_live!();
    let known_task_id = std::env::var("EITSR_LIVE_TASK_ID").unwrap_or_else(|_| "8051".to_string());
    let resp = run_eits(&["tasks", "get", &known_task_id]);

    let task = resp
        .get("task")
        .unwrap_or_else(|| panic!("expected a top-level \"task\" key, got: {resp}"));
    assert!(task.get("id").is_some(), "task missing id: {task}");
    assert!(task.get("title").is_some(), "task missing title: {task}");
    assert!(task.get("state").is_some(), "task missing state: {task}");
}

/// `tasks begin --quiet` + `tasks complete` round-trips against the live
/// server: creates a real, throwaway task and immediately closes it.
#[test]
#[ignore]
fn tasks_begin_quiet_then_complete_round_trip() {
    skip_unless_live!();
    let out = Command::cargo_bin("eits")
        .unwrap()
        .args([
            "--quiet",
            "tasks",
            "begin",
            "--title",
            "eits live test — safe to delete",
        ])
        .assert()
        .success();
    let stdout = String::from_utf8(out.get_output().stdout.clone()).unwrap();
    let task_id: u64 = stdout.trim().parse().expect("expected a bare task id");
    assert!(task_id > 0);

    let complete = run_eits(&[
        "tasks",
        "complete",
        &task_id.to_string(),
        "--message",
        "eits live suite: closing throwaway task",
    ]);
    assert_eq!(
        complete["success"], true,
        "expected success: true: {complete}"
    );
    assert_eq!(
        complete["task"]["state"], "Done",
        "expected task closed to Done: {complete}"
    );
}

/// `dm inbox --limit 1` parses into the normalized `{items, count}` shape.
#[test]
#[ignore]
fn dm_inbox_limit_one_parses() {
    skip_unless_live!();
    let resp = run_eits(&["dm", "inbox", "--limit", "1"]);
    assert!(resp.get("count").is_some(), "missing count: {resp}");
    let items = resp["items"]
        .as_array()
        .unwrap_or_else(|| panic!("expected items array: {resp}"));
    assert!(items.len() <= 1);
}
