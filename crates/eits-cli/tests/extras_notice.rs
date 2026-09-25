use assert_cmd::Command;
use std::os::unix::fs::PermissionsExt;

const NOTICE: &str = "[eits] delegating to legacy eits-extras; output format may differ\n";

fn fake_extras(dir: &tempfile::TempDir) -> std::path::PathBuf {
    let path = dir.path().join("eits-extras");
    std::fs::write(
        &path,
        "#!/bin/sh\nprintf '%s\\0' \"$@\"\nprintf 'legacy stderr\\n' >&2\nexit \"$FAKE_EXIT\"\n",
    )
    .unwrap();
    std::fs::set_permissions(&path, std::fs::Permissions::from_mode(0o755)).unwrap();
    path
}

#[test]
fn delegation_notices_once_without_leaking_args_or_changing_output_and_status() {
    let dir = tempfile::tempdir().unwrap();
    let extras = fake_extras(&dir);
    let args = [
        "worktree",
        "list",
        "--token",
        "test-secret with spaces",
        "",
        "a\nb",
    ];
    let expected_stdout: Vec<u8> = args
        .iter()
        .flat_map(|arg| arg.as_bytes().iter().copied().chain([0]))
        .collect();

    for binary in ["eits", "eitsr"] {
        for status in [0, 42] {
            Command::cargo_bin(binary)
                .unwrap()
                .env("EITS_EXTRAS", &extras)
                .env("FAKE_EXIT", status.to_string())
                .args(args)
                .assert()
                .code(status)
                .stdout(expected_stdout.clone())
                .stderr(format!("{NOTICE}legacy stderr\n"));
        }
    }
}

#[test]
fn missing_extras_keeps_json_error_without_notice() {
    let dir = tempfile::tempdir().unwrap();
    Command::cargo_bin("eits")
        .unwrap()
        .env("EITS_EXTRAS", dir.path().join("missing"))
        .args(["worktree", "list"])
        .assert()
        .code(1)
        .stdout(predicates::str::contains("\"code\":\"extras_not_found\""))
        .stderr("");
}

#[test]
fn rejected_global_flags_do_not_delegate_or_notice() {
    let dir = tempfile::tempdir().unwrap();
    let extras = fake_extras(&dir);
    Command::cargo_bin("eits")
        .unwrap()
        .env("EITS_EXTRAS", extras)
        .args(["--pretty", "worktree", "list"])
        .assert()
        .code(2)
        .stdout(predicates::str::contains("\"code\":\"usage\""))
        .stderr("");
}

#[test]
fn rust_owned_commands_do_not_delegate_or_notice() {
    let dir = tempfile::tempdir().unwrap();
    let extras = fake_extras(&dir);
    for family in [
        "tasks", "dm", "sessions", "commits", "notes", "whoami", "doctor", "work", "workflow",
    ] {
        Command::cargo_bin("eits")
            .unwrap()
            .env("EITS_EXTRAS", &extras)
            .args([family, "--help"])
            .assert()
            .success()
            .stderr("");
    }
}
