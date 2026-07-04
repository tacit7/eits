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
