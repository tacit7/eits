mod common;
use assert_cmd::Command;
use serde_json::Value;

const SESSION: &str = r#"{"started_at":"2026-08-16T00:00:00Z"}"#;
const INBOX: &str = r#"{"messages":[{"message":"check reproduction"}]}"#;
const CLAIM: &str = r#"{"success":true,"task":{"id":42,"state_id":2}}"#;

fn start(url: &str) -> Command {
    let mut cmd = Command::cargo_bin("eits").unwrap();
    cmd.env_clear()
        .env("EITS_URL", url)
        .env("EITS_SESSION_UUID", "worker")
        .args(["workflow", "start-bug", "--task", "42"]);
    cmd
}

#[test]
fn claims_existing_task_between_visible_inbox_checks() {
    for session in [
        SESSION,
        r#"{"session":{"created_at":"2026-08-16T00:00:00Z"}}"#,
    ] {
        let srv = common::serve(vec![
            (200, session),
            (200, INBOX),
            (200, CLAIM),
            (200, INBOX),
        ]);
        let out = start(&srv.url).assert().success();
        let value: Value = serde_json::from_slice(&out.get_output().stdout).unwrap();
        assert_eq!(value["status"], "started");
        assert_eq!(value["task_id"], "42");
        assert_eq!(value["completed_steps"], serde_json::json!(["task_claim"]));
        assert_eq!(
            value["checkpoint"]["items"][0]["message"],
            "check reproduction"
        );
        assert_eq!(value["final_inbox"], value["checkpoint"]);
        assert_eq!(value["operations"][1], "eits tasks claim");
        let requests = srv.finish();
        assert_eq!(requests.len(), 4);
        assert_eq!(requests[0].path, "/api/v1/sessions/worker");
        assert!(requests[1].path.contains("since=2026-08-16T00%3A00%3A00Z"));
        assert_eq!(requests[2].method, "POST");
        assert_eq!(requests[2].path, "/api/v1/tasks/42/claim");
        let body: Value = serde_json::from_str(&requests[2].body).unwrap();
        assert_eq!(body, serde_json::json!({"session_id":"worker"}));
        assert_eq!(requests[3].path, requests[1].path);
    }
}

#[test]
fn failures_and_malformed_confirmations_stop_with_recovery_context() {
    let responses = [(200, SESSION), (200, INBOX), (200, CLAIM), (200, INBOX)];
    for (index, step) in ["session", "checkpoint", "task_claim", "final_inbox"]
        .iter()
        .enumerate()
    {
        for failure in [(403, r#"{"error":"denied"}"#), (200, "{}")] {
            let mut prefix = responses[..index].to_vec();
            prefix.push(failure);
            let srv = common::serve(prefix);
            let out = start(&srv.url).assert().failure();
            let value: Value = serde_json::from_slice(&out.get_output().stdout).unwrap();
            assert!(value["error"].as_str().unwrap().contains(step));
            assert!(value.get("status").and_then(Value::as_str) != Some("started"));
            assert!(value["hint"].as_str().unwrap().contains("eits tasks get"));
            if index == 3 {
                assert!(value["hint"]
                    .as_str()
                    .unwrap()
                    .contains("Confirmed steps: task_claim"));
            }
            assert_eq!(srv.finish().len(), index + 1);
        }
    }
}

#[test]
fn requires_explicit_task_and_session_before_requests() {
    for args in [
        vec!["workflow", "start-bug"],
        vec!["workflow", "start-bug", "--task", " "],
    ] {
        Command::cargo_bin("eits")
            .unwrap()
            .env_clear()
            .args(args)
            .assert()
            .code(2);
    }
    start("http://127.0.0.1:1/api/v1")
        .env_remove("EITS_SESSION_UUID")
        .assert()
        .failure()
        .stdout(predicates::str::contains("requires a session identity"));
}
