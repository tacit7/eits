mod common;

use assert_cmd::Command;
use serde_json::Value;

fn report(
    responses: Vec<(u16, &'static str)>,
    args: &[&str],
    session: bool,
) -> (Value, Vec<common::Request>) {
    let srv = common::serve(responses);
    let dir = tempfile::tempdir().unwrap();
    let mut cmd = Command::cargo_bin("eits").unwrap();
    cmd.env_clear()
        .env("PATH", std::env::var_os("PATH").unwrap())
        .env("XDG_CONFIG_HOME", dir.path())
        .env("EITS_URL", &srv.url)
        .current_dir(dir.path());
    if session {
        cmd.env("EITS_SESSION_UUID", "s-1");
    }
    let out = cmd.args(args).assert().success();
    let value = serde_json::from_slice(&out.get_output().stdout).unwrap();
    (value, srv.finish())
}

const SESSION: &str = r#"{"uuid":"s-1","id":7,"agent_id":"a-1","agent_int_id":11,"project_id":9,"initialized":true,"started_at":"2026-09-25T00:00:00Z","worktree_path":"/tmp/registered"}"#;

#[test]
fn status_uses_session_start_and_reports_unread_limit_without_mutation() {
    let (v, reqs) = report(
        vec![
            (200, SESSION),
            (
                200,
                r#"{"tasks":[{"id":1,"state_id":2},{"id":2,"state_id":4},{"id":3,"state_id":1}]}"#,
            ),
            (200, r#"{"teams":[{"id":768}]}"#),
            (200, r#"{"messages":[{"id":12,"body":"hello"}]}"#),
        ],
        &["work", "status", "--quiet"],
        true,
    );
    assert!(reqs.iter().all(|r| r.method == "GET"));
    assert!(reqs[3].path.contains("since=2026-09-25T00%3A00%3A00Z"));
    assert_eq!(v["current_session"]["worktree_path"], "/tmp/registered");
    assert_eq!(v["health"]["registration"], "registered");
    assert_eq!(v["tasks"]["in_progress_count"], 1);
    assert_eq!(v["tasks"]["active_count"], 2);
    assert_eq!(v["tasks"]["count"], 3);
    assert_eq!(v["inbox"]["unread_count"], Value::Null);
    assert_eq!(v["inbox"]["unread_status"], "unsupported_by_api");
    assert_eq!(v["inbox"]["count"], 1);
}

#[test]
fn status_reports_malformed_collections_as_unavailable() {
    let (v, _) = report(
        vec![
            (200, SESSION),
            (200, r#"{"tasks":null}"#),
            (200, r#"{}"#),
            (200, r#"{"messages":"bad"}"#),
        ],
        &["work", "checkpoint"],
        true,
    );
    for section in ["tasks", "teams", "inbox"] {
        assert_eq!(v["health"][section], false, "{section}");
    }
    assert!(v["warnings"]
        .as_array()
        .unwrap()
        .iter()
        .any(|w| w.as_str().unwrap().contains("invalid response")));
}

#[test]
fn status_does_not_echo_server_error_secrets() {
    let (v, reqs) = report(
        vec![
            (401, r#"{"error":"sensitive-server-marker"}"#),
            (403, r#"{"error":"sensitive-server-marker"}"#),
            (403, r#"{"error":"sensitive-server-marker"}"#),
        ],
        &["workflow", "status"],
        true,
    );
    assert!(reqs.iter().all(|r| r.method == "GET"));
    assert!(!v.to_string().contains("sensitive-server-marker"));
    assert_eq!(v["health"]["session_resolved"], false);
}

#[test]
fn missing_identity_is_explicit_and_makes_no_api_requests() {
    let (v, reqs) = report(vec![], &["work", "status", "--pretty"], false);
    assert!(reqs.is_empty());
    assert_eq!(v["health"]["registration"], "missing_identity");
    assert!(v["warnings"]
        .as_array()
        .unwrap()
        .iter()
        .any(|w| w.as_str().unwrap().contains("missing session identity")));
}
