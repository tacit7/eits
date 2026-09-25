mod common;

use assert_cmd::Command;
use predicates::str::contains;
use serde_json::{json, Value};

fn complete(url: &str) -> Command {
    let mut cmd = Command::cargo_bin("eits").unwrap();
    cmd.env_clear()
        .env("EITS_URL", url)
        .env("EITS_SESSION_UUID", "session-1")
        .env("EITS_AGENT_UUID", "agent-1")
        .args(["tasks", "complete", "42", "--message", "done"]);
    cmd
}

const OPEN: &str = r#"{"task":{"id":42,"state_id":2}}"#;
const DONE: &str = r#"{"success":true,"task_id":42}"#;
const TRACKED: &str = r#"{"commits":[{"commit_hash":"good"}],"errors":[],"link_errors":[]}"#;

#[test]
fn commit_is_optional() {
    let srv = common::serve(vec![(200, OPEN), (200, DONE)]);
    complete(&srv.url).assert().success().stderr("");
    let requests = srv.finish();
    assert_eq!(requests.len(), 2);
    assert!(requests[1].path.ends_with("/tasks/42/complete"));
    let body: Value = serde_json::from_str(&requests[1].body).unwrap();
    assert_eq!(body, json!({"message": "done", "session_id": "session-1"}));
}

#[test]
fn repeated_commits_link_each_hash_to_task_and_session() {
    let srv = common::serve(vec![
        (200, OPEN),
        (200, DONE),
        (201, TRACKED),
        (201, TRACKED),
    ]);
    complete(&srv.url)
        .args(["--commit", "first", "--commit", "second"])
        .assert()
        .success()
        .stderr("");
    let requests = srv.finish();
    assert_eq!(requests.len(), 4);
    for (request, hash) in requests[2..].iter().zip(["first", "second"]) {
        assert_eq!(request.method, "POST");
        assert!(request.path.ends_with("/commits"));
        let body: Value = serde_json::from_str(&request.body).unwrap();
        assert_eq!(
            body,
            json!({"commit_hashes": [hash], "task_ids": ["42"],
            "session_id": "session-1", "agent_id": "agent-1"})
        );
    }
}

#[test]
fn http_failure_warns_and_still_tracks_remaining_commits() {
    let srv = common::serve(vec![
        (200, OPEN),
        (200, DONE),
        (422, r#"{"error":"invalid hash"}"#),
        (201, TRACKED),
    ]);
    let result = complete(&srv.url)
        .args(["--commit", "bad", "--commit", "good"])
        .assert()
        .success()
        .stderr(contains("task closed but commit bad could not be tracked"));
    let output: Value = serde_json::from_slice(&result.get_output().stdout).unwrap();
    assert_eq!(output, json!({"success": true, "task_id": 42}));
    assert_eq!(srv.finish().len(), 4);
}

#[test]
fn successful_http_response_warns_on_commit_creation_errors() {
    let srv = common::serve(vec![
        (200, OPEN),
        (200, DONE),
        (
            207,
            r#"{"commits":[],"errors":[{"hash":"bad","error":"invalid hash"}],"link_errors":[]}"#,
        ),
    ]);
    complete(&srv.url)
        .args(["--commit", "bad"])
        .assert()
        .success()
        .stderr(contains("task closed but commit bad could not be tracked"))
        .stderr(contains("invalid hash"));
    assert_eq!(srv.finish().len(), 3);
}

#[test]
fn successful_http_response_warns_when_created_commit_cannot_link_to_task() {
    let srv = common::serve(vec![
        (200, OPEN),
        (200, DONE),
        (
            207,
            r#"{"commits":[{"commit_hash":"good"}],"errors":[],"link_errors":[{"task_id":42,"error":"link failed"}]}"#,
        ),
    ]);
    complete(&srv.url)
        .args(["--commit", "good", "--quiet"])
        .assert()
        .success()
        .stdout("42\n")
        .stderr(contains("task closed but commit good could not be linked"))
        .stderr(contains("link failed"));
    assert_eq!(srv.finish().len(), 3);
}
