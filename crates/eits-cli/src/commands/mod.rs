pub mod commits;
pub mod dm;
pub mod notes;
pub mod sessions;
pub mod tasks;
pub mod whoami;
pub mod work;

use serde_json::{json, Value};

/// Percent-encode a query component (mirrors bash's `jq -Rr @uri`).
pub fn uri_encode(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    for b in s.bytes() {
        match b {
            b'A'..=b'Z' | b'a'..=b'z' | b'0'..=b'9' | b'-' | b'_' | b'.' | b'~' => {
                out.push(b as char)
            }
            _ => out.push_str(&format!("%{b:02X}")),
        }
    }
    out
}

pub fn is_numeric(s: &str) -> bool {
    !s.is_empty() && s.chars().all(|c| c.is_ascii_digit())
}

/// Normalize a list response into `{"items": [...], "count": N}`, trying each
/// key in `keys` in order and defaulting to an empty array if none match.
pub fn items_and_count(resp: &Value, keys: &[&str]) -> Value {
    let items = keys
        .iter()
        .find_map(|k| resp.get(k))
        .cloned()
        .unwrap_or_else(|| json!([]));
    let count = items.as_array().map(|a| a.len()).unwrap_or(0);
    json!({ "items": items, "count": count })
}
