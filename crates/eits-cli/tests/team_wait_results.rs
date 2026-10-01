mod common;

use serde_json::{json, Value};

const DONE: &str = r#"{"id":42,"name":"review","members":[{"id":7,"name":"worker","role":"member","member_status":"done","session_status":"completed","session_id":99,"session_uuid":"worker-uuid","git_worktree_path":"/tmp/not-the-branch","claimed_task":null}]}"#;
const DETAIL: &str = r#"{"branch_name":"codex/actual-branch","tasks":[{"id":123,"state_id":3},{"id":124,"state_id":4}]}"#;
const ACTIVE: &str = r#"{"id":42,"name":"review","members":[{"id":7,"name":"worker","member_status":"active","session_status":"working","session_id":99,"session_uuid":"worker-uuid"}]}"#;

fn run(
    responses: Vec<(u16, &'static str)>,
    flags: &[&str],
) -> (std::process::Output, common::MockServer) {
    let server = common::serve(responses);
    let output = assert_cmd::Command::cargo_bin("eits")
        .unwrap()
        .env(
            "EITS_EXTRAS",
            concat!(env!("CARGO_MANIFEST_DIR"), "/../../scripts/eits-extras"),
        )
        .env("EITS_URL", &server.url)
        .env("EITS_API_KEY", "")
        .env("EITS_SESSION_UUID", "")
        .env("EITS_COMPACT", "1")
        .args(["teams", "status", "42"])
        .args(flags)
        .timeout(std::time::Duration::from_secs(15))
        .output()
        .unwrap();
    (output, server)
}

#[test]
fn wait_returns_completed_tasks_and_real_branch_as_one_json_document() {
    let (output, server) = run(vec![(200, DONE), (200, DETAIL)], &["--wait"]);
    assert!(output.status.success());
    let result: Value = serde_json::from_slice(&output.stdout).expect("wait stdout must be JSON");
    assert_eq!(result["status"], "done");
    assert_eq!(result["team_id"], 42);
    assert_eq!(result["results"][0]["branch"], "codex/actual-branch");
    assert_eq!(result["results"][0]["task_ids"], json!([123, 124]));
    assert_eq!(result["results"][0]["status"], "done");
    assert_eq!(result["results"][0]["session_status"], "completed");
    assert_eq!(String::from_utf8_lossy(&output.stdout).lines().count(), 1);
    let requests = server.finish();
    assert_eq!(requests[1].path, "/api/v1/sessions/worker-uuid");
    assert!(requests.iter().all(|r| r.method == "GET"));
}

#[test]
fn json_flag_waits_until_settled() {
    let (output, server) = run(
        vec![
            (200, ACTIVE),
            (200, r#"{"hung":false}"#),
            (200, DONE),
            (200, DETAIL),
        ],
        &["--wait", "--json"],
    );
    assert!(output.status.success());
    let result: Value = serde_json::from_slice(&output.stdout).unwrap();
    assert_eq!(result["results"][0]["status"], "done");
    assert_eq!(server.finish().len(), 4);
}

#[test]
fn spawn_failure_without_session_preserves_exit_one_and_null_metadata() {
    let (output, server) = run(
        vec![(
            200,
            r#"{"id":42,"members":[{"id":8,"name":"failed","member_status":"spawn_failed"}]}"#,
        )],
        &["--wait", "--json"],
    );
    assert_eq!(output.status.code(), Some(1));
    let result: Value = serde_json::from_slice(&output.stdout).unwrap();
    assert_eq!(result["status"], "spawn_failed");
    assert_eq!(result["results"][0]["branch"], Value::Null);
    assert_eq!(result["results"][0]["task_ids"], json!([]));
    server.finish();
}

#[test]
fn hung_worker_preserves_exit_two_and_returns_results() {
    let (output, server) = run(
        vec![(200, ACTIVE), (200, r#"{"hung":true}"#), (200, DETAIL)],
        &["--wait"],
    );
    assert_eq!(output.status.code(), Some(2));
    let result: Value = serde_json::from_slice(&output.stdout).unwrap();
    assert_eq!(result["status"], "hung");
    assert_eq!(result["results"][0]["status"], "active");
    assert_eq!(result["hung_members"], json!(["worker"]));
    server.finish();
}

#[test]
fn unavailable_metadata_is_explicit_without_changing_completion_exit() {
    let (output, server) = run(
        vec![(200, DONE), (404, r#"{"error":"not found"}"#)],
        &["--wait"],
    );
    assert!(output.status.success());
    let result: Value = serde_json::from_slice(&output.stdout).unwrap();
    assert_eq!(
        result["results"][0]["metadata_error"],
        "session details unavailable"
    );
    assert_eq!(result["results"][0]["branch"], Value::Null);
    server.finish();
}

#[test]
fn plain_json_status_remains_raw_team_snapshot() {
    let (output, server) = run(vec![(200, ACTIVE)], &["--json"]);
    assert!(output.status.success());
    let result: Value = serde_json::from_slice(&output.stdout).unwrap();
    assert_eq!(result, serde_json::from_str::<Value>(ACTIVE).unwrap());
    server.finish();
}

#[test]
fn empty_team_returns_empty_results() {
    let (output, server) = run(
        vec![(200, r#"{"id":42,"name":"empty","members":[]}"#)],
        &["--wait"],
    );
    assert!(output.status.success());
    let result: Value = serde_json::from_slice(&output.stdout).unwrap();
    assert_eq!(result["status"], "done");
    assert_eq!(result["results"], json!([]));
    server.finish();
}

#[test]
fn permanent_team_error_keeps_exit_one_and_diagnostics_off_stdout() {
    let (output, server) = run(
        vec![(403, r#"{"error":"forbidden"}"#)],
        &["--wait", "--json"],
    );
    assert_eq!(output.status.code(), Some(1));
    assert!(output.stdout.is_empty());
    assert!(String::from_utf8_lossy(&output.stderr).contains("permanent error (HTTP 403)"));
    server.finish();
}
