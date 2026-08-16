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
        /// Only commits since this duration ago, e.g. 24h / 7d / 30m.
        /// Filtered client-side (bash parity): the server doesn't implement
        /// this filter server-side, so results missing a timestamp field are
        /// excluded entirely, same as bash.
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
    if let Some(a) = &cfg.agent_uuid {
        if !a.is_empty() {
            return Ok(a.to_string());
        }
    }
    if let Some(uuid) = &cfg.session_uuid {
        if let Ok(resp) = client.get(&format!("/sessions/{uuid}")) {
            let session = resp.get("session").unwrap_or(&resp);
            if let Some(a) = session
                .get("agent_uuid")
                .or_else(|| session.get("agent_id"))
                .and_then(|v| v.as_str())
            {
                if !a.is_empty() {
                    return Ok(a.to_string());
                }
            }
        }
    }
    Err(EitsError::usage(
        "agent_id is required (set EITS_AGENT_UUID, EITS_CODEX_ENV_FILE, or EITS_CODEX_SESSION_ID; if the Codex session id is unknown, ask the user for it)",
    ))
}

fn first_error_message(v: &Value) -> String {
    match v {
        Value::String(s) => s.clone(),
        other => other.to_string(),
    }
}

/// Client-side `--since-time` filter, ported from bash's fallback (the server
/// doesn't implement `created_at_since` — confirmed in commit_controller.ex —
/// so bash always applies this filter after the fact, and so do we).
///
/// Compares the first 19 chars (`YYYY-MM-DDTHH:MM:SS`) of `inserted_at` /
/// `created_at` against the same prefix of `cutoff_iso`: fixed-width ISO8601
/// UTC timestamps order identically as strings and as instants, so no date
/// parsing is needed. An item with neither timestamp field is excluded, same
/// as bash's `select` (`. == "" then false`).
fn passes_since_time(item: &Value, cutoff_iso: &str) -> bool {
    let ts = item
        .get("inserted_at")
        .and_then(Value::as_str)
        .or_else(|| item.get("created_at").and_then(Value::as_str))
        .unwrap_or("");
    match (ts.get(..19), cutoff_iso.get(..19)) {
        (Some(item_prefix), Some(cutoff_prefix)) => item_prefix >= cutoff_prefix,
        _ => false,
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
            let cutoff = match &since_time {
                Some(spec) => Some(duration::to_iso8601_utc(
                    spec,
                    std::time::SystemTime::now(),
                )?),
                None => None,
            };
            if let Some(iso) = &cutoff {
                // Sent for forward-compatibility only: the server doesn't
                // implement this filter (confirmed in commit_controller.ex),
                // so we always re-filter client-side below, same as bash.
                qs.push(("created_at_since".into(), uri_encode(iso)));
            }
            let query_string = qs
                .iter()
                .map(|(k, v)| format!("{k}={v}"))
                .collect::<Vec<_>>()
                .join("&");
            let mut resp = client.get(&format!("/commits?{query_string}"))?;
            if let Some(cutoff_iso) = &cutoff {
                for key in ["commits", "results"] {
                    if let Some(arr) = resp.get_mut(key).and_then(Value::as_array_mut) {
                        arr.retain(|item| passes_since_time(item, cutoff_iso));
                        break;
                    }
                }
            }
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
            if let Some(identity) = cfg.session_identity() {
                payload["session_id"] = json!(identity);
            }
            if !messages.is_empty() {
                payload["commit_messages"] = json!(messages);
            }
            let resp = client.post("/commits", payload).map_err(|err| {
                if err.message.contains("server returned HTML") {
                    err.with_hint(
                        "commits API returned HTML instead of JSON; verify EITS_URL points at /api/v1 and check the server-side API error path",
                    )
                } else {
                    err
                }
            })?;

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

            let has_commits = !commits.is_empty();
            let has_duplicates = !duplicates.is_empty();
            let has_errors = !errors.is_empty();

            // Pure failure: the batch produced errors and nothing was created
            // or already tracked — nothing was persisted, so this is the only
            // case that's a hard error (exit 1, validation envelope).
            if has_errors && !has_commits && !has_duplicates {
                return Err(EitsError::api(
                    first_error_message(&errors[0]),
                    Code::Validation,
                    None,
                ));
            }

            // Any other combination means at least one hash was persisted
            // (created or already-tracked) — surface everything the batch
            // did rather than silently dropping data, exit 0.
            let status = if has_errors || (has_commits && has_duplicates) {
                "partial"
            } else if has_commits {
                "created"
            } else {
                "already_tracked"
            };

            if quiet {
                if has_commits {
                    for c in &commits {
                        let id = c
                            .get("id")
                            .map(|v| match v {
                                Value::String(s) => s.clone(),
                                other => other.to_string(),
                            })
                            .ok_or_else(|| {
                                EitsError::api("response has no commit id", Code::ServerError, None)
                            })?;
                        println!("{id}");
                    }
                    return Ok(());
                }
                return Err(EitsError::usage(
                    "commits create --quiet: no created commit id to print",
                ));
            }

            let mut out = json!({ "status": status });
            if has_commits {
                out["commits"] = json!(commits);
            }
            if has_duplicates {
                out["duplicates"] = json!(duplicates);
            }
            if has_errors {
                out["errors"] = json!(errors);
            }
            output::print_json(&out, pretty);
            Ok(())
        }
    }
}
