use crate::config::Config;
use crate::error::EitsError;
use crate::http::Client;
use crate::output;
use serde_json::{json, Value};
use std::collections::HashSet;
use std::process::Command as StdCommand;

use super::whoami;

#[derive(clap::Subcommand)]
pub enum WorkCmd {
    /// Report the current work/session checkpoint
    #[command(alias = "checkpoint")]
    Status,
}

pub fn run(client: &Client, cfg: &Config, cmd: WorkCmd, pretty: bool) -> Result<(), EitsError> {
    match cmd {
        WorkCmd::Status => {
            let mut warnings: Vec<String> = Vec::new();
            let mut report = serde_json::Map::new();

            let mut identity = json!({
                "session_uuid": cfg.session_uuid.clone(),
                "session_id": cfg.session_id.clone(),
                "agent_uuid": cfg.agent_uuid.clone(),
                "agent_id": Value::Null,
                "project_id": cfg.project_id.clone(),
                "created_at": Value::Null,
                "worktree_path": Value::Null,
                "resolved": false,
            });

            let session_snapshot = match cfg.session_identity() {
                Some(_) => match whoami::resolve(client, cfg) {
                    Ok(snapshot) => Some(snapshot),
                    Err(err) => {
                        warnings.push(format!("session lookup unavailable: {}", err.message));
                        None
                    }
                },
                None => None,
            };

            if let Some(snapshot) = &session_snapshot {
                identity["session_uuid"] = snapshot.session_uuid.clone();
                identity["session_id"] = snapshot.session_id.clone();
                identity["agent_uuid"] = json!(snapshot.agent_uuid.clone());
                identity["agent_id"] = snapshot.agent_id.clone();
                identity["project_id"] = snapshot.project_id.clone();
                identity["created_at"] = snapshot
                    .session
                    .get("created_at")
                    .cloned()
                    .unwrap_or(Value::Null);
                identity["worktree_path"] = snapshot
                    .session
                    .get("worktree_path")
                    .cloned()
                    .unwrap_or(Value::Null);
                identity["status"] = snapshot
                    .session
                    .get("status")
                    .cloned()
                    .unwrap_or(Value::Null);
                identity["resolved"] = json!(true);
            }

            report.insert("current_session".into(), identity);
            report.insert(
                "health".into(),
                json!({
                    "session_identity": cfg.session_identity().is_some(),
                    "agent_uuid": cfg.agent_uuid.is_some(),
                    "project_id": cfg.project_id.is_some(),
                    "session_resolved": session_snapshot.is_some(),
                }),
            );

            let mut task_items: Vec<Value> = Vec::new();
            let mut active_tasks: Vec<Value> = Vec::new();
            let mut tasks_ok = false;
            if let Some(identity) = cfg.session_identity() {
                let mut qs = format!("session_id={identity}&limit=200");
                if let Some(pid) = cfg.project_id.as_deref() {
                    qs.push_str(&format!("&project_id={pid}"));
                }
                match client.get(&format!("/tasks?{qs}")) {
                    Ok(resp) => {
                        task_items = collection_items(&resp, &["tasks", "results"]);
                        active_tasks = task_items
                            .iter()
                            .filter(|task| matches!(task_state_id(task), Some(2 | 4)))
                            .cloned()
                            .collect();
                        tasks_ok = true;
                    }
                    Err(err) => warnings.push(format!("task lookup unavailable: {}", err.message)),
                }
            }
            report.insert(
                "tasks".into(),
                json!({
                    "count": task_items.len(),
                    "active_count": active_tasks.len(),
                    "items": task_items,
                    "active_items": active_tasks,
                }),
            );
            update_health(&mut report, "tasks", tasks_ok);

            let mut team_items: Vec<Value> = Vec::new();
            let mut teams_ok = false;
            let agent_uuid = session_snapshot
                .as_ref()
                .map(|snapshot| snapshot.agent_uuid.clone())
                .or_else(|| cfg.agent_uuid.clone());
            if let Some(agent_uuid) = agent_uuid {
                match client.get(&format!(
                    "/teams?member_agent_uuid={}",
                    super::uri_encode(&agent_uuid)
                )) {
                    Ok(resp) => {
                        team_items = collection_items(&resp, &["teams"]);
                        teams_ok = true;
                    }
                    Err(err) => warnings.push(format!("team lookup unavailable: {}", err.message)),
                }
            }
            report.insert(
                "team_memberships".into(),
                json!({
                    "count": team_items.len(),
                    "items": team_items,
                }),
            );
            update_health(&mut report, "teams", teams_ok);

            let mut inbox_items: Vec<Value> = Vec::new();
            let mut inbox_ok = false;
            if let Some(identity) = cfg.session_identity() {
                let mut qs: Vec<(String, String)> = vec![
                    ("session".into(), identity.to_string()),
                    ("limit".into(), "20".into()),
                ];
                if let Some(created_at) = session_snapshot
                    .as_ref()
                    .and_then(|snapshot| snapshot.session.get("created_at"))
                    .and_then(Value::as_str)
                {
                    qs.push(("since".into(), super::uri_encode(created_at)));
                }
                let query_string = qs
                    .iter()
                    .map(|(k, v)| format!("{k}={v}"))
                    .collect::<Vec<_>>()
                    .join("&");
                match client.get(&format!("/dm?{query_string}")) {
                    Ok(resp) => {
                        inbox_items = collection_items(&resp, &["messages"]);
                        inbox_ok = true;
                    }
                    Err(err) => warnings.push(format!("dm lookup unavailable: {}", err.message)),
                }
            }
            report.insert(
                "inbox".into(),
                json!({
                    "count": inbox_items.len(),
                    "items": inbox_items,
                }),
            );
            update_health(&mut report, "inbox", inbox_ok);

            let git = git_report();
            let git_root = git.get("root").and_then(Value::as_str).map(str::to_string);
            report.insert("git".into(), git);
            update_health(&mut report, "git_repo", git_root.is_some());

            let head = git_head();
            let mut commit_tracking = json!({
                "state": "unavailable",
                "tracked_head": false,
                "head": Value::Null,
                "tracked_count": Value::Null,
                "unlogged_commits": [],
            });
            let mut commits_ok = false;
            if let (Some(identity), Some(head)) = (cfg.session_identity(), head.clone()) {
                match client.get(&format!("/commits?session_id={identity}&limit=200")) {
                    Ok(resp) => {
                        let tracked: HashSet<String> =
                            collection_items(&resp, &["commits", "results"])
                                .iter()
                                .filter_map(|item| item.get("commit_hash").and_then(Value::as_str))
                                .map(str::to_string)
                                .collect();
                        let recent = git_recent_commits(20);
                        let mut unlogged = Vec::new();
                        for hash in recent {
                            if tracked.contains(&hash) {
                                break;
                            }
                            unlogged.push(Value::String(hash));
                        }
                        commit_tracking = json!({
                            "state": "checked",
                            "tracked_head": tracked.contains(&head),
                            "head": head,
                            "tracked_count": tracked.len(),
                            "unlogged_commits": unlogged,
                        });
                        commits_ok = true;
                    }
                    Err(err) => {
                        warnings.push(format!("commit tracking unavailable: {}", err.message))
                    }
                }
            } else if cfg.session_identity().is_none() {
                warnings.push("commit tracking unavailable: missing session identity".into());
            } else if head.is_none() {
                warnings.push("commit tracking unavailable: not inside a git repository".into());
            }
            report.insert("commit_tracking".into(), commit_tracking);
            update_health(&mut report, "commit_tracking", commits_ok);

            if !warnings.is_empty() {
                report.insert("warnings".into(), json!(warnings));
            }

            output::print_json(&Value::Object(report), pretty);
            Ok(())
        }
    }
}

fn update_health(report: &mut serde_json::Map<String, Value>, key: &str, ok: bool) {
    if let Some(health) = report.get_mut("health").and_then(Value::as_object_mut) {
        health.insert(key.to_string(), json!(ok));
    }
}

fn collection_items(resp: &Value, keys: &[&str]) -> Vec<Value> {
    keys.iter()
        .find_map(|k| resp.get(k))
        .and_then(Value::as_array)
        .cloned()
        .unwrap_or_default()
}

fn task_state_id(task: &Value) -> Option<i64> {
    task.get("state_id")
        .and_then(|v| {
            v.as_i64()
                .or_else(|| v.as_str().and_then(|s| s.parse().ok()))
        })
        .or_else(|| {
            task.get("task")
                .and_then(|nested| nested.get("state_id"))
                .and_then(|v| {
                    v.as_i64()
                        .or_else(|| v.as_str().and_then(|s| s.parse().ok()))
                })
        })
}

fn git_report() -> Value {
    let root = git_stdout(&["rev-parse", "--show-toplevel"]);
    let branch = git_stdout(&["rev-parse", "--abbrev-ref", "HEAD"]);
    let head = git_stdout(&["rev-parse", "HEAD"]);
    let dirty_paths = git_dirty_paths();
    json!({
        "cwd": std::env::current_dir().ok().map(|p| p.to_string_lossy().to_string()),
        "root": root,
        "branch": branch,
        "head": head,
        "dirty": !dirty_paths.is_empty(),
        "dirty_paths": dirty_paths,
    })
}

fn git_head() -> Option<String> {
    git_stdout(&["rev-parse", "HEAD"])
}

fn git_recent_commits(limit: usize) -> Vec<String> {
    let arg = format!("--max-count={limit}");
    git_lines(&["rev-list", &arg, "HEAD"]).unwrap_or_default()
}

fn git_dirty_paths() -> Vec<Value> {
    let Some(raw) = git_output(&["status", "--porcelain=v1"]) else {
        return Vec::new();
    };
    raw.lines()
        .into_iter()
        .filter_map(|line| {
            if line.len() < 4 {
                return None;
            }
            let status = line.get(0..2)?.to_string();
            let path = line.get(3..)?.trim().to_string();
            Some(json!({ "status": status, "path": path }))
        })
        .collect()
}

fn git_stdout(args: &[&str]) -> Option<String> {
    let text = git_output(args)?.trim().to_string();
    if text.is_empty() {
        None
    } else {
        Some(text)
    }
}

fn git_lines(args: &[&str]) -> Option<Vec<String>> {
    git_output(args).map(|text| {
        text.lines()
            .map(str::trim)
            .filter(|line| !line.is_empty())
            .map(str::to_string)
            .collect()
    })
}

fn git_output(args: &[&str]) -> Option<String> {
    let output = StdCommand::new("git").args(args).output().ok()?;
    if !output.status.success() {
        return None;
    }
    Some(String::from_utf8_lossy(&output.stdout).to_string())
}

#[cfg(test)]
mod tests {
    use super::*;
    use assert_cmd::Command;

    mod common {
        include!(concat!(env!("CARGO_MANIFEST_DIR"), "/tests/common/mod.rs"));
    }

    fn git(dir: &std::path::Path, args: &[&str]) {
        let status = StdCommand::new("git")
            .args(args)
            .current_dir(dir)
            .status()
            .expect("git command");
        assert!(status.success(), "git {:?} failed", args);
    }

    fn init_git_repo(dir: &std::path::Path) -> String {
        git(dir, &["init"]);
        git(dir, &["config", "user.email", "test@example.com"]);
        git(dir, &["config", "user.name", "Test User"]);
        std::fs::write(dir.join("tracked.txt"), "tracked\n").unwrap();
        git(dir, &["add", "tracked.txt"]);
        git(dir, &["commit", "-m", "tracked commit"]);
        let head = StdCommand::new("git")
            .args(["rev-parse", "HEAD"])
            .current_dir(dir)
            .output()
            .expect("git rev-parse HEAD");
        assert!(head.status.success());
        String::from_utf8(head.stdout).unwrap().trim().to_string()
    }

    #[test]
    fn status_reports_core_checkpoint_data() {
        let repo = tempfile::tempdir().unwrap();
        let head = init_git_repo(repo.path());
        std::fs::write(repo.path().join("dirty.txt"), "dirty\n").unwrap();
        let commit_resp = Box::leak(
            format!(r#"{{"commits":[{{"id":1,"commit_hash":"{}"}}]}}"#, head).into_boxed_str(),
        );

        let srv = common::serve(vec![
            (
                200,
                r#"{"uuid":"s-1","id":7,"agent_id":"agent-1","agent_int_id":11,"project_id":9,"created_at":"2026-08-16T00:00:00Z","worktree_path":"/tmp/worktree"}"#,
            ),
            (
                200,
                r#"{"tasks":[{"id":1,"title":"active","state_id":2},{"id":2,"title":"review","state_id":4},{"id":3,"title":"done","state_id":3}]}"#,
            ),
            (
                200,
                r#"{"teams":[{"id":720,"name":"workflow-checkpoint-9028"}]}"#,
            ),
            (
                200,
                r#"{"messages":[{"id":9,"body":"ping","from_session_id":222,"inserted_at":"2026-08-16T00:00:01Z"}]}"#,
            ),
            (200, commit_resp),
        ]);

        let mut cmd = Command::cargo_bin("eits").unwrap();
        let out = cmd
            .current_dir(repo.path())
            .env("EITS_URL", &srv.url)
            .env("EITS_SESSION_UUID", "s-1")
            .env("EITS_AGENT_UUID", "agent-1")
            .env("EITS_PROJECT_ID", "9")
            .args(["work", "status"])
            .assert()
            .success();

        let stdout = String::from_utf8(out.get_output().stdout.clone()).unwrap();
        let v: serde_json::Value = serde_json::from_str(stdout.trim()).unwrap();
        assert_eq!(v["current_session"]["session_uuid"], "s-1");
        assert_eq!(v["current_session"]["agent_id"], 11);
        assert_eq!(v["current_session"]["project_id"], 9);
        assert_eq!(v["tasks"]["count"], 3);
        assert_eq!(v["tasks"]["active_count"], 2);
        assert_eq!(v["team_memberships"]["count"], 1);
        assert_eq!(v["inbox"]["count"], 1);
        assert_eq!(v["commit_tracking"]["state"], "checked");
        assert_eq!(v["commit_tracking"]["tracked_head"], true);
        assert_eq!(v["git"]["dirty"], true);
        assert!(v.get("warnings").is_none());

        let reqs = srv.finish();
        assert_eq!(reqs.len(), 5);
        assert_eq!(reqs[0].path, "/api/v1/sessions/s-1");
        assert!(reqs[1].path.contains("/api/v1/tasks?session_id=s-1"));
        assert_eq!(reqs[2].path, "/api/v1/teams?member_agent_uuid=agent-1");
        assert!(reqs[3].path.contains("/api/v1/dm?session=s-1"));
        assert!(reqs[4].path.contains("/api/v1/commits?session_id=s-1"));
    }

    #[test]
    fn status_marks_head_unlogged_when_commit_log_is_missing_latest_hash() {
        let repo = tempfile::tempdir().unwrap();
        let _base_head = init_git_repo(repo.path());
        std::fs::write(repo.path().join("second.txt"), "second\n").unwrap();
        git(repo.path(), &["add", "second.txt"]);
        git(repo.path(), &["commit", "-m", "second commit"]);
        let head = StdCommand::new("git")
            .args(["rev-parse", "HEAD"])
            .current_dir(repo.path())
            .output()
            .expect("git rev-parse HEAD");
        assert!(head.status.success());
        let head = String::from_utf8(head.stdout).unwrap().trim().to_string();
        let parent = StdCommand::new("git")
            .args(["rev-parse", "HEAD~1"])
            .current_dir(repo.path())
            .output()
            .expect("git rev-parse HEAD~1");
        assert!(parent.status.success());
        let parent_hash = String::from_utf8(parent.stdout).unwrap().trim().to_string();
        let commit_resp = Box::leak(
            format!(
                r#"{{"commits":[{{"id":1,"commit_hash":"{}"}}]}}"#,
                parent_hash
            )
            .into_boxed_str(),
        );

        let srv = common::serve(vec![
            (
                200,
                r#"{"uuid":"s-1","id":7,"agent_id":"agent-1","agent_int_id":11,"project_id":9,"created_at":"2026-08-16T00:00:00Z"}"#,
            ),
            (200, r#"{"tasks":[]}"#),
            (200, r#"{"teams":[]}"#),
            (200, r#"{"messages":[]}"#),
            (200, commit_resp),
        ]);

        let out = Command::cargo_bin("eits")
            .unwrap()
            .current_dir(repo.path())
            .env("EITS_URL", &srv.url)
            .env("EITS_SESSION_UUID", "s-1")
            .env("EITS_AGENT_UUID", "agent-1")
            .args(["work", "status"])
            .assert()
            .success();
        let stdout = String::from_utf8(out.get_output().stdout.clone()).unwrap();
        let v: serde_json::Value = serde_json::from_str(stdout.trim()).unwrap();
        assert_eq!(v["commit_tracking"]["state"], "checked");
        assert_eq!(v["commit_tracking"]["tracked_head"], false);
        assert_eq!(v["commit_tracking"]["unlogged_commits"][0], head);

        let reqs = srv.finish();
        assert_eq!(reqs.len(), 5);
    }
}
