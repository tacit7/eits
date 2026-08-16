mod common;
use assert_cmd::Command;

fn scrub_codex_identity(cmd: &mut Command) -> &mut Command {
    cmd.env_remove("EITS_CODEX_ENV_FILE")
        .env_remove("EITS_CODEX_SESSION_ID")
        .env_remove("CODEX_THREAD_ID")
        .env_remove("CODEX_SESSION_ID")
}

#[test]
fn usage_error_is_json_envelope_exit_2() {
    let out = Command::cargo_bin("eits")
        .unwrap()
        .args(["tasks", "get"]) // missing required id
        .assert()
        .code(2);
    let stdout = String::from_utf8(out.get_output().stdout.clone()).unwrap();
    let v: serde_json::Value = serde_json::from_str(stdout.trim()).unwrap();
    assert_eq!(v["code"], "usage");
}

#[test]
fn help_is_human_text_exit_0() {
    Command::cargo_bin("eits")
        .unwrap()
        .args(["--help"])
        .assert()
        .success()
        .stdout(predicates::str::contains("EITS CLI"));
}

#[test]
fn bare_invocation_is_json_usage_envelope_exit_2() {
    let out = Command::cargo_bin("eits").unwrap().assert().code(2);
    let stdout = String::from_utf8(out.get_output().stdout.clone()).unwrap();
    let v: serde_json::Value = serde_json::from_str(stdout.trim()).unwrap();
    assert_eq!(v["code"], "usage");
}

#[test]
fn unknown_global_flag_before_known_subcommand_is_usage_exit_2() {
    let out = Command::cargo_bin("eits")
        .unwrap()
        .args(["--bogus", "tasks", "list"])
        .assert()
        .code(2);
    let stdout = String::from_utf8(out.get_output().stdout.clone()).unwrap();
    let v: serde_json::Value = serde_json::from_str(stdout.trim()).unwrap();
    assert_eq!(v["code"], "usage");
}

// Intentional clap upgrades that change help text should update these golden
// files in the same commit as the upgrade.
#[test]
fn help_output_matches_goldens() {
    let cases: &[(&[&str], &str)] = &[
        (&["--help"], "help_root.txt"),
        (&["tasks", "--help"], "help_tasks.txt"),
        (&["dm", "--help"], "help_dm.txt"),
        (&["sessions", "--help"], "help_sessions.txt"),
        (&["commits", "--help"], "help_commits.txt"),
        (&["notes", "--help"], "help_notes.txt"),
        (&["whoami", "--help"], "help_whoami.txt"),
        (&["work", "--help"], "help_work.txt"),
    ];
    for (args, golden) in cases {
        let out = Command::cargo_bin("eits")
            .unwrap()
            .args(*args)
            .assert()
            .success();
        let stdout = String::from_utf8(out.get_output().stdout.clone()).unwrap();
        let expected = std::fs::read_to_string(format!("tests/goldens/{golden}")).unwrap();
        assert_eq!(stdout, expected, "help output drifted for {golden}");
    }
}

#[test]
fn get_maps_404_to_envelope_on_stdout_exit_1() {
    let srv = common::serve(vec![(404, r#"{"error":"Task not found"}"#)]);
    let out = Command::cargo_bin("eits")
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
    let out = Command::cargo_bin("eits")
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
    Command::cargo_bin("eits")
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
    let mut cmd = Command::cargo_bin("eits").unwrap();
    scrub_codex_identity(&mut cmd)
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
    let out = Command::cargo_bin("eits")
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
    let out = Command::cargo_bin("eits")
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
fn begin_accepts_string_task_id_from_server() {
    // The server has been observed returning task_id as a numeric string
    // (e.g. `"task_id":"42"`) rather than a JSON number — must not blow up.
    let srv = common::serve(vec![
        (200, r#"{"task_id":"42"}"#),
        (200, r#"{"task":{"id":42,"state":"In Progress"}}"#),
    ]);
    let out = Command::cargo_bin("eits")
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
fn begin_sends_team_id_when_team_flag_is_present() {
    let srv = common::serve(vec![
        (200, r#"{"task_id":42}"#),
        (200, r#"{"task":{"id":42,"state":"In Progress"}}"#),
    ]);
    let out = Command::cargo_bin("eits")
        .unwrap()
        .env("EITS_URL", &srv.url)
        .env_remove("EITS_SESSION_UUID")
        .env_remove("EITS_SESSION_ID")
        .args([
            "--quiet",
            "tasks",
            "begin",
            "--title",
            "Team-scoped work",
            "--team",
            "720",
        ])
        .assert()
        .success();
    let stdout = String::from_utf8(out.get_output().stdout.clone()).unwrap();
    assert_eq!(stdout.trim(), "42");

    let reqs = srv.finish();
    let body: serde_json::Value = serde_json::from_str(&reqs[0].body).unwrap();
    assert_eq!(body["team_id"], "720");
}

#[test]
fn create_sends_team_id_when_team_flag_is_present() {
    let srv = common::serve(vec![(201, r#"{"success":true,"task_id":"42"}"#)]);
    let mut cmd = Command::cargo_bin("eits").unwrap();
    let out = scrub_codex_identity(&mut cmd)
        .env("EITS_URL", &srv.url)
        .env("EITS_PROJECT_ID", "7")
        .env("EITS_SESSION_ID", "99")
        .env_remove("EITS_SESSION_UUID")
        .args([
            "--quiet",
            "tasks",
            "create",
            "--title",
            "Assigned team task",
            "--team",
            "720",
        ])
        .assert()
        .success();
    let stdout = String::from_utf8(out.get_output().stdout.clone()).unwrap();
    assert_eq!(stdout.trim(), "42");

    let reqs = srv.finish();
    assert_eq!(reqs.len(), 1);
    assert_eq!(reqs[0].method, "POST");
    assert_eq!(reqs[0].path, "/api/v1/tasks");
    let body: serde_json::Value = serde_json::from_str(&reqs[0].body).unwrap();
    assert_eq!(body["title"], "Assigned team task");
    assert_eq!(body["team_id"], "720");
    assert_eq!(body["project_id"], "7");
    assert_eq!(body["session_id"], "99");
}

#[test]
fn claim_accepts_team_flag_without_changing_payload() {
    let srv = common::serve(vec![(200, r#"{"success":true,"task":{"id":9001}}"#)]);
    let out = Command::cargo_bin("eits")
        .unwrap()
        .env("EITS_URL", &srv.url)
        .env("EITS_SESSION_UUID", "s-1")
        .args(["tasks", "claim", "9001", "--team", "720"])
        .assert()
        .success();
    let stdout = String::from_utf8(out.get_output().stdout.clone()).unwrap();
    let v: serde_json::Value = serde_json::from_str(stdout.trim()).unwrap();
    assert_eq!(v["task"]["id"], 9001);

    let reqs = srv.finish();
    let body: serde_json::Value = serde_json::from_str(&reqs[0].body).unwrap();
    assert_eq!(body["session_id"], "s-1");
    assert!(body.get("team_id").is_none());
}

#[test]
fn tasks_list_team_sends_team_id_without_default_session_scope() {
    let srv = common::serve(vec![(
        200,
        r#"{"tasks":[{"id":8991,"title":"Fix rail","team_id":720,"session_ids":[6858]}]}"#,
    )]);
    let mut cmd = Command::cargo_bin("eits").unwrap();
    let out = scrub_codex_identity(&mut cmd)
        .env("EITS_URL", &srv.url)
        .env("EITS_SESSION_ID", "99")
        .env_remove("EITS_SESSION_UUID")
        .env_remove("EITS_PROJECT_ID")
        .args(["tasks", "list", "--team", "720"])
        .assert()
        .success();
    let stdout = String::from_utf8(out.get_output().stdout.clone()).unwrap();
    let v: serde_json::Value = serde_json::from_str(stdout.trim()).unwrap();
    assert_eq!(v["items"][0]["id"], 8991);
    assert_eq!(v["items"][0]["session_ids"][0], 6858);

    let reqs = srv.finish();
    assert_eq!(reqs[0].method, "GET");
    assert_eq!(reqs[0].path, "/api/v1/tasks?team_id=720&limit=200");
}

#[test]
fn tasks_status_team_uses_team_task_endpoint() {
    let srv = common::serve(vec![(
        200,
        r#"{"tasks":[{"id":8991,"title":"Fix rail","team_id":720,"session_ids":[6858]}]}"#,
    )]);
    let out = Command::cargo_bin("eits")
        .unwrap()
        .env("EITS_URL", &srv.url)
        .args(["tasks", "status", "--team", "720"])
        .assert()
        .success();
    let stdout = String::from_utf8(out.get_output().stdout.clone()).unwrap();
    let v: serde_json::Value = serde_json::from_str(stdout.trim()).unwrap();
    assert_eq!(v["items"][0]["team_id"], 720);

    let reqs = srv.finish();
    assert_eq!(reqs[0].method, "GET");
    assert_eq!(reqs[0].path, "/api/v1/tasks?team_id=720&limit=500");
}

#[test]
fn complete_already_done_short_circuits_with_single_request() {
    let srv = common::serve(vec![(200, r#"{"task":{"state_id":3}}"#)]);
    let out = Command::cargo_bin("eits")
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
fn complete_already_done_short_circuits_when_state_id_is_a_string() {
    // Same class of bug as begin_accepts_string_task_id_from_server: the
    // server has been observed sending state_id as a numeric string.
    let srv = common::serve(vec![(200, r#"{"task":{"state_id":"3"}}"#)]);
    let out = Command::cargo_bin("eits")
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
    Command::cargo_bin("eits")
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
    Command::cargo_bin("eits")
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
    let out = Command::cargo_bin("eits")
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
fn commits_list_since_time_sends_created_at_since_param_and_filters_client_side() {
    // Server doesn't implement time filtering (confirmed in commit_controller.ex),
    // so we send the bash-parity param name for forward-compatibility but always
    // re-filter client-side, same as bash's jq fallback. "old" predates any
    // real --since-time cutoff; "new" postdates any real one, so this is
    // deterministic regardless of when the test runs.
    let srv = common::serve(vec![(
        200,
        r#"{"commits":[
            {"id":1,"commit_hash":"old","inserted_at":"2000-01-01T00:00:00Z"},
            {"id":2,"commit_hash":"new","inserted_at":"2099-01-01T00:00:00Z"}
        ]}"#,
    )]);
    let out = Command::cargo_bin("eits")
        .unwrap()
        .env("EITS_URL", &srv.url)
        .args(["commits", "list", "--since-time", "1h"])
        .assert()
        .success();
    let stdout = String::from_utf8(out.get_output().stdout.clone()).unwrap();
    let v: serde_json::Value = serde_json::from_str(stdout.trim()).unwrap();
    assert_eq!(v["count"], 1);
    assert_eq!(v["items"][0]["commit_hash"], "new");
    let reqs = srv.finish();
    assert!(
        reqs[0].path.contains("created_at_since="),
        "expected created_at_since param in path: {}",
        reqs[0].path
    );
}

#[test]
fn commits_list_since_time_excludes_items_missing_a_timestamp() {
    // Matches bash's `select(. == "" then false)`: no inserted_at/created_at
    // at all means excluded, not included by default.
    let srv = common::serve(vec![(
        200,
        r#"{"commits":[{"id":1,"commit_hash":"no-ts"}]}"#,
    )]);
    let out = Command::cargo_bin("eits")
        .unwrap()
        .env("EITS_URL", &srv.url)
        .args(["commits", "list", "--since-time", "1h"])
        .assert()
        .success();
    let stdout = String::from_utf8(out.get_output().stdout.clone()).unwrap();
    let v: serde_json::Value = serde_json::from_str(stdout.trim()).unwrap();
    assert_eq!(v["count"], 0);
}

#[test]
fn commits_create_duplicate_reports_already_tracked_exit_0() {
    let srv = common::serve(vec![(
        200,
        r#"{"commits":[],"duplicates":[{"commit_hash":"abc123","status":"duplicate"}],"errors":[],"already_tracked":true}"#,
    )]);
    let out = Command::cargo_bin("eits")
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
fn commits_create_mixed_batch_reports_partial_with_both_arrays_exit_0() {
    let srv = common::serve(vec![(
        200,
        r#"{"commits":[{"id":9,"commit_hash":"new1","commit_message":null}],"duplicates":[{"commit_hash":"old1","status":"duplicate"}],"errors":[]}"#,
    )]);
    let out = Command::cargo_bin("eits")
        .unwrap()
        .env("EITS_URL", &srv.url)
        .args([
            "commits", "create", "--agent", "agent-1", "--hash", "new1", "--hash", "old1",
        ])
        .assert()
        .success();
    let stdout = String::from_utf8(out.get_output().stdout.clone()).unwrap();
    let v: serde_json::Value = serde_json::from_str(stdout.trim()).unwrap();
    assert_eq!(v["status"], "partial");
    assert_eq!(v["commits"][0]["commit_hash"], "new1");
    assert_eq!(v["duplicates"][0]["commit_hash"], "old1");
    assert!(v.get("errors").is_none());
}

#[test]
fn commits_create_created_plus_errors_reports_partial_with_all_three_exit_0() {
    let srv = common::serve(vec![(
        200,
        r#"{"commits":[{"id":9,"commit_hash":"new1","commit_message":null}],"duplicates":[],"errors":[{"hash":["is invalid"]}]}"#,
    )]);
    let out = Command::cargo_bin("eits")
        .unwrap()
        .env("EITS_URL", &srv.url)
        .args([
            "commits", "create", "--agent", "agent-1", "--hash", "new1", "--hash", "bad",
        ])
        .assert()
        .success();
    let stdout = String::from_utf8(out.get_output().stdout.clone()).unwrap();
    let v: serde_json::Value = serde_json::from_str(stdout.trim()).unwrap();
    assert_eq!(v["status"], "partial");
    assert_eq!(v["commits"][0]["commit_hash"], "new1");
    assert!(v["duplicates"].is_null());
    assert!(v["errors"].as_array().unwrap().len() == 1);
}

#[test]
fn commits_create_pure_errors_still_exits_1_validation() {
    let srv = common::serve(vec![(
        200,
        r#"{"commits":[],"duplicates":[],"errors":[{"hash":["is invalid"]}]}"#,
    )]);
    let out = Command::cargo_bin("eits")
        .unwrap()
        .env("EITS_URL", &srv.url)
        .args(["commits", "create", "--agent", "agent-1", "--hash", "bad"])
        .assert()
        .code(1);
    let stdout = String::from_utf8(out.get_output().stdout.clone()).unwrap();
    let v: serde_json::Value = serde_json::from_str(stdout.trim()).unwrap();
    assert_eq!(v["code"], "validation");
}

#[test]
fn commits_create_html_error_reports_json_with_commit_hint() {
    let srv = common::serve(vec![(400, "<html><body>bad request</body></html>")]);
    let out = Command::cargo_bin("eits")
        .unwrap()
        .env("EITS_URL", &srv.url)
        .args(["commits", "create", "--agent", "agent-1", "--hash", "bad"])
        .assert()
        .code(1);
    let stdout = String::from_utf8(out.get_output().stdout.clone()).unwrap();
    let v: serde_json::Value = serde_json::from_str(stdout.trim()).unwrap();
    assert_eq!(v["code"], "validation");
    assert_eq!(v["status"], 400);
    assert_eq!(v["error"], "server returned HTML — check server logs");
    assert!(v["hint"]
        .as_str()
        .unwrap()
        .contains("commits API returned HTML instead of JSON"));
}

#[test]
fn notes_add_quiet_prints_bare_id() {
    let srv = common::serve(vec![(
        200,
        r#"{"id":7,"parent_type":"session","parent_id":"s-1","title":"","body":"hi","starred":false}"#,
    )]);
    let out = Command::cargo_bin("eits")
        .unwrap()
        .env("EITS_URL", &srv.url)
        .env("EITS_SESSION_UUID", "s-1")
        .args(["--quiet", "notes", "add", "--body", "hi"])
        .assert()
        .success();
    let stdout = String::from_utf8(out.get_output().stdout.clone()).unwrap();
    assert_eq!(stdout.trim(), "7");
}

#[test]
fn sessions_list_normalizes_from_results_key() {
    let srv = common::serve(vec![(200, r#"{"results":[{"uuid":"a-1","name":"one"}]}"#)]);
    let out = Command::cargo_bin("eits")
        .unwrap()
        .env("EITS_URL", &srv.url)
        .env("EITS_PROJECT_ID", "1")
        .args(["sessions", "list"])
        .assert()
        .success();
    let stdout = String::from_utf8(out.get_output().stdout.clone()).unwrap();
    let v: serde_json::Value = serde_json::from_str(stdout.trim()).unwrap();
    assert_eq!(v["count"], 1);
    assert_eq!(v["items"][0]["uuid"], "a-1");
}

#[test]
fn sessions_list_normalizes_from_sessions_key() {
    let srv = common::serve(vec![(
        200,
        r#"{"sessions":[{"uuid":"b-2","name":"two"},{"uuid":"b-3","name":"three"}]}"#,
    )]);
    let out = Command::cargo_bin("eits")
        .unwrap()
        .env("EITS_URL", &srv.url)
        .env("EITS_PROJECT_ID", "1")
        .args(["sessions", "list"])
        .assert()
        .success();
    let stdout = String::from_utf8(out.get_output().stdout.clone()).unwrap();
    let v: serde_json::Value = serde_json::from_str(stdout.trim()).unwrap();
    assert_eq!(v["count"], 2);
    assert_eq!(v["items"][1]["uuid"], "b-3");
}

#[test]
fn sessions_create_quiet_prints_bare_uuid() {
    let srv = common::serve(vec![(200, r#"{"session":{"uuid":"new-uuid-1"}}"#)]);
    let out = Command::cargo_bin("eits")
        .unwrap()
        .env("EITS_URL", &srv.url)
        .args([
            "--quiet",
            "sessions",
            "create",
            "--session-id",
            "new-uuid-1",
        ])
        .assert()
        .success();
    let stdout = String::from_utf8(out.get_output().stdout.clone()).unwrap();
    assert_eq!(stdout.trim(), "new-uuid-1");
}

#[test]
fn sessions_list_mine_and_search_is_usage_error_exit_2() {
    let out = Command::cargo_bin("eits")
        .unwrap()
        .env("EITS_URL", "http://127.0.0.1:1")
        .env("EITS_SESSION_UUID", "s-1")
        .args(["sessions", "list", "--mine", "--search", "foo"])
        .assert()
        .code(2);
    let stdout = String::from_utf8(out.get_output().stdout.clone()).unwrap();
    let v: serde_json::Value = serde_json::from_str(stdout.trim()).unwrap();
    assert_eq!(v["code"], "usage");
}

#[test]
fn sessions_end_defaults_uuid_to_session_identity() {
    let srv = common::serve(vec![(200, r#"{"status":"ended"}"#)]);
    Command::cargo_bin("eits")
        .unwrap()
        .env("EITS_URL", &srv.url)
        .env("EITS_SESSION_UUID", "self-uuid-9")
        .args(["sessions", "end"])
        .assert()
        .success();
    let reqs = srv.finish();
    assert_eq!(reqs[0].method, "POST");
    assert_eq!(reqs[0].path, "/api/v1/sessions/self-uuid-9/end");
}

#[test]
fn sessions_create_project_flag_sends_project_name_key() {
    let srv = common::serve(vec![(200, r#"{"session":{"uuid":"s-1"}}"#)]);
    Command::cargo_bin("eits")
        .unwrap()
        .env("EITS_URL", &srv.url)
        .args([
            "sessions",
            "create",
            "--session-id",
            "s-1",
            "--project",
            "my-project",
        ])
        .assert()
        .success();
    let reqs = srv.finish();
    let body: serde_json::Value = serde_json::from_str(&reqs[0].body).unwrap();
    assert_eq!(body["project_name"], "my-project");
    assert!(body.get("project").is_none());
}

#[test]
fn sessions_update_project_id_flag_sends_project_id_key() {
    let srv = common::serve(vec![(200, r#"{"status":"ok"}"#)]);
    Command::cargo_bin("eits")
        .unwrap()
        .env("EITS_URL", &srv.url)
        .args(["sessions", "update", "s-1", "--project-id", "42"])
        .assert()
        .success();
    let reqs = srv.finish();
    let body: serde_json::Value = serde_json::from_str(&reqs[0].body).unwrap();
    assert_eq!(body["project_id"], 42); // all-digit *_id coerced to a JSON number
    assert!(body.get("project").is_none());
}

#[test]
fn sessions_get_self_resolves_to_session_uuid() {
    let srv = common::serve(vec![(
        200,
        r#"{"session":{"uuid":"resolved-uuid","name":"Codex CLI"}}"#,
    )]);
    let out = Command::cargo_bin("eits")
        .unwrap()
        .env("EITS_URL", &srv.url)
        .env("EITS_SESSION_UUID", "resolved-uuid")
        .args(["sessions", "get", "self"])
        .assert()
        .success();
    let stdout = String::from_utf8(out.get_output().stdout.clone()).unwrap();
    let v: serde_json::Value = serde_json::from_str(stdout.trim()).unwrap();
    assert_eq!(v["uuid"], "resolved-uuid");
    assert_eq!(v["name"], "Codex CLI");
    assert!(v.get("session").is_none(), "sessions get stays top-level");
    let reqs = srv.finish();
    assert_eq!(reqs[0].path, "/api/v1/sessions/resolved-uuid");
}

#[test]
fn sessions_create_omits_absent_optional_fields() {
    let srv = common::serve(vec![(200, r#"{"session":{"uuid":"s-1"}}"#)]);
    Command::cargo_bin("eits")
        .unwrap()
        .env("EITS_URL", &srv.url)
        .args(["sessions", "create", "--session-id", "s-1"])
        .assert()
        .success();
    let reqs = srv.finish();
    let body: serde_json::Value = serde_json::from_str(&reqs[0].body).unwrap();
    let obj = body.as_object().unwrap();
    assert_eq!(
        obj.keys()
            .cloned()
            .collect::<std::collections::BTreeSet<_>>(),
        ["session_id", "read_only"]
            .into_iter()
            .map(String::from)
            .collect::<std::collections::BTreeSet<_>>()
    );
}

#[test]
fn dm_send_holds_lock_and_times_out_when_already_locked() {
    let identity = "test-dm-lock-1";
    let lock_path = std::path::PathBuf::from(format!("/tmp/eits_dm_{identity}.lock"));
    let _ = std::fs::remove_dir(&lock_path); // clean slate in case of a prior crash
    std::fs::create_dir(&lock_path).unwrap();

    let out = Command::cargo_bin("eits")
        .unwrap()
        .env("EITS_URL", "http://127.0.0.1:1/api/v1")
        .env("EITS_SESSION_UUID", identity)
        .env("EITS_DM_LOCK_ATTEMPTS", "1")
        .args(["dm", "--to", "9", "--message", "hi"])
        .assert()
        .code(1);
    let stdout = String::from_utf8(out.get_output().stdout.clone()).unwrap();
    let v: serde_json::Value = serde_json::from_str(stdout.trim()).unwrap();
    assert_eq!(v["code"], "lock_timeout");

    std::fs::remove_dir(&lock_path).unwrap();
}

#[test]
fn dm_inbox_normalizes_messages_key_and_sends_from_and_limit_params() {
    let srv = common::serve(vec![(
        200,
        r#"{"session_id":1,"count":1,"messages":[{"id":5,"from_session_id":2,"body":"hi"}]}"#,
    )]);
    let out = Command::cargo_bin("eits")
        .unwrap()
        .env("EITS_URL", &srv.url)
        .env("EITS_SESSION_UUID", "s-1")
        .args(["dm", "inbox", "--from", "2", "--limit", "5"])
        .assert()
        .success();
    let stdout = String::from_utf8(out.get_output().stdout.clone()).unwrap();
    let v: serde_json::Value = serde_json::from_str(stdout.trim()).unwrap();
    assert_eq!(v["count"], 1);
    assert_eq!(v["items"][0]["id"], 5);

    let reqs = srv.finish();
    assert!(
        reqs[0].path.contains("from=2"),
        "expected from=2 in path: {}",
        reqs[0].path
    );
    assert!(
        reqs[0].path.contains("limit=5"),
        "expected limit=5 in path: {}",
        reqs[0].path
    );
}

#[test]
fn dm_send_bad_metadata_is_usage_error_exit_2() {
    let out = Command::cargo_bin("eits")
        .unwrap()
        .env("EITS_URL", "http://127.0.0.1:1/api/v1")
        .env("EITS_SESSION_UUID", "s-1")
        .args([
            "dm",
            "--to",
            "9",
            "--message",
            "hi",
            "--metadata",
            "not-json",
        ])
        .assert()
        .code(2);
    let stdout = String::from_utf8(out.get_output().stdout.clone()).unwrap();
    let v: serde_json::Value = serde_json::from_str(stdout.trim()).unwrap();
    assert_eq!(v["code"], "usage");
}

#[test]
fn dm_send_posts_exact_payload_keys_and_releases_lock_after() {
    let srv = common::serve(vec![(200, r#"{"success":true,"message_id":"77"}"#)]);
    let identity = "test-dm-lock-2";
    let lock_path = std::path::PathBuf::from(format!("/tmp/eits_dm_{identity}.lock"));
    let _ = std::fs::remove_dir(&lock_path);

    let out = Command::cargo_bin("eits")
        .unwrap()
        .env("EITS_URL", &srv.url)
        .env("EITS_SESSION_UUID", identity)
        .args(["--quiet", "dm", "--to", "9", "--message", "hi"])
        .assert()
        .success();
    let stdout = String::from_utf8(out.get_output().stdout.clone()).unwrap();
    assert_eq!(stdout.trim(), "77");
    assert!(
        !lock_path.exists(),
        "lock dir must be released after send completes"
    );

    let reqs = srv.finish();
    let body: serde_json::Value = serde_json::from_str(&reqs[0].body).unwrap();
    assert_eq!(body["from_session_id"], identity);
    assert_eq!(body["to_session_id"], "9");
    assert_eq!(body["message"], "hi");
    assert_eq!(body["response_required"], false);
    assert!(body.get("metadata").is_none());
}

#[test]
fn dm_wait_requires_session() {
    let mut cmd = Command::cargo_bin("eits").unwrap();
    let out = scrub_codex_identity(&mut cmd)
        .env("EITS_URL", "http://127.0.0.1:1/api/v1")
        .env_remove("EITS_SESSION_UUID")
        .env_remove("EITS_SESSION_ID")
        .args(["dm", "wait"])
        .assert()
        .code(2);
    let stdout = String::from_utf8(out.get_output().stdout.clone()).unwrap();
    let v: serde_json::Value = serde_json::from_str(stdout.trim()).unwrap();
    assert_eq!(v["code"], "usage");
}

#[test]
fn dm_wait_sends_session_timeout_and_since_params() {
    let srv = common::serve(vec![(200, r#"{"items":[],"count":0}"#)]);
    let out = Command::cargo_bin("eits")
        .unwrap()
        .env("EITS_URL", &srv.url)
        .args([
            "dm",
            "wait",
            "--session",
            "s-1",
            "--timeout",
            "3",
            "--since",
            "2026-01-01T00:00:00Z",
        ])
        .assert()
        .success();
    let stdout = String::from_utf8(out.get_output().stdout.clone()).unwrap();
    let v: serde_json::Value = serde_json::from_str(stdout.trim()).unwrap();
    assert_eq!(v["count"], 0);
    assert_eq!(v["items"].as_array().unwrap().len(), 0);

    let reqs = srv.finish();
    assert!(reqs[0].path.starts_with("/api/v1/dm/wait?"));
    assert!(reqs[0].path.contains("session=s-1"));
    assert!(reqs[0].path.contains("timeout=3"));
    assert!(reqs[0].path.contains("since=2026-01-01"));
}

#[test]
fn dm_wait_defaults_session_from_identity_and_prints_arrived_dm() {
    let srv = common::serve(vec![(
        200,
        r#"{"items":[{"id":9,"body":"hi","from_session_id":2,"to_session_id":1}],"count":1}"#,
    )]);
    let out = Command::cargo_bin("eits")
        .unwrap()
        .env("EITS_URL", &srv.url)
        .env("EITS_SESSION_UUID", "s-1")
        .args(["dm", "wait"])
        .assert()
        .success();
    let stdout = String::from_utf8(out.get_output().stdout.clone()).unwrap();
    let v: serde_json::Value = serde_json::from_str(stdout.trim()).unwrap();
    assert_eq!(v["count"], 1);
    assert_eq!(v["items"][0]["id"], 9);

    let reqs = srv.finish();
    assert!(reqs[0].path.contains("session=s-1"));
    assert!(
        reqs[0].path.contains("timeout=25"),
        "default timeout: {}",
        reqs[0].path
    );
}

#[test]
fn dm_wait_team_only_skips_non_team_messages_until_team_message_arrives() {
    let srv = common::serve(vec![
        (
            200,
            r#"{"teams":[{"id":720,"name":"cli-workflow-9025-9026"}]}"#,
        ),
        (200, r#"{"members":[{"session_id":222}]}"#),
        (
            200,
            r#"{"items":[{"id":1,"body":"outside","from_session_id":111,"inserted_at":"2026-01-01T00:00:00Z"}],"count":1}"#,
        ),
        (
            200,
            r#"{"items":[{"id":2,"body":"inside","from_session_id":222,"inserted_at":"2026-01-01T00:00:01Z"}],"count":1}"#,
        ),
    ]);
    let out = Command::cargo_bin("eits")
        .unwrap()
        .env("EITS_URL", &srv.url)
        .env("EITS_SESSION_UUID", "s-1")
        .env("EITS_AGENT_UUID", "agent-1")
        .args(["dm", "wait", "--team-only", "--timeout", "3"])
        .assert()
        .success();
    let stdout = String::from_utf8(out.get_output().stdout.clone()).unwrap();
    let v: serde_json::Value = serde_json::from_str(stdout.trim()).unwrap();
    assert_eq!(v["count"], 1);
    assert_eq!(v["items"][0]["id"], 2);

    let reqs = srv.finish();
    assert_eq!(reqs.len(), 4);
    assert_eq!(reqs[0].path, "/api/v1/teams?member_agent_uuid=agent-1");
    assert_eq!(reqs[1].path, "/api/v1/teams/720/members");
    assert!(reqs[2].path.contains("/api/v1/dm/wait?"));
    assert!(reqs[2].path.contains("session=s-1"));
    assert!(
        reqs[3].path.contains("since=2026-01-01T00%3A00%3A00Z"),
        "expected second wait to advance since past non-team DM: {}",
        reqs[3].path
    );
}

#[test]
fn sessions_archive_dry_run_lists_without_posting() {
    let srv = common::serve(vec![(
        200,
        r#"{"sessions":[{"uuid":"a-1","name":"one","status":"waiting"},{"uuid":"a-2","name":"two","status":"waiting"}]}"#,
    )]);
    let out = Command::cargo_bin("eits")
        .unwrap()
        .env("EITS_URL", &srv.url)
        .args(["sessions", "archive", "--status", "waiting", "--dry-run"])
        .assert()
        .success();
    let stdout = String::from_utf8(out.get_output().stdout.clone()).unwrap();
    let v: serde_json::Value = serde_json::from_str(stdout.trim()).unwrap();
    assert_eq!(v["dry_run"], true);
    assert_eq!(v["count"], 2);
    // Only the list request should have been made — no archive POSTs.
    let reqs = srv.finish();
    assert_eq!(reqs.len(), 1);
    assert_eq!(reqs[0].method, "GET");
}

#[test]
fn tasks_get_grafts_envelope_siblings_into_task() {
    // Server envelope carries project_id/annotations OUTSIDE .task (bash
    // parity); normalization must not lose them. Regression: ticket 8108.
    let srv = common::serve(vec![(
        200,
        r#"{"success":true,"task":{"id":8108,"title":"t","state_id":1},"project_id":1,"annotations":[{"id":1,"body":"x"}]}"#,
    )]);
    let out = Command::cargo_bin("eits")
        .unwrap()
        .env("EITS_URL", &srv.url)
        .args(["tasks", "get", "8108"])
        .assert()
        .success();
    let stdout = String::from_utf8(out.get_output().stdout.clone()).unwrap();
    let v: serde_json::Value = serde_json::from_str(stdout.trim()).unwrap();
    assert_eq!(v["task"]["project_id"], 1);
    assert_eq!(v["task"]["annotations"][0]["body"], "x");
    assert!(v.get("project_id").is_none(), "no top-level duplication");
}
