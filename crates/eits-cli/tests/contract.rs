mod common;
use assert_cmd::Command;

#[test]
fn get_maps_404_to_envelope_on_stdout_exit_1() {
    let srv = common::serve(vec![(404, r#"{"error":"Task not found"}"#)]);
    let out = Command::cargo_bin("eitsr")
        .unwrap()
        .env("EITS_URL", &srv.url)
        .args(["tasks", "get", "999"])
        .assert()
        .code(1);
    let stdout = String::from_utf8(out.get_output().stdout.clone()).unwrap();
    let v: serde_json::Value = serde_json::from_str(stdout.trim()).unwrap(); // stdout is pure JSON
    assert_eq!(v["code"], "not_found");
    assert_eq!(v["status"], 404);
    let stderr = String::from_utf8(out.get_output().stderr.clone()).unwrap();
    assert!(
        stderr.is_empty(),
        "stderr must be empty on permanent errors: {stderr}"
    );
}

#[test]
fn retries_503_then_succeeds_chatter_on_stderr_only() {
    let srv = common::serve(vec![
        (503, "{}"),
        (200, r#"{"task":{"id":1,"title":"t","state":"Done"}}"#),
    ]);
    let out = Command::cargo_bin("eitsr")
        .unwrap()
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
    Command::cargo_bin("eitsr")
        .unwrap()
        .env("EITS_URL", &srv.url)
        .env("EITS_SESSION_UUID", "u-123")
        .env("EITS_API_KEY", "k")
        .args(["tasks", "get", "1"])
        .assert()
        .success();
    let reqs = srv.finish();
    let h = &reqs[0].headers;
    assert!(h.iter().any(|(k, v)| k == "x-eits-session" && v == "u-123"));
    assert!(h
        .iter()
        .any(|(k, v)| k == "x-eits-role" && v == "orchestrator"));
    assert!(h
        .iter()
        .any(|(k, v)| k == "authorization" && v == "Bearer k"));

    let srv2 = common::serve(vec![(200, r#"{"task":{"id":1}}"#)]);
    Command::cargo_bin("eitsr")
        .unwrap()
        .env("EITS_URL", &srv2.url)
        .env_remove("EITS_SESSION_UUID")
        .env_remove("EITS_API_KEY")
        .env("EITS_SESSION_ID", "7") // integer-only: NO headers
        .args(["tasks", "get", "1"])
        .assert()
        .success();
    let reqs2 = srv2.finish();
    assert!(!reqs2[0]
        .headers
        .iter()
        .any(|(k, _)| k == "x-eits-session" || k == "authorization" || k == "x-eits-role"));
}

#[test]
fn get_normalizes_bash_style_duplicated_envelope_to_single_task_key() {
    // Bash-style response duplicates task fields at the top level alongside
    // the nested "task" object; our normalization keeps only the nested one.
    let srv = common::serve(vec![(
        200,
        r#"{"task":{"id":5,"title":"x"},"id":5,"title":"x"}"#,
    )]);
    let out = Command::cargo_bin("eitsr")
        .unwrap()
        .env("EITS_URL", &srv.url)
        .args(["tasks", "get", "5"])
        .assert()
        .success();
    let stdout = String::from_utf8(out.get_output().stdout.clone()).unwrap();
    let v: serde_json::Value = serde_json::from_str(stdout.trim()).unwrap();
    let obj = v.as_object().unwrap();
    assert_eq!(obj.len(), 1, "expected exactly one top-level key: {v}");
    assert!(obj.contains_key("task"));
    assert!(v.get("id").is_none(), "no top-level id: {v}");
}

#[test]
fn begin_quiet_prints_bare_task_id() {
    let srv = common::serve(vec![
        (200, r#"{"task_id":42}"#),
        (200, r#"{"task":{"id":42,"state":"In Progress"}}"#),
    ]);
    let out = Command::cargo_bin("eitsr")
        .unwrap()
        .env("EITS_URL", &srv.url)
        .env_remove("EITS_SESSION_UUID")
        .env_remove("EITS_SESSION_ID")
        .args(["--quiet", "tasks", "begin", "--title", "Do the thing"])
        .assert()
        .success();
    let stdout = String::from_utf8(out.get_output().stdout.clone()).unwrap();
    assert_eq!(stdout.trim(), "42");
}

#[test]
fn complete_already_done_short_circuits_with_single_request() {
    let srv = common::serve(vec![(200, r#"{"task":{"state_id":3}}"#)]);
    let out = Command::cargo_bin("eitsr")
        .unwrap()
        .env("EITS_URL", &srv.url)
        .args(["tasks", "complete", "5", "--message", "done"])
        .assert()
        .success();
    let stdout = String::from_utf8(out.get_output().stdout.clone()).unwrap();
    let v: serde_json::Value = serde_json::from_str(stdout.trim()).unwrap();
    assert_eq!(v["status"], "already_closed");
    assert_eq!(v["task_id"], 5);
    let reqs = srv.finish();
    assert_eq!(reqs.len(), 1, "must not POST /complete once already Done");
    assert_eq!(reqs[0].method, "GET");
}

#[test]
fn annotate_failure_after_retries_queues_pending_annotation() {
    let home = tempfile::tempdir().unwrap();
    let srv = common::serve(vec![(500, "{}")]);
    Command::cargo_bin("eitsr")
        .unwrap()
        .env("EITS_URL", &srv.url)
        .env("EITS_RETRY_BASE_MS", "10")
        .env("HOME", home.path())
        .args(["tasks", "annotate", "9", "--body", "hello"])
        .assert()
        .code(1)
        .stderr(predicates::str::contains("queued"));
    let log_path = home.path().join(".eits").join("pending-annotations.log");
    let content = std::fs::read_to_string(&log_path).unwrap();
    let line: serde_json::Value = serde_json::from_str(content.trim()).unwrap();
    assert_eq!(line["task_id"], "9");
    assert_eq!(line["body"], "hello");
    assert_eq!(line["title"], "");
}

#[test]
fn connection_refused_exits_3() {
    Command::cargo_bin("eitsr")
        .unwrap()
        .env("EITS_URL", "http://127.0.0.1:1/api/v1")
        .env("EITS_RETRY_BASE_MS", "10")
        .args(["tasks", "get", "1"])
        .assert()
        .code(3)
        .stdout(predicates::str::contains("\"code\":\"connection_failed\""));
}

#[test]
fn notes_list_normalizes_results_key() {
    let srv = common::serve(vec![(
        200,
        r#"{"success":true,"results":[{"id":1,"title":"a"},{"id":2,"title":"b"}]}"#,
    )]);
    let out = Command::cargo_bin("eitsr")
        .unwrap()
        .env("EITS_URL", &srv.url)
        .env_remove("EITS_SESSION_UUID")
        .env_remove("EITS_SESSION_ID")
        .args(["notes", "list"])
        .assert()
        .success();
    let stdout = String::from_utf8(out.get_output().stdout.clone()).unwrap();
    let v: serde_json::Value = serde_json::from_str(stdout.trim()).unwrap();
    assert_eq!(v["count"], 2);
    assert_eq!(v["items"].as_array().unwrap().len(), 2);
}

#[test]
fn commits_list_since_time_sends_iso_query_param() {
    let srv = common::serve(vec![(200, r#"{"commits":[]}"#)]);
    Command::cargo_bin("eitsr")
        .unwrap()
        .env("EITS_URL", &srv.url)
        .args(["commits", "list", "--since-time", "24h"])
        .assert()
        .success();
    let reqs = srv.finish();
    assert!(
        reqs[0].path.contains("since_time="),
        "expected since_time param in path: {}",
        reqs[0].path
    );
}

#[test]
fn commits_create_duplicate_reports_already_tracked_exit_0() {
    let srv = common::serve(vec![(
        200,
        r#"{"commits":[],"duplicates":[{"commit_hash":"abc123","status":"duplicate"}],"errors":[],"already_tracked":true}"#,
    )]);
    let out = Command::cargo_bin("eitsr")
        .unwrap()
        .env("EITS_URL", &srv.url)
        .args([
            "commits", "create", "--agent", "agent-1", "--hash", "abc123",
        ])
        .assert()
        .success();
    let stdout = String::from_utf8(out.get_output().stdout.clone()).unwrap();
    let v: serde_json::Value = serde_json::from_str(stdout.trim()).unwrap();
    assert_eq!(v["status"], "already_tracked");
    assert_eq!(v["duplicates"][0]["commit_hash"], "abc123");
}

#[test]
fn notes_add_quiet_prints_bare_id() {
    let srv = common::serve(vec![(
        200,
        r#"{"id":7,"parent_type":"session","parent_id":"s-1","title":"","body":"hi","starred":false}"#,
    )]);
    let out = Command::cargo_bin("eitsr")
        .unwrap()
        .env("EITS_URL", &srv.url)
        .env("EITS_SESSION_UUID", "s-1")
        .args(["--quiet", "notes", "add", "--body", "hi"])
        .assert()
        .success();
    let stdout = String::from_utf8(out.get_output().stdout.clone()).unwrap();
    assert_eq!(stdout.trim(), "7");
}
