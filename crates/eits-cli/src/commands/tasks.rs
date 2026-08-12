use crate::config::Config;
use crate::error::{Code, EitsError};
use crate::http::Client;
use crate::output;
use serde_json::{json, Value};
use std::io::Write;

#[derive(clap::Subcommand)]
pub enum TasksCmd {
    /// List tasks (session-scoped by default; pass --all to see everything)
    List {
        #[arg(short = 's', long)]
        session: Option<String>,
        #[arg(short = 'p', long)]
        project: Option<String>,
        #[arg(short = 'l', long)]
        limit: Option<String>,
        // No short flag: the global `-q`/`--quiet` already claims `-q`.
        #[arg(long)]
        query: Option<String>,
        #[arg(long)]
        tag: Option<String>,
        /// List tasks for a team id.
        #[arg(long)]
        team: Option<String>,
        #[arg(long)]
        mine: bool,
        #[arg(long)]
        all: bool,
        /// Accepted for muscle-memory parity with bash; Rust output is always JSON.
        #[arg(short = 'j', long = "json")]
        json_flag: bool,
    },
    /// Fetch a single task by id
    Get { id: String },
    /// Attach an existing tag to a task (tag ids: `eits tags list`)
    Tag { task_id: String, tag_id: String },
    /// Claim an existing task (--id) or create + claim a new one (-t/--title)
    Begin {
        #[arg(long)]
        id: Option<String>,
        #[arg(short = 't', long)]
        title: Option<String>,
        #[arg(short = 'd', long)]
        description: Option<String>,
        #[arg(short = 'p', long)]
        project: Option<String>,
        #[arg(long)]
        priority: Option<String>,
        #[arg(long = "tag")]
        tags: Vec<String>,
    },
    /// Atomic annotate + close (Done)
    Complete {
        id: String,
        #[arg(short = 'm', long)]
        message: String,
        #[arg(long = "commit")]
        commits: Vec<String>,
        #[arg(long)]
        notify: Option<String>,
    },
    /// Add an annotation to a task
    Annotate {
        id: String,
        #[arg(short = 'b', long)]
        body: String,
        #[arg(short = 't', long)]
        title: Option<String>,
    },
    /// Patch task fields
    Update {
        id: String,
        #[arg(short = 's', long)]
        state: Option<String>,
        #[arg(short = 't', long)]
        title: Option<String>,
        #[arg(short = 'd', long)]
        description: Option<String>,
    },
    /// Full-text task search
    Search {
        query: String,
        #[arg(short = 'p', long)]
        project: Option<String>,
        #[arg(short = 'l', long)]
        limit: Option<String>,
        #[arg(long)]
        state: Option<String>,
    },
    /// Task-centric team status view
    Status {
        /// Team id to inspect.
        #[arg(long)]
        team: String,
        #[arg(short = 'l', long)]
        limit: Option<String>,
        /// Accepted for parity with other task read commands; output is always JSON.
        #[arg(short = 'j', long = "json")]
        json_flag: bool,
    },
    /// Show workflow state ids, names, and accepted aliases
    States,
    /// Create a task without claiming it
    Create {
        #[arg(short = 't', long)]
        title: String,
        #[arg(short = 'p', long)]
        project: Option<String>,
        #[arg(long)]
        team: Option<String>,
        #[arg(short = 'd', long)]
        description: Option<String>,
        #[arg(long)]
        priority: Option<String>,
    },
    /// Claim an existing task (link session + set In Progress)
    Claim { id: String },
    /// Delete a task
    Delete { id: String },
    /// In Progress + In Review tasks for the current session
    Active,
    /// Apply the same update to multiple tasks at once
    BulkUpdate {
        #[arg(long)]
        ids: Option<String>,
        #[arg(long)]
        session: Option<String>,
        #[arg(long)]
        state: Option<String>,
        #[arg(long)]
        priority: Option<String>,
        #[arg(long)]
        title: Option<String>,
    },
    /// Link a session to a task
    LinkSession { id: String, session: Option<String> },
}

use super::{is_numeric, items_and_count, uri_encode};

/// Single source of truth for workflow-state names and their accepted alias
/// strings. `aliases[0]` is the canonical value sent to the server. Both
/// `apply_update_state` (the `update`/`begin`/`claim` alias resolver) and the
/// `states` command derive from this table so they cannot drift apart.
const STATE_ALIAS_TABLE: &[(i64, &str, &[&str])] = &[
    (1, "To Do", &["todo", "to-do", "to do"]),
    (
        2,
        "In Progress",
        &["start", "in-progress", "progress", "in progress"],
    ),
    (3, "Done", &["done", "complete", "completed"]),
    (4, "In Review", &["in-review", "review", "in review"]),
];

/// Port of bash `update`'s `_resolve_state`: numeric input remaps workflow
/// position (1-4) to the actual DB state_id (3 and 4 are swapped); named
/// input maps aliases from `STATE_ALIAS_TABLE` to their canonical string,
/// passing through anything unrecognized unchanged.
fn apply_update_state(updates: &mut serde_json::Map<String, Value>, v: &str) {
    if is_numeric(v) {
        let n: i64 = v.parse().unwrap_or(0);
        let sid = match n {
            1 => 1,
            2 => 2,
            3 => 4,
            4 => 3,
            other => other,
        };
        updates.insert("state_id".into(), json!(sid));
    } else {
        let lower = v.to_lowercase();
        let normalized = STATE_ALIAS_TABLE
            .iter()
            .find(|(_, _, aliases)| aliases.contains(&lower.as_str()))
            .map(|(_, _, aliases)| aliases[0])
            .unwrap_or(v);
        updates.insert("state".into(), json!(normalized));
    }
}

fn states_payload() -> Value {
    let items: Vec<Value> = STATE_ALIAS_TABLE
        .iter()
        .map(|(id, name, aliases)| json!({ "id": id, "name": name, "aliases": aliases }))
        .collect();
    let count = items.len();
    json!({ "items": items, "count": count })
}

pub fn run(
    client: &Client,
    cfg: &Config,
    cmd: TasksCmd,
    pretty: bool,
    quiet: bool,
) -> Result<(), EitsError> {
    match cmd {
        TasksCmd::Get { id } => {
            let v = client.get(&format!("/tasks/{id}"))?;
            // The server's envelope carries project_id / annotations / state_id
            // as SIBLINGS of .task, not inside it — graft them into the task
            // object so normalization is lossless (found via ticket 8108: a
            // task's project_id read as null through eits but 1 through bash).
            let mut task = v.get("task").cloned().unwrap_or_else(|| v.clone());
            if let Some(obj) = task.as_object_mut() {
                for key in ["project_id", "annotations", "state_id"] {
                    if !obj.contains_key(key) || obj[key].is_null() {
                        if let Some(side) = v.get(key) {
                            if !side.is_null() {
                                obj.insert(key.to_string(), side.clone());
                            }
                        }
                    }
                }
            }
            output::print_json(&json!({ "task": task }), pretty);
            Ok(())
        }

        TasksCmd::Tag { task_id, tag_id } => {
            let v = client.post(
                &format!("/tasks/{task_id}/tags"),
                json!({ "tag_id": tag_id }),
            )?;
            output::print_json(&v, pretty);
            Ok(())
        }

        TasksCmd::List {
            session,
            project,
            limit,
            query,
            tag,
            team,
            mine,
            all,
            json_flag: _,
        } => {
            if mine && session.is_some() {
                return Err(EitsError::usage(
                    "--mine/--assigned and --session are mutually exclusive",
                ));
            }
            let mut qs: Vec<(String, String)> = Vec::new();
            let project_flag = project.is_some();
            if let Some(p) = &project {
                qs.push(("project_id".into(), p.clone()));
            }
            if let Some(s) = &session {
                qs.push(("session_id".into(), s.clone()));
            }
            let tag_flag = tag.is_some();
            if let Some(t) = &tag {
                if is_numeric(t) {
                    qs.push(("tag_id".into(), t.clone()));
                } else {
                    let resp = client.get(&format!("/tags?q={}", uri_encode(t)))?;
                    let id = resp
                        .get("tags")
                        .and_then(|v| v.as_array())
                        .and_then(|arr| {
                            arr.iter().find(|o| {
                                o.get("name").and_then(|n| n.as_str()) == Some(t.as_str())
                            })
                        })
                        .and_then(|o| o.get("id"))
                        .cloned();
                    match id {
                        Some(id_val) => qs.push(("tag_id".into(), id_val.to_string())),
                        None => return Err(EitsError::usage(format!("tag not found: {t}"))),
                    }
                }
            }
            let team_flag = team.is_some();
            if let Some(t) = &team {
                qs.push(("team_id".into(), t.clone()));
            }
            if let Some(q) = &query {
                qs.push(("q".into(), uri_encode(q)));
            }
            let limit_flag = limit.is_some();
            if let Some(l) = &limit {
                qs.push(("limit".into(), l.clone()));
            }
            let mut mine_flag = false;
            if mine {
                mine_flag = true;
                let identity = cfg.session_identity().ok_or_else(|| {
                    EitsError::usage(
                        "--mine/--assigned requires EITS_SESSION_UUID or EITS_SESSION_ID to be set",
                    )
                })?;
                qs.push(("session_id".into(), identity.to_string()));
            }
            // Default session scope: only when nothing else already scoped the query.
            if !all && session.is_none() && !mine_flag && !tag_flag && !team_flag {
                if let Some(identity) = cfg.session_identity() {
                    qs.push(("session_id".into(), identity.to_string()));
                }
            }
            // Project default: explicit --project wins, else EITS_PROJECT_ID, else cwd.
            if !project_flag && !team_flag {
                if let Some(pid) = &cfg.project_id {
                    qs.push(("project_id".into(), pid.clone()));
                } else if let Ok(cwd) = std::env::current_dir() {
                    qs.push(("path".into(), uri_encode(&cwd.to_string_lossy())));
                }
            }
            if !limit_flag {
                qs.push(("limit".into(), "200".into()));
            }
            let query_string = qs
                .iter()
                .map(|(k, v)| format!("{k}={v}"))
                .collect::<Vec<_>>()
                .join("&");
            let resp = client.get(&format!("/tasks?{query_string}"))?;
            output::print_json(&items_and_count(&resp, &["tasks", "results"]), pretty);
            Ok(())
        }

        TasksCmd::Status {
            team,
            limit,
            json_flag: _,
        } => {
            let limit = limit.unwrap_or_else(|| "500".into());
            let resp = client.get(&format!("/tasks?team_id={team}&limit={limit}"))?;
            output::print_json(&items_and_count(&resp, &["tasks", "results"]), pretty);
            Ok(())
        }

        TasksCmd::Begin {
            id,
            title,
            description,
            project,
            priority,
            tags,
        } => {
            let identity = cfg.session_identity().unwrap_or("").to_string();

            if let Some(task_id) = id {
                let resp = client.post(
                    &format!("/tasks/{task_id}/claim"),
                    json!({ "session_id": identity }),
                )?;
                for t in &tags {
                    if let Err(e) =
                        client.post(&format!("/tasks/{task_id}/tags"), json!({ "tag_id": t }))
                    {
                        eprintln!(
                            "warning: failed to apply tag {t} to task {task_id}: {}",
                            e.message
                        );
                    }
                }
                if quiet {
                    println!("{task_id}");
                } else {
                    output::print_json(&resp, pretty);
                }
                return Ok(());
            }

            let title = title.ok_or_else(|| {
                EitsError::usage("begin: --title is required when --id is not given")
            })?;
            let project_id = project.or_else(|| cfg.project_id.clone());
            let body = json!({
                "title": title,
                "description": description.unwrap_or_default(),
                "project_id": project_id,
                "priority": priority,
                "session_id": identity,
            });
            let create_resp = client.post("/tasks", body)?;
            // The server sends `task_id` as a JSON number in some responses
            // and as a numeric string in others (confirmed live) — accept both.
            let task_id = create_resp
                .get("task_id")
                .and_then(|v| {
                    v.as_i64()
                        .or_else(|| v.as_str().and_then(|s| s.parse().ok()))
                })
                .ok_or_else(|| EitsError::api("task creation failed", Code::ServerError, None))?;
            client.patch(
                &format!("/tasks/{task_id}"),
                json!({ "state": "start", "session_id": identity }),
            )?;
            if !identity.is_empty() {
                let _ = client.post(
                    &format!("/tasks/{task_id}/sessions"),
                    json!({ "session_id": identity }),
                );
            }
            for t in &tags {
                if let Err(e) =
                    client.post(&format!("/tasks/{task_id}/tags"), json!({ "tag_id": t }))
                {
                    eprintln!(
                        "warning: failed to apply tag {t} to task {task_id}: {}",
                        e.message
                    );
                }
            }
            if quiet {
                println!("{task_id}");
            } else {
                let full = client.get(&format!("/tasks/{task_id}"))?;
                let task = full.get("task").cloned().unwrap_or_else(|| json!({}));
                output::print_json(
                    &json!({
                        "task_id": task.get("id").cloned().unwrap_or(json!(task_id)),
                        "title": task.get("title").cloned().unwrap_or(Value::Null),
                        "state": task.get("state").cloned().unwrap_or(Value::Null),
                        "state_id": task.get("state_id").cloned().unwrap_or(Value::Null),
                        "message": "Task created",
                    }),
                    pretty,
                );
            }
            Ok(())
        }

        TasksCmd::Complete {
            id,
            message,
            commits,
            notify,
        } => {
            let check = client.get(&format!("/tasks/{id}"))?;
            // Same class of bug as tasks begin's task_id: the server can send
            // state_id as a numeric string, which .as_i64() alone would miss.
            let state_id = check
                .get("task")
                .and_then(|t| t.get("state_id"))
                .or_else(|| check.get("state_id"))
                .and_then(|v| {
                    v.as_i64()
                        .or_else(|| v.as_str().and_then(|s| s.parse().ok()))
                });
            if state_id == Some(3) {
                let task_id_val = id
                    .parse::<i64>()
                    .map(Value::from)
                    .unwrap_or_else(|_| Value::String(id.clone()));
                output::print_json(
                    &json!({
                        "status": "already_closed",
                        "message": "task is already Done — no change made",
                        "task_id": task_id_val,
                    }),
                    pretty,
                );
                return Ok(());
            }

            let identity = cfg.session_identity().unwrap_or("").to_string();
            let resp = client.post(
                &format!("/tasks/{id}/complete"),
                json!({ "message": message, "session_id": identity }),
            )?;

            for hash in &commits {
                if let Err(e) = client.post("/commits", json!({ "hash": hash })) {
                    eprintln!(
                        "warning: task closed but commit {hash} could not be tracked: {}",
                        e.message
                    );
                }
            }

            if let Some(to) = &notify {
                let dm_message = format!("Task {id} completed");
                if let Err(e) =
                    super::dm::send_dm(client, cfg, to, &dm_message, Some(&identity), None, false)
                {
                    eprintln!("warning: task closed but DM to {to} failed: {}", e.message);
                }
            }

            if quiet {
                println!("{id}");
            } else {
                output::print_json(&resp, pretty);
            }
            Ok(())
        }

        TasksCmd::Annotate { id, body, title } => {
            let title_val = title.unwrap_or_default();
            let payload = json!({ "body": body, "title": title_val });
            match client.post(&format!("/tasks/{id}/annotations"), payload) {
                Ok(resp) => {
                    if quiet {
                        println!("{id}");
                    } else {
                        output::print_json(&resp, pretty);
                    }
                    Ok(())
                }
                Err(_) => {
                    let home = std::env::var("HOME").unwrap_or_default();
                    let dir = std::path::PathBuf::from(home).join(".eits");
                    let _ = std::fs::create_dir_all(&dir);
                    let line =
                        json!({ "task_id": id, "body": body, "title": title_val }).to_string();
                    let path = dir.join("pending-annotations.log");
                    if let Ok(mut f) = std::fs::OpenOptions::new()
                        .create(true)
                        .append(true)
                        .open(&path)
                    {
                        let _ = writeln!(f, "{line}");
                    }
                    eprintln!(
                        "annotate failed after retries — queued to ~/.eits/pending-annotations.log"
                    );
                    std::process::exit(1);
                }
            }
        }

        TasksCmd::Update {
            id,
            state,
            title,
            description,
        } => {
            let mut updates = serde_json::Map::new();
            if let Some(s) = &state {
                apply_update_state(&mut updates, s);
            }
            if let Some(t) = &title {
                updates.insert("title".into(), json!(t));
            }
            if let Some(d) = &description {
                updates.insert("description".into(), json!(d));
            }
            let resp = client.patch(&format!("/tasks/{id}"), Value::Object(updates))?;
            if quiet {
                println!("{id}");
            } else {
                output::print_json(&resp, pretty);
            }
            Ok(())
        }

        TasksCmd::Search {
            query,
            project,
            limit,
            state,
        } => {
            let mut qs = format!("q={}", uri_encode(&query));
            if let Some(p) = project.or_else(|| cfg.project_id.clone()) {
                qs.push_str(&format!("&project_id={p}"));
            }
            if let Some(l) = &limit {
                qs.push_str(&format!("&limit={l}"));
            }
            if let Some(s) = &state {
                qs.push_str(&format!("&state_id={s}"));
            }
            let resp = client.get(&format!("/tasks?{qs}"))?;
            output::print_json(&items_and_count(&resp, &["tasks", "results"]), pretty);
            Ok(())
        }

        TasksCmd::States => {
            output::print_json(&states_payload(), pretty);
            Ok(())
        }

        TasksCmd::Create {
            title,
            project,
            team,
            description,
            priority,
        } => {
            let identity = cfg.session_identity().unwrap_or("").to_string();
            let project_id = project.or_else(|| cfg.project_id.clone());
            let body = json!({
                "title": title,
                "description": description.unwrap_or_default(),
                "project_id": project_id,
                "team_id": team,
                "priority": priority,
                "session_id": identity,
            });
            let resp = client.post("/tasks", body)?;
            if quiet {
                output::print_quiet_id(&resp, "/task_id")?;
            } else {
                output::print_json(&resp, pretty);
            }
            Ok(())
        }

        TasksCmd::Claim { id } => {
            let identity = cfg.session_identity().unwrap_or("").to_string();
            let resp = client.post(
                &format!("/tasks/{id}/claim"),
                json!({ "session_id": identity }),
            )?;
            if quiet {
                println!("{id}");
            } else {
                output::print_json(&resp, pretty);
            }
            Ok(())
        }

        TasksCmd::Delete { id } => {
            let resp = client.delete(&format!("/tasks/{id}"))?;
            if quiet {
                println!("{id}");
            } else {
                output::print_json(&resp, pretty);
            }
            Ok(())
        }

        TasksCmd::Active => {
            let identity = cfg.session_identity().ok_or_else(|| {
                EitsError::usage("active: EITS_SESSION_UUID or EITS_SESSION_ID is required")
            })?;
            let resp2 = client.get(&format!("/tasks?session_id={identity}&state_id=2&limit=20"))?;
            let resp4 = client.get(&format!("/tasks?session_id={identity}&state_id=4&limit=20"))?;
            let mut items: Vec<Value> = resp2
                .get("tasks")
                .and_then(|v| v.as_array())
                .cloned()
                .unwrap_or_default();
            if let Some(arr4) = resp4.get("tasks").and_then(|v| v.as_array()) {
                items.extend(arr4.clone());
            }
            let count = items.len();
            output::print_json(&json!({ "items": items, "count": count }), pretty);
            Ok(())
        }

        TasksCmd::BulkUpdate {
            ids,
            session,
            state,
            priority,
            title,
        } => {
            if ids.is_some() && session.is_some() {
                return Err(EitsError::usage(
                    "--ids and --session are mutually exclusive",
                ));
            }
            let mut updates = serde_json::Map::new();
            if let Some(s) = &state {
                if is_numeric(s) {
                    updates.insert("state_id".into(), json!(s.parse::<i64>().unwrap_or(0)));
                } else {
                    updates.insert("state".into(), json!(s));
                }
            }
            if let Some(p) = &priority {
                updates.insert("priority".into(), json!(p));
            }
            if let Some(t) = &title {
                updates.insert("title".into(), json!(t));
            }
            if updates.is_empty() {
                return Err(EitsError::usage(
                    "at least one field to update is required (--state, --priority, --title)",
                ));
            }

            let id_list: Vec<String> = if let Some(session_id) = &session {
                let resp = client.get(&format!("/tasks?session_id={session_id}&limit=200"))?;
                resp.get("tasks")
                    .and_then(|v| v.as_array())
                    .map(|arr| {
                        arr.iter()
                            .filter_map(|t| t.get("id"))
                            .map(|v| match v {
                                Value::String(s) => s.clone(),
                                other => other.to_string(),
                            })
                            .collect()
                    })
                    .unwrap_or_default()
            } else {
                let raw = ids
                    .clone()
                    .ok_or_else(|| EitsError::usage("--ids or --session is required"))?;
                raw.split(',')
                    .map(|s| s.trim().to_string())
                    .filter(|s| !s.is_empty())
                    .collect()
            };

            let mut results = Vec::new();
            for task_id in &id_list {
                let ok = client
                    .patch(&format!("/tasks/{task_id}"), Value::Object(updates.clone()))
                    .is_ok();
                results.push(json!({ "id": task_id, "ok": ok }));
            }
            let count = results.len();
            if quiet {
                println!("{}", id_list.join(","));
            } else {
                output::print_json(&json!({ "items": results, "count": count }), pretty);
            }
            Ok(())
        }

        TasksCmd::LinkSession { id, session } => {
            let session_id = session
                .or_else(|| cfg.session_identity().map(|s| s.to_string()))
                .ok_or_else(|| {
                    EitsError::usage(
                        "session_uuid is required (or set EITS_SESSION_UUID / EITS_SESSION_ID)",
                    )
                })?;
            let resp = client.post(
                &format!("/tasks/{id}/sessions"),
                json!({ "session_id": session_id }),
            )?;
            if quiet {
                println!("{id}");
            } else {
                output::print_json(&resp, pretty);
            }
            Ok(())
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Guards against `states` and `apply_update_state` drifting apart again:
    /// every alias the `states` command advertises must actually normalize to
    /// that state's canonical value via the same resolver `update`/`begin`
    /// use.
    #[test]
    fn every_states_alias_is_accepted_by_update_resolver() {
        let payload = states_payload();
        let items = payload["items"].as_array().unwrap();
        assert_eq!(items.len(), STATE_ALIAS_TABLE.len());
        for (_, _, aliases) in STATE_ALIAS_TABLE {
            let canonical = aliases[0];
            for alias in *aliases {
                let mut updates = serde_json::Map::new();
                apply_update_state(&mut updates, alias);
                assert_eq!(
                    updates.get("state").and_then(|v| v.as_str()),
                    Some(canonical),
                    "alias {alias:?} did not normalize to canonical {canonical:?}"
                );
            }
        }
    }
}
