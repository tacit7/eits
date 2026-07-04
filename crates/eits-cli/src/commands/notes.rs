use super::{items_and_count, uri_encode};
use crate::config::Config;
use crate::error::EitsError;
use crate::http::Client;
use crate::output;
use serde_json::{json, Value};

#[derive(clap::Subcommand)]
pub enum NotesCmd {
    /// List notes (session-scoped by default; pass --task/--project/--mine to override)
    List {
        #[arg(short = 's', long)]
        session: Option<String>,
        #[arg(short = 'T', long)]
        task: Option<String>,
        #[arg(short = 'p', long)]
        project: Option<String>,
        #[arg(long)]
        mine: bool,
        #[arg(long)]
        starred: bool,
        #[arg(short = 'l', long)]
        limit: Option<String>,
        /// Accepted for muscle-memory parity with bash; Rust output is never truncated.
        #[arg(long)]
        full: bool,
        /// Accepted for muscle-memory parity with bash; Rust output is always JSON.
        #[arg(short = 'j', long = "json")]
        json_flag: bool,
    },
    /// Fetch a single note by id
    Get { id: String },
    /// Add a note attached to the current session
    Add {
        #[arg(short = 'b', long)]
        body: String,
        #[arg(short = 't', long)]
        title: Option<String>,
        #[arg(long)]
        starred: bool,
    },
    /// Create a note attached to an arbitrary parent
    Create {
        #[arg(long = "parent-type")]
        parent_type: String,
        #[arg(long = "parent-id")]
        parent_id: String,
        #[arg(short = 'b', long)]
        body: String,
        #[arg(short = 't', long)]
        title: Option<String>,
        #[arg(long)]
        starred: bool,
    },
    /// Patch note fields
    Update {
        id: String,
        #[arg(short = 'b', long)]
        body: Option<String>,
        #[arg(short = 't', long)]
        title: Option<String>,
        #[arg(long)]
        starred: bool,
    },
    /// Full-text note search
    Search {
        query: String,
        #[arg(short = 'p', long)]
        project: Option<String>,
        #[arg(long)]
        starred: bool,
        #[arg(short = 'l', long)]
        limit: Option<String>,
        /// Accepted for muscle-memory parity with bash; Rust output is never truncated.
        #[arg(long)]
        full: bool,
    },
}

/// Extract the created/patched note's id, trying `/note/id` (bash-style nested
/// envelope) before falling back to `/id` (the real API's flat response).
fn quiet_note_id(v: &Value) -> Result<String, EitsError> {
    output::quiet_id(v, "/note/id").or_else(|_| output::quiet_id(v, "/id"))
}

pub fn run(
    client: &Client,
    cfg: &Config,
    cmd: NotesCmd,
    pretty: bool,
    quiet: bool,
) -> Result<(), EitsError> {
    match cmd {
        NotesCmd::List {
            session,
            task,
            project,
            mine,
            starred,
            limit,
            full: _,
            json_flag: _,
        } => {
            if mine && session.is_some() {
                return Err(EitsError::usage(
                    "--mine and --session are mutually exclusive",
                ));
            }
            let mut qs: Vec<(String, String)> = Vec::new();
            if let Some(s) = &session {
                qs.push(("session_id".into(), s.clone()));
            }
            if let Some(t) = &task {
                qs.push(("task_id".into(), t.clone()));
            }
            if let Some(p) = &project {
                qs.push(("project_id".into(), p.clone()));
            }
            if starred {
                qs.push(("starred".into(), "true".into()));
            }
            if let Some(l) = &limit {
                qs.push(("limit".into(), l.clone()));
            }
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
            // Agent-centric default: scope to current session unless overridden.
            if session.is_none() && !mine_flag && task.is_none() {
                if let Some(identity) = cfg.session_identity() {
                    qs.push(("session_id".into(), identity.to_string()));
                }
            }
            let query_string = qs
                .iter()
                .map(|(k, v)| format!("{k}={v}"))
                .collect::<Vec<_>>()
                .join("&");
            let resp = client.get(&format!("/notes?{query_string}"))?;
            output::print_json(&items_and_count(&resp, &["results", "notes"]), pretty);
            Ok(())
        }

        NotesCmd::Get { id } => {
            let v = client.get(&format!("/notes/{id}"))?;
            let note = v.get("note").cloned().unwrap_or(v);
            output::print_json(&json!({ "note": note }), pretty);
            Ok(())
        }

        NotesCmd::Add {
            body,
            title,
            starred,
        } => {
            let parent_id = cfg.session_identity().ok_or_else(|| {
                EitsError::usage("add: EITS_SESSION_UUID or EITS_SESSION_ID is required")
            })?;
            let payload = json!({
                "parent_type": "session",
                "parent_id": parent_id,
                "body": body,
                "title": title.unwrap_or_default(),
                "starred": starred,
            });
            let resp = client.post("/notes", payload)?;
            if quiet {
                println!("{}", quiet_note_id(&resp)?);
            } else {
                output::print_json(&resp, pretty);
            }
            Ok(())
        }

        NotesCmd::Create {
            parent_type,
            parent_id,
            body,
            title,
            starred,
        } => {
            let payload = json!({
                "parent_type": parent_type,
                "parent_id": parent_id,
                "body": body,
                "title": title.unwrap_or_default(),
                "starred": starred,
            });
            let resp = client.post("/notes", payload)?;
            if quiet {
                println!("{}", quiet_note_id(&resp)?);
            } else {
                output::print_json(&resp, pretty);
            }
            Ok(())
        }

        NotesCmd::Update {
            id,
            body,
            title,
            starred,
        } => {
            let mut updates = serde_json::Map::new();
            if let Some(b) = &body {
                updates.insert("body".into(), json!(b));
            }
            if let Some(t) = &title {
                updates.insert("title".into(), json!(t));
            }
            if starred {
                updates.insert("starred".into(), json!(true));
            }
            let resp = client.patch(&format!("/notes/{id}"), Value::Object(updates))?;
            if quiet {
                println!("{id}");
            } else {
                output::print_json(&resp, pretty);
            }
            Ok(())
        }

        NotesCmd::Search {
            query,
            project,
            starred,
            limit,
            full: _,
        } => {
            let mut qs = format!("q={}", uri_encode(&query));
            if let Some(p) = &project {
                qs.push_str(&format!("&project_id={p}"));
            }
            if starred {
                qs.push_str("&starred=true");
            }
            if let Some(l) = &limit {
                qs.push_str(&format!("&limit={l}"));
            }
            let resp = client.get(&format!("/notes?{qs}"))?;
            output::print_json(&items_and_count(&resp, &["results", "notes"]), pretty);
            Ok(())
        }
    }
}
