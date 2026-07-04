use super::{items_and_count, uri_encode};
use crate::config::Config;
use crate::error::EitsError;
use crate::http::Client;
use crate::output;
use serde_json::{json, Value};
use std::collections::HashSet;

#[derive(clap::Subcommand)]
pub enum DmCmd {
    /// Show inbound DMs for a session (alias: list)
    #[command(alias = "list")]
    Inbox {
        #[arg(short = 's', long)]
        session: Option<String>,
        #[arg(short = 'f', long)]
        from: Option<String>,
        #[arg(short = 'l', long, short_alias = 'n')]
        limit: Option<String>,
        #[arg(long)]
        since: Option<String>,
        #[arg(long = "since-session")]
        since_session: bool,
        #[arg(long = "team-only")]
        team_only: bool,
        /// Accepted for muscle-memory parity with bash; Rust output is always JSON.
        #[arg(short = 'j', long = "json")]
        json_flag: bool,
    },
    /// Fetch one DM by id (full body)
    Read {
        id: String,
        /// Accepted for muscle-memory parity with bash; Rust output is always JSON.
        #[arg(short = 'j', long = "json")]
        json_flag: bool,
    },
}

/// Bash `_dm_post` payload shape: `{from_session_id, to_session_id, message,
/// response_required[, metadata]}`. Shared by `dm` send and `tasks complete
/// --notify` so both build the exact same body.
pub fn build_payload(
    from: &str,
    to: &str,
    message: &str,
    response_required: bool,
    metadata: Option<Value>,
) -> Value {
    let mut body = json!({
        "from_session_id": from,
        "to_session_id": to,
        "message": message,
        "response_required": response_required,
    });
    if let Some(m) = metadata {
        body["metadata"] = m;
    }
    body
}

/// Validates `--metadata`, resolves `--from` (default: session identity),
/// acquires the DM serialization lock around the POST only, and posts to
/// `/dm`. Shared by `dm` send and `tasks complete --notify`.
pub fn send_dm(
    client: &Client,
    cfg: &Config,
    to: &str,
    message: &str,
    from: Option<&str>,
    metadata: Option<&str>,
    response_required: bool,
) -> Result<Value, EitsError> {
    let from = from
        .map(String::from)
        .or_else(|| cfg.session_identity().map(String::from))
        .ok_or_else(|| {
            EitsError::usage("dm: --from is required (or set EITS_SESSION_UUID/EITS_SESSION_ID)")
        })?;
    let metadata_val = match metadata {
        Some(m) => Some(
            serde_json::from_str::<Value>(m)
                .map_err(|e| EitsError::usage(format!("--metadata must be valid JSON: {e}")))?,
        ),
        None => None,
    };
    let payload = build_payload(&from, to, message, response_required, metadata_val);
    let lock_identity = cfg.session_identity().unwrap_or("default");
    let _guard = crate::lock::DmLock::acquire(lock_identity)?;
    client.post("/dm", payload)
}

#[allow(clippy::too_many_arguments)]
pub fn run(
    client: &Client,
    cfg: &Config,
    cmd: Option<DmCmd>,
    to: Option<String>,
    message: Option<String>,
    from: Option<String>,
    metadata: Option<String>,
    response_required: bool,
    pretty: bool,
    quiet: bool,
) -> Result<(), EitsError> {
    match cmd {
        Some(DmCmd::Inbox {
            session,
            from,
            limit,
            since,
            since_session,
            team_only,
            json_flag: _,
        }) => {
            let session = session
                .or_else(|| cfg.session_identity().map(|s| s.to_string()))
                .ok_or_else(|| {
                    EitsError::usage(
                        "dm inbox: session is required (pass --session or set EITS_SESSION_UUID/EITS_SESSION_ID)",
                    )
                })?;

            let mut since = since;
            if since_session {
                match client.get(&format!("/sessions/{session}")) {
                    Ok(v) => {
                        let ts = v
                            .get("created_at")
                            .and_then(|t| t.as_str())
                            .or_else(|| {
                                v.get("session")
                                    .and_then(|s| s.get("created_at"))
                                    .and_then(|t| t.as_str())
                            })
                            .map(String::from);
                        match ts {
                            Some(ts) => since = Some(ts),
                            None => eprintln!(
                                "warning: --since-session: could not resolve session created_at; showing all DMs"
                            ),
                        }
                    }
                    Err(_) => eprintln!(
                        "warning: --since-session: could not resolve session created_at; showing all DMs"
                    ),
                }
            }

            let mut qs: Vec<(String, String)> = vec![
                ("session".into(), session),
                ("limit".into(), limit.unwrap_or_else(|| "20".into())),
            ];
            if let Some(f) = &from {
                qs.push(("from".into(), f.clone()));
            }
            if let Some(s) = &since {
                qs.push(("since".into(), uri_encode(s)));
            }
            let query_string = qs
                .iter()
                .map(|(k, v)| format!("{k}={v}"))
                .collect::<Vec<_>>()
                .join("&");
            let mut resp = client.get(&format!("/dm?{query_string}"))?;

            if team_only {
                match std::env::var("EITS_AGENT_UUID").ok() {
                    None => {
                        eprintln!("warning: --team-only requires EITS_AGENT_UUID; showing all DMs")
                    }
                    Some(agent_uuid) => {
                        let allowed = resolve_team_session_ids(client, &agent_uuid);
                        if let Some(messages) = resp.get("messages").and_then(|v| v.as_array()) {
                            let filtered: Vec<Value> = messages
                                .iter()
                                .filter(|m| {
                                    m.get("from_session_id")
                                        .map(|fid| allowed.contains(&value_to_key(fid)))
                                        .unwrap_or(false)
                                })
                                .cloned()
                                .collect();
                            let count = filtered.len();
                            resp["messages"] = json!(filtered);
                            resp["count"] = json!(count);
                        }
                    }
                }
            }

            output::print_json(&items_and_count(&resp, &["messages"]), pretty);
            Ok(())
        }

        Some(DmCmd::Read { id, json_flag: _ }) => {
            let qs = cfg
                .session_identity()
                .map(|s| format!("?session={s}"))
                .unwrap_or_default();
            let resp = client.get(&format!("/dm/{id}{qs}"))?;
            output::print_json(&resp, pretty);
            Ok(())
        }

        None => {
            let to = to.ok_or_else(|| EitsError::usage("dm: --to is required"))?;
            let message = message.ok_or_else(|| EitsError::usage("dm: --message is required"))?;
            let resp = send_dm(
                client,
                cfg,
                &to,
                &message,
                from.as_deref(),
                metadata.as_deref(),
                response_required,
            )?;
            if quiet {
                match resp.get("message_id") {
                    Some(id) => {
                        println!("{}", value_to_key(id));
                        Ok(())
                    }
                    None => Err(EitsError::usage(
                        "dm: --quiet requires a response with a message id",
                    )),
                }
            } else {
                output::print_json(&resp, pretty);
                Ok(())
            }
        }
    }
}

/// Port of bash `--team-only`: collect session ids of every member across
/// every team the given agent belongs to. Failures degrade to an empty
/// allow-list (matching bash's best-effort `|| _teams_json="{}"`).
fn resolve_team_session_ids(client: &Client, agent_uuid: &str) -> HashSet<String> {
    let mut allowed = HashSet::new();
    let teams_resp = client
        .get(&format!(
            "/teams?member_agent_uuid={}",
            uri_encode(agent_uuid)
        ))
        .unwrap_or_else(|_| json!({}));
    let Some(team_ids) = teams_resp.get("teams").and_then(|v| v.as_array()) else {
        return allowed;
    };
    for t in team_ids {
        let Some(tid) = t.get("id") else { continue };
        let tid = value_to_key(tid);
        if let Ok(members_resp) = client.get(&format!("/teams/{tid}/members")) {
            if let Some(members) = members_resp.get("members").and_then(|v| v.as_array()) {
                for m in members {
                    if let Some(sid) = m.get("session_id") {
                        allowed.insert(value_to_key(sid));
                    }
                }
            }
        }
    }
    allowed
}

fn value_to_key(v: &Value) -> String {
    match v {
        Value::String(s) => s.clone(),
        other => other.to_string(),
    }
}
