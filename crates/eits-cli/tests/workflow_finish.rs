mod common;
use assert_cmd::Command;
use serde_json::Value;

const SESSION: &str = r#"{"started_at":"2026-08-16T00:00:00Z"}"#;
const INBOX: &str = r#"{"messages":[],"count":0}"#;
const DONE: &str = r#"{"success":true}"#;
const SENT: &str = r#"{"message_id":12}"#;
fn finish(url: &str) -> Command {
    let mut cmd = Command::cargo_bin("eits").unwrap();
    cmd.env_clear()
        .env("EITS_URL", url)
        .env("EITS_SESSION_UUID", "worker")
        .env("EITS_AGENT_UUID", "agent")
        .args([
            "workflow", "finish", "--task", "42", "--result", "tested", "--parent", "7",
            "--branch", "feature",
        ]);
    cmd
}
#[test]
fn closes_and_notifies_with_two_inbox_polls() {
    let srv = common::serve(vec![
        (200, SESSION),
        (200, INBOX),
        (200, DONE),
        (201, SENT),
        (200, INBOX),
    ]);
    let out = finish(&srv.url).assert().success();
    let value: Value = serde_json::from_slice(&out.get_output().stdout).unwrap();
    assert_eq!(value["status"], "finished");
    let requests = srv.finish();
    assert!(requests[1].path.contains("since=2026-08-16T00%3A00%3A00Z"));
    assert_eq!(requests[2].path, "/api/v1/tasks/42/complete");
    let body: Value = serde_json::from_str(&requests[2].body).unwrap();
    assert_eq!(body["session_id"], "worker");
    assert_eq!(body["message"], "tested");
    let dm: Value = serde_json::from_str(&requests[3].body).unwrap();
    assert_eq!(
        dm["message"],
        "done task=42 result=tested branch=feature commit=none"
    );
    assert_eq!(dm["to_session_id"], "7");
    assert_eq!(requests[4].path, requests[1].path);
}
#[test]
fn each_failed_step_stops_without_success() {
    let steps = [
        "session",
        "checkpoint",
        "task_complete",
        "parent_dm",
        "final_inbox",
    ];
    let responses = [
        (200, SESSION),
        (200, INBOX),
        (200, DONE),
        (201, SENT),
        (200, INBOX),
    ];
    for (index, step) in steps.iter().enumerate() {
        let mut prefix = responses[..index].to_vec();
        prefix.push((403, r#"{"error":"denied"}"#));
        let srv = common::serve(prefix);
        let out = finish(&srv.url).assert().failure();
        let value: Value = serde_json::from_slice(&out.get_output().stdout).unwrap();
        assert!(value["error"].as_str().unwrap().contains(step));
        assert!(value.get("status").and_then(Value::as_str) != Some("finished"));
        assert_eq!(srv.finish().len(), index + 1);
    }
}
#[test]
fn commit_errors_prevent_task_completion() {
    let srv = common::serve(vec![
        (200, SESSION),
        (200, INBOX),
        (200, r#"{"commits":[{"id":1}],"link_errors":["failed"]}"#),
    ]);
    finish(&srv.url)
        .args(["--commit", "abc"])
        .assert()
        .failure();
    let requests = srv.finish();
    assert_eq!(requests[2].path, "/api/v1/commits");
}
#[test]
fn logs_commits_before_completion() {
    let srv = common::serve(vec![
        (200, SESSION),
        (200, INBOX),
        (201, r#"{"commits":[{"id":1}]}"#),
        (200, DONE),
        (201, SENT),
        (200, INBOX),
    ]);
    finish(&srv.url)
        .args(["--commit", "abc", "--checks-reminder", "Run focused tests"])
        .assert()
        .success();
    let requests = srv.finish();
    let body: Value = serde_json::from_str(&requests[2].body).unwrap();
    assert_eq!(body["commit_hashes"][0], "abc");
    assert_eq!(body["task_ids"][0], "42");
    let dm: Value = serde_json::from_str(&requests[4].body).unwrap();
    assert!(dm["message"].as_str().unwrap().ends_with("commit=abc"));
}

#[test]
fn malformed_confirmations_do_not_claim_success() {
    let responses = [
        (200, SESSION),
        (200, INBOX),
        (200, DONE),
        (201, SENT),
        (200, INBOX),
    ];
    for index in 0..responses.len() {
        let mut prefix = responses[..index].to_vec();
        prefix.push((200, "{}"));
        let srv = common::serve(prefix);
        let out = finish(&srv.url).assert().failure();
        let value: Value = serde_json::from_slice(&out.get_output().stdout).unwrap();
        assert!(value.get("error").is_some());
        if index == 4 {
            assert!(value["hint"].as_str().unwrap().contains("parent_dm"));
        }
        assert_eq!(srv.finish().len(), index + 1);
    }
}

#[test]
fn explicit_nonblank_inputs_are_required() {
    for args in [
        vec!["workflow", "finish"],
        vec![
            "workflow", "finish", "--task", "42", "--result", "done", "--parent", "7",
        ],
        vec![
            "workflow", "finish", "--task", "42", "--result", " ", "--parent", "7", "--branch",
            "feature",
        ],
    ] {
        Command::cargo_bin("eits")
            .unwrap()
            .env_clear()
            .env("EITS_URL", "http://127.0.0.1:1/api/v1")
            .args(args)
            .assert()
            .code(2);
    }
}

#[test]
fn duplicate_commits_are_valid_but_unconfirmed_batches_fail() {
    for (body, success) in [
        (r#"{"duplicates":[{"commit_hash":"abc"}]}"#, true),
        (r#"{"commits":[],"errors":[]}"#, false),
        (r#"{"commits":[{"id":1}],"errors":["failed"]}"#, false),
    ] {
        let mut responses = vec![(200, SESSION), (200, INBOX), (200, body)];
        if success {
            responses.extend([(200, DONE), (201, SENT), (200, INBOX)]);
        }
        let srv = common::serve(responses);
        let out = finish(&srv.url).args(["--commit", "abc"]).assert();
        if success {
            out.success();
        } else {
            out.failure();
        }
        assert_eq!(srv.finish().len(), if success { 6 } else { 3 });
    }
}
