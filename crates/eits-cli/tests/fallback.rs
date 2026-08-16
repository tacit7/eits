use assert_cmd::Command;

fn fake_extras(dir: &tempfile::TempDir) -> std::path::PathBuf {
    let p = dir.path().join("eits-extras");
    std::fs::write(&p, "#!/bin/sh\necho \"EXTRAS:$@\"\nexit 42\n").unwrap();
    use std::os::unix::fs::PermissionsExt;
    std::fs::set_permissions(&p, std::fs::Permissions::from_mode(0o755)).unwrap();
    p
}

#[test]
fn unknown_root_subcommand_execs_extras_with_argv() {
    let dir = tempfile::tempdir().unwrap();
    let extras = fake_extras(&dir);
    Command::cargo_bin("eits")
        .unwrap()
        .env("EITS_EXTRAS", &extras)
        .args(["worktree", "list", "--flag", "x y"])
        .assert()
        .code(42)
        .stdout(predicates::str::contains("EXTRAS:worktree list --flag x y"));
}

#[test]
fn missing_extras_is_json_error_exit_1() {
    Command::cargo_bin("eits")
        .unwrap()
        .env("EITS_EXTRAS", "/nonexistent/nope")
        .env("PATH", "/usr/bin:/bin") // no eits-extras on PATH
        .args(["worktree", "list"])
        .assert()
        .code(1)
        .stdout(predicates::str::contains("\"code\":\"extras_not_found\""));
}

#[test]
fn global_flags_are_not_forwarded_to_extras() {
    let dir = tempfile::tempdir().unwrap();
    let extras = fake_extras(&dir);
    Command::cargo_bin("eits")
        .unwrap()
        .env("EITS_EXTRAS", &extras)
        .args(["--pretty", "worktree", "list"])
        .assert()
        .code(2)
        .stdout(predicates::str::contains("\"code\":\"usage\""));
}
