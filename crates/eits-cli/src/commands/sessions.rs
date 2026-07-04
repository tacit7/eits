use super::{items_and_count, uri_encode};
use crate::config::Config;
use crate::error::EitsError;
use crate::http::Client;
use crate::output;
use serde_json::{json, Value};

#[derive(clap::Subcommand)]
pub enum SessionsCmd {
    /// List sessions (project-scoped by default; see mutual-exclusion rules below)
    List {
        // No short flag: the global `-q`/`--quiet` already claims `-q`.
        #[arg(long = "search")]
        search: Option<String>,
        #[arg(short = 'n', long)]
        name: Option<String>,
        #[arg(long)]
        status: Option<String>,
        #[arg(short = 'p', long)]
        project: Option<String>,
        #[arg(long)]
        agent: Option<String>,
        #[arg(long = "agent-slug")]
        agent_slug: Option<String>,
        #[arg(long)]
        parent: Option<String>,
        #[arg(long)]
        mine: bool,
        #[arg(short = 'l', long)]
        limit: Option<String>,
        #[arg(long)]
        include_archived: bool,
        #[arg(long)]
        with_tasks: bool,
        /// Accepted for muscle-memory parity with bash; Rust output is always JSON.
        #[arg(short = 'j', long = "json")]
        json_flag: bool,
    },
    /// Fetch a single session by uuid or id
    Get { id: String },
    /// Create a session
    Create {
        #[arg(long = "session-id")]
        session_id: String,
        #[arg(long)]
        name: Option<String>,
        #[arg(long)]
        description: Option<String>,
        #[arg(long = "project-name")]
        project_name: Option<String>,
        #[arg(long = "project-path")]
        project_path: Option<String>,
        #[arg(long)]
        model: Option<String>,
        #[arg(long)]
        entrypoint: Option<String>,
        #[arg(long = "read-only")]
        read_only: bool,
    },
    /// Patch session fields
    Update {
        uuid: String,
        #[arg(long)]
        status: Option<String>,
        #[arg(long)]
        reason: Option<String>,
        #[arg(long)]
        intent: Option<String>,
        #[arg(long)]
        entrypoint: Option<String>,
        #[arg(long)]
        name: Option<String>,
        #[arg(long)]
        description: Option<String>,
        #[arg(long = "clear-entrypoint")]
        clear_entrypoint: bool,
        #[arg(long = "ended-at")]
        ended_at: Option<String>,
        #[arg(long)]
        project: Option<String>,
        #[arg(long = "worktree-path")]
        worktree_path: Option<String>,
    },
    /// End a session (defaults uuid to the current session identity)
    End {
        uuid: Option<String>,
        #[arg(long = "final-status")]
        final_status: Option<String>,
    },
    /// Mark the current (or given) session complete
    Complete { uuid: Option<String> },
    /// Mark the current (or given) session waiting
    Waiting { uuid: Option<String> },
    /// Reopen an ended session
    Reopen { uuid: Option<String> },
    /// Archive a session
    Archive { uuid: String },
    /// Unarchive a session
    Unarchive { uuid: String },
    /// Declare read-only intent (review) or work mode
    SetIntent { mode: String, uuid: Option<String> },
    /// Get or set session context
    Context {
        uuid: Option<String>,
        #[arg(long)]
        text: Option<String>,
        #[arg(long)]
        metadata: Option<String>,
    },
}

fn resolve_uuid(cfg: &Config, uuid: Option<String>) -> Result<String, EitsError> {
    match uuid {
        Some(u) if u == "self" => cfg
            .session_identity()
            .map(|s| s.to_string())
            .ok_or_else(|| EitsError::usage("'self' requires EITS_SESSION_UUID to be set")),
        Some(u) => Ok(u),
        None => cfg
            .session_identity()
            .map(|s| s.to_string())
            .ok_or_else(|| {
                EitsError::usage(
                    "session UUID required (pass as argument or set EITS_SESSION_UUID)",
                )
            }),
    }
}

pub fn run(
    client: &Client,
    cfg: &Config,
    cmd: SessionsCmd,
    pretty: bool,
    quiet: bool,
) -> Result<(), EitsError> {
    match cmd {
        SessionsCmd::List {
            search,
            name,
            status,
            project,
            agent,
            agent_slug,
            parent,
            mine,
            limit,
            include_archived,
            with_tasks,
            json_flag: _,
        } => {
            let other_flag =
                search.is_some() || name.is_some() || status.is_some() || project.is_some();
            if agent.is_some() && (other_flag || mine) {
                return Err(EitsError::usage(
                    "--agent is mutually exclusive with --search, --status, --project, and --mine",
                ));
            }
            if mine && (agent.is_some() || other_flag) {
                return Err(EitsError::usage(
                    "--mine cannot combine with --agent, --search, --status, and --project",
                ));
            }
            if name.is_some() && (agent.is_some() || mine) {
                return Err(EitsError::usage(
                    "--name cannot combine with --agent or --mine",
                ));
            }

            let mut qs: Vec<(String, String)> = Vec::new();
            let project_flag = project.is_some();
            if let Some(q) = &search {
                qs.push(("q".into(), uri_encode(q)));
            }
            if let Some(n) = &name {
                qs.push(("name".into(), uri_encode(n)));
            }
            if let Some(s) = &status {
                qs.push(("status".into(), s.clone()));
            }
            if let Some(p) = &project {
                qs.push(("project_id".into(), p.clone()));
            }
            if let Some(a) = &agent {
                qs.push(("agent_id".into(), a.clone()));
            }
            if let Some(a) = &agent_slug {
                qs.push(("agent_def_slug".into(), uri_encode(a)));
            }
            if let Some(p) = &parent {
                qs.push(("parent_session_id".into(), p.clone()));
            }
            let agent_flag = agent.is_some();
            let mut mine_flag = false;
            if mine {
                mine_flag = true;
                let identity = cfg.session_identity().ok_or_else(|| {
                    EitsError::usage(
                        "--mine requires EITS_SESSION_UUID or EITS_SESSION_ID to be set",
                    )
                })?;
                qs.push(("session_id".into(), identity.to_string()));
            }
            if let Some(l) = &limit {
                qs.push(("limit".into(), l.clone()));
            }
            if include_archived {
                qs.push(("include_archived".into(), "true".into()));
            }
            if with_tasks {
                qs.push(("with_tasks".into(), "true".into()));
            }
            // Project scope: explicit --project wins, then EITS_PROJECT_ID, then cwd path.
            if !project_flag && !agent_flag && !mine_flag {
                if let Some(pid) = &cfg.project_id {
                    qs.push(("project_id".into(), pid.clone()));
                } else if let Ok(cwd) = std::env::current_dir() {
                    qs.push(("path".into(), uri_encode(&cwd.to_string_lossy())));
                }
            }
            let query_string = qs
                .iter()
                .map(|(k, v)| format!("{k}={v}"))
                .collect::<Vec<_>>()
                .join("&");
            let resp = client.get(&format!("/sessions?{query_string}"))?;
            output::print_json(&items_and_count(&resp, &["results", "sessions"]), pretty);
            Ok(())
        }

        SessionsCmd::Get { id } => {
            let v = client.get(&format!("/sessions/{id}"))?;
            let session = v.get("session").cloned().unwrap_or(v);
            output::print_json(&json!({ "session": session }), pretty);
            Ok(())
        }

        SessionsCmd::Create {
            session_id,
            name,
            description,
            project_name,
            project_path,
            model,
            entrypoint,
            read_only,
        } => {
            let body = json!({
                "session_id": session_id,
                "name": name.unwrap_or_default(),
                "description": description.unwrap_or_default(),
                "project_name": project_name.unwrap_or_default(),
                "project_path": project_path.unwrap_or_default(),
                "model": model.unwrap_or_default(),
                "entrypoint": entrypoint.unwrap_or_default(),
                "read_only": read_only,
            });
            let resp = client.post("/sessions", body)?;
            if quiet {
                output::print_quiet_id(&resp, "/session/uuid")
                    .or_else(|_| output::print_quiet_id(&resp, "/uuid"))?;
            } else {
                output::print_json(&resp, pretty);
            }
            Ok(())
        }

        SessionsCmd::Update {
            uuid,
            status,
            reason,
            intent,
            entrypoint,
            name,
            description,
            clear_entrypoint,
            ended_at,
            project,
            worktree_path,
        } => {
            let mut updates = serde_json::Map::new();
            if let Some(s) = &status {
                updates.insert("status".into(), json!(s));
            }
            if let Some(r) = &reason {
                updates.insert("status_reason".into(), json!(r));
            }
            if let Some(i) = &intent {
                updates.insert("intent".into(), json!(i));
            }
            if let Some(e) = &entrypoint {
                updates.insert("entrypoint".into(), json!(e));
            }
            if let Some(n) = &name {
                updates.insert("name".into(), json!(n));
            }
            if let Some(d) = &description {
                updates.insert("description".into(), json!(d));
            }
            if clear_entrypoint {
                updates.insert("clear_entrypoint".into(), json!(true));
            }
            if let Some(e) = &ended_at {
                updates.insert("ended_at".into(), json!(e));
            }
            if let Some(p) = &project {
                updates.insert("project_id".into(), json!(p));
            }
            if let Some(w) = &worktree_path {
                updates.insert("worktree_path".into(), json!(w));
            }
            let resp = client.patch(&format!("/sessions/{uuid}"), Value::Object(updates))?;
            if quiet {
                println!("{uuid}");
            } else {
                output::print_json(&resp, pretty);
            }
            Ok(())
        }

        SessionsCmd::End { uuid, final_status } => {
            let uuid = resolve_uuid(cfg, uuid)?;
            let body = match &final_status {
                Some(fs) => json!({ "final_status": fs }),
                None => json!({}),
            };
            let resp = client.post(&format!("/sessions/{uuid}/end"), body)?;
            if quiet {
                println!("{uuid}");
            } else {
                output::print_json(&resp, pretty);
            }
            Ok(())
        }

        SessionsCmd::Complete { uuid } => {
            let uuid = resolve_uuid(cfg, uuid)?;
            let resp = client.post(&format!("/sessions/{uuid}/complete"), json!({}))?;
            if quiet {
                println!("{uuid}");
            } else {
                output::print_json(&resp, pretty);
            }
            Ok(())
        }

        SessionsCmd::Waiting { uuid } => {
            let uuid = resolve_uuid(cfg, uuid)?;
            let resp = client.post(&format!("/sessions/{uuid}/waiting"), json!({}))?;
            if quiet {
                println!("{uuid}");
            } else {
                output::print_json(&resp, pretty);
            }
            Ok(())
        }

        SessionsCmd::Reopen { uuid } => {
            let uuid = resolve_uuid(cfg, uuid)?;
            let resp = client.post(&format!("/sessions/{uuid}/reopen"), json!({}))?;
            if quiet {
                println!("{uuid}");
            } else {
                output::print_json(&resp, pretty);
            }
            Ok(())
        }

        SessionsCmd::Archive { uuid } => {
            let resp = client.post(&format!("/sessions/{uuid}/archive"), json!({}))?;
            if quiet {
                println!("{uuid}");
            } else {
                output::print_json(&resp, pretty);
            }
            Ok(())
        }

        SessionsCmd::Unarchive { uuid } => {
            let resp = client.post(&format!("/sessions/{uuid}/unarchive"), json!({}))?;
            if quiet {
                println!("{uuid}");
            } else {
                output::print_json(&resp, pretty);
            }
            Ok(())
        }

        SessionsCmd::SetIntent { mode, uuid } => {
            if mode != "review" && mode != "work" {
                return Err(EitsError::usage(
                    "set-intent requires 'review' or 'work' as the first argument",
                ));
            }
            let uuid = resolve_uuid(cfg, uuid)?;
            let read_only = mode == "review";
            let resp = client.patch(
                &format!("/sessions/{uuid}"),
                json!({ "read_only": read_only }),
            )?;
            if quiet {
                println!("{uuid}");
            } else {
                output::print_json(&resp, pretty);
            }
            Ok(())
        }

        SessionsCmd::Context {
            uuid,
            text,
            metadata,
        } => {
            let uuid = resolve_uuid(cfg, uuid)?;
            match &text {
                Some(t) => {
                    let mut body = serde_json::Map::new();
                    body.insert("context".into(), json!(t));
                    if let Some(m) = &metadata {
                        let parsed: Value = serde_json::from_str(m).map_err(|e| {
                            EitsError::usage(format!("--metadata is not valid JSON: {e}"))
                        })?;
                        body.insert("metadata".into(), parsed);
                    }
                    let resp =
                        client.patch(&format!("/sessions/{uuid}/context"), Value::Object(body))?;
                    if quiet {
                        println!("{uuid}");
                    } else {
                        output::print_json(&resp, pretty);
                    }
                    Ok(())
                }
                None => {
                    let resp = client.get(&format!("/sessions/{uuid}/context"))?;
                    output::print_json(&resp, pretty);
                    Ok(())
                }
            }
        }
    }
}
