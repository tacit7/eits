use std::path::Path;
use std::process::Command;

fn git(repo: &Path, args: &[&str]) {
    let output = Command::new("git")
        .arg("-C")
        .arg(repo)
        .args(args)
        .output()
        .unwrap();
    assert!(
        output.status.success(),
        "{}",
        String::from_utf8_lossy(&output.stderr)
    );
}

fn repo() -> tempfile::TempDir {
    let dir = tempfile::tempdir().unwrap();
    git(dir.path(), &["init", "-q"]);
    git(
        dir.path(),
        &[
            "-c",
            "user.name=Test",
            "-c",
            "user.email=test@example.com",
            "commit",
            "--allow-empty",
            "-qm",
            "initial",
        ],
    );
    dir
}

fn add_worktree(repo: &Path, path: &Path, branch: &str) {
    git(
        repo,
        &[
            "worktree",
            "add",
            "-q",
            "-b",
            branch,
            path.to_str().unwrap(),
        ],
    );
}

fn warnings(cwd: &Path, project: &Path, name: &str) -> String {
    let output = assert_cmd::Command::cargo_bin("eits")
        .unwrap()
        .current_dir(cwd)
        .env(
            "EITS_EXTRAS",
            concat!(env!("CARGO_MANIFEST_DIR"), "/../../scripts/eits-extras"),
        )
        .env("EITS_URL", "http://127.0.0.1:1/api/v1")
        .env("EITS_API_KEY", "")
        .env("EITS_SESSION_UUID", "")
        .env("EITS_PROJECT_ID", "1")
        .args([
            "agents",
            "spawn",
            "--provider",
            "codex",
            "--instructions",
            "regression test",
            "--dry-run",
            "--yolo",
            "--project-path",
        ])
        .arg(project)
        .args(["--worktree", name])
        .assert()
        .success()
        .get_output()
        .stderr
        .clone();
    String::from_utf8(output).unwrap()
}

#[test]
fn unrelated_worktrees_and_branch_prefixes_are_silent() {
    let project = repo();
    add_worktree(
        project.path(),
        &project.path().join("other"),
        "worktree-requested-extra",
    );
    assert!(!warnings(project.path(), project.path(), "requested").contains("warning:"));
}

#[test]
fn uses_requested_project_instead_of_callers_repository() {
    let caller = repo();
    let project = repo();
    add_worktree(
        caller.path(),
        &caller.path().join("other"),
        "worktree-requested",
    );
    assert!(!warnings(caller.path(), project.path(), "requested").contains("warning:"));
    add_worktree(
        project.path(),
        &project.path().join("other"),
        "worktree-requested",
    );
    assert!(warnings(caller.path(), project.path(), "requested")
        .contains("warning: worktree \"requested\""));
}

#[test]
fn matching_registered_branch_warns_even_when_path_is_missing() {
    let project = repo();
    let path = project.path().join("old location");
    add_worktree(project.path(), &path, "worktree-requested");
    std::fs::rename(&path, project.path().join("moved location")).unwrap();
    assert!(warnings(project.path(), project.path(), "requested")
        .contains("warning: worktree \"requested\""));
}

#[test]
fn matching_path_warns_even_for_different_branch_and_missing_directory() {
    let project = repo();
    let path = project.path().join(".claude/worktrees/nested/requested");
    add_worktree(project.path(), &path, "other-branch");
    std::fs::rename(&path, project.path().join("moved")).unwrap();
    assert!(warnings(project.path(), project.path(), "nested/requested")
        .contains("warning: worktree \"nested/requested\""));
}

#[test]
fn existing_unregistered_target_warns() {
    let project = repo();
    let path = project.path().join(".claude/worktrees/requested");
    std::fs::create_dir_all(path.parent().unwrap()).unwrap();
    std::fs::write(path, "occupied").unwrap();
    assert!(warnings(project.path(), project.path(), "requested")
        .contains("warning: worktree \"requested\""));
}

#[test]
fn non_repository_does_not_break_dry_run() {
    let dir = tempfile::tempdir().unwrap();
    assert!(!warnings(dir.path(), dir.path(), "requested").contains("warning:"));
}
