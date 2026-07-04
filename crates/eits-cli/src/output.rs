pub fn pretty_enabled(cli_pretty: bool) -> bool {
    cli_pretty
        || std::env::var("EITS_PRETTY")
            .map(|v| v == "1")
            .unwrap_or(false)
}

pub fn print_json(v: &serde_json::Value, pretty: bool) {
    if pretty {
        println!("{}", serde_json::to_string_pretty(v).expect("serializable"));
    } else {
        println!("{}", serde_json::to_string(v).expect("serializable"));
    }
}

// Wired up once `--quiet` mutation commands land (later tasks).
#[allow(dead_code)]
pub fn quiet_id(v: &serde_json::Value, pointer: &str) -> Result<String, crate::error::EitsError> {
    v.pointer(pointer)
        .map(|id| match id {
            serde_json::Value::String(s) => s.clone(),
            other => other.to_string(),
        })
        .ok_or_else(|| {
            crate::error::EitsError::api(
                format!("response has no id at {pointer}"),
                crate::error::Code::ServerError,
                None,
            )
        })
}

#[allow(dead_code)]
pub fn print_quiet_id(v: &serde_json::Value, pointer: &str) -> Result<(), crate::error::EitsError> {
    println!("{}", quiet_id(v, pointer)?);
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn quiet_extracts_id_by_pointer() {
        let v = serde_json::json!({"task": {"id": 123}});
        assert_eq!(quiet_id(&v, "/task/id").unwrap(), "123");
        let v2 = serde_json::json!({"session": {"uuid": "abc-def"}});
        assert_eq!(quiet_id(&v2, "/session/uuid").unwrap(), "abc-def");
        assert!(quiet_id(&v, "/nope").is_err());
    }
}
