use super::{items_and_count, uri_encode};
use crate::config::Config;
use crate::duration;
use crate::error::{Code, EitsError};
use crate::http::Client;
use crate::output;
use serde_json::{json, Value};

#[derive(clap::Subcommand)]
pub enum CommitsCmd {
    /// List tracked commits (session-scoped by default)
    List {
        #[arg(short = 's', long)]
        session: Option<String>,
        #[arg(short = 'p', long)]
        project: Option<String>,
        #[arg(short = 'l', long)]
        limit: Option<String>,
        /// Only commits after this hash (server-side, via since_hash)
        #[arg(long)]
        since: Option<String>,
        /// Only commits since this duration ago, e.g. 24h / 7d / 30m
        #[arg(long = "since-time")]
        since_time: Option<String>,
    },
    /// Track one or more git commits
    Create {
        #[arg(short = 'a', long)]
        agent: Option<String>,
        /// Commit hash to track (repeatable)
        #[arg(long = "hash")]
        hashes: Vec<String>,
        /// Commit message, positionally paired with --hash (repeatable)
        #[arg(short = 'm', long = "message")]
        messages: Vec<String>,
    },
}

/// Resolve the agent uuid to attribute commits to: explicit --agent, else
/// EITS_AGENT_UUID, else look it up from the current session.
fn resolve_agent_id(
    client: &Client,
    cfg: &Config,
    agent_flag: Option<String>,
) -> Result<String, EitsError> {
    if let Some(a) = agent_flag {
        if !a.is_empty() {
            return Ok(a);
        }
    }
    if let Ok(a) = std::env::var("EITS_AGENT_UUID") {
        if !a.is_empty() {
            return Ok(a);
        }
    }
    if let Some(uuid) = &cfg.session_uuid {
        if let Ok(resp) = client.get(&format!("/sessions/{uuid}")) {
            if let Some(a) = resp.get("agent_uuid").and_then(|v| v.as_str()) {
                if !a.is_empty() {
                    return Ok(a.to_string());
                }
            }
        }
    }
    Err(EitsError::usage(
        "agent_id is required (or set EITS_AGENT_UUID)",
    ))
}

fn first_error_message(v: &Value) -> String {
    match v {
        Value::String(s) => s.clone(),
        other => other.to_string(),
    }
}

pub fn run(
    client: &Client,
    cfg: &Config,
    cmd: CommitsCmd,
    pretty: bool,
    quiet: bool,
) -> Result<(), EitsError> {
    match cmd {
        CommitsCmd::List {
            session,
            project,
            limit,
            since,
            since_time,
        } => {
            let mut qs: Vec<(String, String)> = Vec::new();
            if let Some(p) = &project {
                qs.push(("project_id".into(), p.clone()));
            }
            match &session {
                Some(s) => qs.push(("session_id".into(), s.clone())),
                None => {
                    if let Some(identity) = cfg.session_identity() {
                        qs.push(("session_id".into(), identity.to_string()));
                    }
                }
            }
            if let Some(h) = &since {
                qs.push(("since_hash".into(), uri_encode(h)));
            }
            if let Some(l) = &limit {
                qs.push(("limit".into(), l.clone()));
            }
            if let Some(spec) = &since_time {
                let iso = duration::to_iso8601_utc(spec, std::time::SystemTime::now())?;
                qs.push(("since_time".into(), uri_encode(&iso)));
            }
            let query_string = qs
                .iter()
                .map(|(k, v)| format!("{k}={v}"))
                .collect::<Vec<_>>()
                .join("&");
            let resp = client.get(&format!("/commits?{query_string}"))?;
            output::print_json(&items_and_count(&resp, &["commits", "results"]), pretty);
            Ok(())
        }

        CommitsCmd::Create {
            agent,
            hashes,
            messages,
        } => {
            if hashes.is_empty() {
                return Err(EitsError::usage("commits create: --hash is required"));
            }
            let agent_id = resolve_agent_id(client, cfg, agent)?;
            let mut payload = json!({
                "agent_id": agent_id,
                "commit_hashes": hashes,
            });
            if !messages.is_empty() {
                payload["commit_messages"] = json!(messages);
            }
            let resp = client.post("/commits", payload)?;

            let commits = resp
                .get("commits")
                .and_then(Value::as_array)
                .cloned()
                .unwrap_or_default();
            let duplicates = resp
                .get("duplicates")
                .and_then(Value::as_array)
                .cloned()
                .unwrap_or_default();
            let errors = resp
                .get("errors")
                .and_then(Value::as_array)
                .cloned()
                .unwrap_or_default();

            if let Some(first) = errors.first() {
                return Err(EitsError::api(
                    first_error_message(first),
                    Code::Validation,
                    None,
                ));
            }

            if !commits.is_empty() {
                if quiet {
                    let id = commits[0]
                        .get("id")
                        .map(|v| match v {
                            Value::String(s) => s.clone(),
                            other => other.to_string(),
                        })
                        .ok_or_else(|| {
                            EitsError::api("response has no commit id", Code::ServerError, None)
                        })?;
                    println!("{id}");
                } else {
                    output::print_json(&json!({ "status": "created", "commits": commits }), pretty);
                }
                return Ok(());
            }

            if !duplicates.is_empty() {
                if quiet {
                    return Err(EitsError::usage(
                        "commits create --quiet: already-tracked commits have no id to print",
                    ));
                }
                output::print_json(
                    &json!({ "status": "already_tracked", "duplicates": duplicates }),
                    pretty,
                );
                return Ok(());
            }

            if quiet {
                return Err(EitsError::usage(
                    "commits create --quiet: response had no commit id",
                ));
            }
            output::print_json(&resp, pretty);
            Ok(())
        }
    }
}
