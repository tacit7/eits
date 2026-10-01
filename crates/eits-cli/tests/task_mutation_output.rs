mod common;

use assert_cmd::Command;
use serde_json::{json, Value};

fn command(url: &str, args: &[&str]) -> Command {
    let mut cmd = Command::cargo_bin("eits").unwrap();
    cmd.env_clear()
        .env("EITS_URL", url)
        .env("EITS_SESSION_UUID", "caller-not-owner")
        .env("EITS_PROJECT_ID", "999")
        .args(args);
    cmd
}

#[test]
fn task_mutations_add_common_fields_without_losing_api_payload() {
    for args in [
        vec!["tasks", "create", "--title", "example"],
        vec!["tasks", "claim", "42"],
        vec!["tasks", "begin", "--id", "42"],
        vec!["tasks", "update", "42", "--title", "example"],
    ] {
        let response = r#"{"message":"saved","task_id":42,"task":{"id":42,"state":"In Progress","session_id":17,"project_id":6},"extra":"kept"}"#;
        let srv = common::serve(vec![(200, response)]);
        let out = command(&srv.url, &args).assert().success();
        let v: Value = serde_json::from_slice(&out.get_output().stdout).unwrap();
        assert_eq!(v["success"], true, "{args:?}");
        assert_eq!(v["id"], 42);
        assert_eq!(v["state"], "In Progress");
        assert_eq!(v["session_id"], 17);
        assert_eq!(v["project_id"], 6);
        assert_eq!(v["next"], json!(["eits tasks get 42"]));
        let original: Value = serde_json::from_str(response).unwrap();
        for (key, value) in original.as_object().unwrap() {
            assert_eq!(&v[key], value);
        }
        assert_eq!(srv.finish().len(), 1);
    }
}

#[test]
fn missing_api_context_is_explicitly_null_even_with_environment_defaults() {
    let srv = common::serve(vec![(200, r#"{"task_id":"42"}"#)]);
    let out = command(&srv.url, &["tasks", "create", "--title", "example"])
        .assert()
        .success();
    let v: Value = serde_json::from_slice(&out.get_output().stdout).unwrap();
    assert_eq!(
        v,
        json!({"success":true,"id":"42","task_id":"42",
        "state":null,"session_id":null,"project_id":null,"next":["eits tasks get 42"]})
    );
    srv.finish();
}

#[test]
fn complete_normalizes_both_changed_and_already_closed_results() {
    for closed in [false, true] {
        for quiet in [false, true] {
            let responses = if closed {
                vec![(
                    200,
                    r#"{"task":{"id":42,"state_id":3,"state":"Done","session_id":17},"project_id":6}"#,
                )]
            } else {
                vec![
                    (200, r#"{"task":{"id":42,"state":"In Progress"}}"#),
                    (200, r#"{"success":true,"task_id":42}"#),
                ]
            };
            let srv = common::serve(responses);
            let mut cmd = command(&srv.url, &["tasks", "complete", "42", "--message", "done"]);
            if quiet {
                cmd.arg("--quiet");
            }
            let out = cmd.assert().success();
            if quiet {
                assert_eq!(out.get_output().stdout, b"42\n");
            } else {
                let v: Value = serde_json::from_slice(&out.get_output().stdout).unwrap();
                assert_eq!(v["success"], true);
                assert_eq!(v["id"], 42);
                assert_eq!(v["next"], json!(["eits tasks get 42"]));
                assert_eq!(v["state"], if closed { json!("Done") } else { Value::Null });
                assert!(v.get("session_id").is_some());
                assert!(v.get("project_id").is_some());
                if closed {
                    assert_eq!(v["status"], "already_closed");
                }
            }
            assert_eq!(srv.finish().len(), if closed { 1 } else { 2 });
        }
    }
}

#[test]
fn begin_creation_uses_fetched_context_and_keeps_legacy_summary() {
    let srv = common::serve(vec![
        (200, r#"{"task_id":42}"#),
        (200, r#"{"success":true}"#),
        (200, r#"{"success":true}"#),
        (
            200,
            r#"{"task":{"id":42,"title":"example","state":"In Progress"},"state_id":2,"session_id":17,"project_id":6}"#,
        ),
    ]);
    let out = command(&srv.url, &["tasks", "begin", "--title", "example"])
        .assert()
        .success();
    let v: Value = serde_json::from_slice(&out.get_output().stdout).unwrap();
    assert_eq!(
        v,
        json!({"success":true,"id":42,"task_id":42,"title":"example",
        "state":"In Progress","state_id":2,"session_id":17,"project_id":6,
        "message":"Task created","next":["eits tasks get 42"]})
    );
    assert_eq!(srv.finish().len(), 4);
}

#[test]
fn quiet_mutations_still_print_only_the_id() {
    for args in [
        vec!["tasks", "create", "--title", "example"],
        vec!["tasks", "claim", "42"],
        vec!["tasks", "begin", "--id", "42"],
        vec!["tasks", "update", "42", "--state", "done"],
    ] {
        let srv = common::serve(vec![(200, r#"{"task_id":42}"#)]);
        command(&srv.url, &args)
            .arg("--quiet")
            .assert()
            .success()
            .stdout("42\n");
        srv.finish();
    }
}

#[test]
fn update_uses_addressed_id_but_does_not_infer_requested_state() {
    let srv = common::serve(vec![(200, r#"{"message":"updated"}"#)]);
    let out = command(&srv.url, &["tasks", "update", "42", "--state", "done"])
        .arg("--pretty")
        .assert()
        .success();
    let v: Value = serde_json::from_slice(&out.get_output().stdout).unwrap();
    assert_eq!(
        v,
        json!({"message":"updated","success":true,"id":42,
        "state":null,"session_id":null,"project_id":null,"next":["eits tasks get 42"]})
    );
    assert!(String::from_utf8_lossy(&out.get_output().stdout).contains("\n  "));
    srv.finish();
}

#[test]
fn explicit_top_level_fields_win_including_false_and_null() {
    let response = r#"{"success":false,"id":42,"state":null,"session_id":19,"project_id":8,"next":[],"task":{"id":43,"state":"Done","session_id":17,"project_id":6}}"#;
    let srv = common::serve(vec![(200, response)]);
    let out = command(&srv.url, &["tasks", "claim", "42"])
        .assert()
        .success();
    let v: Value = serde_json::from_slice(&out.get_output().stdout).unwrap();
    assert_eq!(v, serde_json::from_str::<Value>(response).unwrap());
    srv.finish();
}

#[test]
fn absent_or_non_numeric_ids_do_not_produce_suggested_shell_commands() {
    for response in [r#"{}"#, r#"{"task_id":"42; echo unexpected"}"#] {
        let srv = common::serve(vec![(200, response)]);
        let out = command(&srv.url, &["tasks", "create", "--title", "example"])
            .assert()
            .success();
        let v: Value = serde_json::from_slice(&out.get_output().stdout).unwrap();
        assert!(v.get("id").is_some());
        assert_eq!(v["next"], json!([]));
        srv.finish();
    }
}
