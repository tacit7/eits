mod common;
use assert_cmd::Command;

fn command(url: &str) -> Command {
    let mut cmd = Command::cargo_bin("eits").unwrap();
    cmd.env_clear()
        .env("PATH", std::env::var("PATH").unwrap_or_default())
        .env("EITS_URL", url)
        .env("EITS_SESSION_UUID", "watch-session")
        .env("EITS_RETRY", "0")
        .timeout(std::time::Duration::from_secs(10));
    cmd
}

#[test]
fn watch_exposes_stream_options() {
    command("http://127.0.0.1:1/api/v1")
        .args(["dm", "watch", "--help"])
        .assert()
        .success()
        .stdout(predicates::str::contains("--since-session"))
        .stdout(predicates::str::contains("--team-only"))
        .stdout(predicates::str::contains("--format"));
}

#[test]
fn watch_does_not_swallow_session_auth_failure() {
    let srv = common::serve(vec![(401, r#"{"error":"unauthorized"}"#)]);
    command(&srv.url)
        .args(["dm", "watch", "--since-session"])
        .assert()
        .code(1)
        .stdout(predicates::str::contains("unauthorized"));
    assert_eq!(srv.finish().len(), 1);
}

#[test]
fn reconnect_retains_equal_timestamp_cursor_and_deduplicates() {
    let srv = common::serve(vec![
        (
            200,
            r#"{"watch_cursor":true,"items":[{"id":10,"inserted_at":"2026-01-01T00:00:00.000000Z"}]}"#,
        ),
        (503, r#"{"error":"restart"}"#),
        (
            200,
            r#"{"watch_cursor":true,"items":[{"id":10,"inserted_at":"2026-01-01T00:00:00.000000Z"},{"id":11,"inserted_at":"2026-01-01T00:00:00.000000Z"}]}"#,
        ),
        (401, r#"{"error":"unauthorized"}"#),
    ]);
    let result = command(&srv.url)
        .args(["dm", "watch", "--since", "2025-12-31T18:00:00-06:00"])
        .assert()
        .code(1);
    let lines: Vec<serde_json::Value> = String::from_utf8(result.get_output().stdout.clone())
        .unwrap()
        .lines()
        .map(|line| serde_json::from_str(line).unwrap())
        .collect();
    assert_eq!(lines.len(), 3);
    assert_eq!(lines[0]["id"], 10);
    assert_eq!(lines[1]["id"], 11);
    assert_eq!(lines[2]["code"], "unauthorized");
    let requests = srv.finish();
    assert_eq!(requests[1].path, requests[2].path);
    assert!(requests[1].path.contains("after_id=10"));
    assert!(requests[3].path.contains("after_id=11"));
}

#[test]
fn default_session_cutoff_and_team_filter_advance_past_outsiders() {
    let srv = common::serve(vec![
        (200, r#"{"started_at":"2026-01-01T00:00:00Z"}"#),
        (200, r#"{"teams":[{"id":7}]}"#),
        (200, r#"{"members":[{"session_id":22}]}"#),
        (
            200,
            r#"{"watch_cursor":true,"items":[{"id":10,"from_session_id":33,"inserted_at":"2026-01-01T00:00:01.000000Z"}]}"#,
        ),
        (
            200,
            r#"{"watch_cursor":true,"items":[{"id":11,"from_session_id":22,"inserted_at":"2026-01-01T00:00:01.000000Z"}]}"#,
        ),
        (403, r#"{"error":"forbidden"}"#),
    ]);
    let result = command(&srv.url)
        .env("EITS_AGENT_UUID", "agent-test")
        .args(["dm", "watch", "--team-only", "--format", "json"])
        .assert()
        .code(1);
    let lines: Vec<serde_json::Value> = String::from_utf8(result.get_output().stdout.clone())
        .unwrap()
        .lines()
        .map(|line| serde_json::from_str(line).unwrap())
        .collect();
    assert_eq!(lines.len(), 2);
    assert_eq!(lines[0]["count"], 1);
    assert_eq!(lines[0]["items"][0]["id"], 11);
    let requests = srv.finish();
    assert_eq!(requests[0].path, "/api/v1/sessions/watch-session");
    assert!(requests[3].path.contains("since=2026-01-01T00%3A00%3A00Z"));
    assert!(requests[4].path.contains("after_id=10"));
}

#[test]
fn empty_and_duplicate_responses_do_not_spin_or_regress() {
    let srv = common::serve(vec![
        (
            200,
            r#"{"watch_cursor":true,"items":[{"id":10,"inserted_at":"2026-01-01T00:00:01.000000Z"}]}"#,
        ),
        (200, r#"{"watch_cursor":true,"items":[]}"#),
        (
            200,
            r#"{"watch_cursor":true,"items":[{"id":9,"inserted_at":"2026-01-01T00:00:00.000000Z"}]}"#,
        ),
        (400, r#"{"error":"invalid request"}"#),
    ]);
    let started = std::time::Instant::now();
    command(&srv.url)
        .args(["dm", "watch", "--since", "2026-01-01T00:00:00Z"])
        .assert()
        .code(1);
    assert!(started.elapsed() >= std::time::Duration::from_secs(2));
    let requests = srv.finish();
    assert_eq!(requests[1].path, requests[2].path);
    assert_eq!(requests[2].path, requests[3].path);
}

#[test]
fn old_servers_and_missing_cutoffs_fail_closed() {
    for response in [r#"{"items":[],"count":0}"#, r#"{"session":{}}"#] {
        let srv = common::serve(vec![(200, response)]);
        let mut cmd = command(&srv.url);
        cmd.args(["dm", "watch"]);
        if response.contains("items") {
            cmd.args(["--since", "2026-01-01T00:00:00Z"]);
        }
        cmd.assert().code(2);
        assert_eq!(srv.finish().len(), 1);
    }
}

#[test]
fn team_auth_errors_are_not_downgraded_to_empty_membership() {
    let srv = common::serve(vec![(403, r#"{"error":"forbidden"}"#)]);
    command(&srv.url)
        .env("EITS_AGENT_UUID", "agent-test")
        .args([
            "dm",
            "watch",
            "--since",
            "2026-01-01T00:00:00Z",
            "--team-only",
        ])
        .assert()
        .code(1);
    assert_eq!(srv.finish().len(), 1);
}

#[test]
fn rejects_zero_timeout_and_invalid_url_before_polling() {
    command("http://127.0.0.1:1/api/v1")
        .args(["dm", "watch", "--timeout", "0"])
        .assert()
        .code(2);
    command("not-a-url")
        .args(["dm", "watch", "--since", "2026-01-01T00:00:00Z"])
        .assert()
        .code(2);
}

#[test]
fn malformed_cursor_data_fails_instead_of_replaying_forever() {
    for response in [
        r#"{"watch_cursor":true,"items":[{"id":10}]}"#,
        r#"{"watch_cursor":true,"items":[{"inserted_at":"2026-01-01T00:00:00.000000Z"}]}"#,
        r#"{"watch_cursor":true,"items":[{"id":10,"inserted_at":"2026-01-01T00:00:00-06:00"}]}"#,
        r#"{"watch_cursor":true}"#,
    ] {
        let srv = common::serve(vec![(200, response)]);
        command(&srv.url)
            .args(["dm", "watch", "--since", "2026-01-01T00:00:00Z"])
            .assert()
            .code(2);
        assert_eq!(srv.finish().len(), 1);
    }
}
