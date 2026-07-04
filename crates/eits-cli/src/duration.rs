// consumed by Task 7
#[allow(dead_code)]
pub fn to_iso8601_utc(
    spec: &str,
    now: std::time::SystemTime,
) -> Result<String, crate::error::EitsError> {
    let (num, unit) = spec.split_at(spec.len().saturating_sub(1));
    let n: u64 = num.parse().map_err(|_| {
        crate::error::EitsError::usage(format!(
            "invalid duration: {spec} (expected <N>m, <N>h, or <N>d)"
        ))
    })?;
    let secs = match unit {
        "m" => n * 60,
        "h" => n * 3600,
        "d" => n * 86400,
        _ => {
            return Err(crate::error::EitsError::usage(format!(
                "invalid duration unit: {spec}"
            )))
        }
    };
    let ts = now.duration_since(std::time::UNIX_EPOCH).unwrap().as_secs() - secs;
    // days-since-epoch → civil date (Howard Hinnant algorithm), no chrono dep
    let (days, rem) = (ts / 86400, ts % 86400);
    let (h, m, s) = (rem / 3600, (rem % 3600) / 60, rem % 60);
    let z = days as i64 + 719_468;
    let era = z.div_euclid(146_097);
    let doe = z.rem_euclid(146_097);
    let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365;
    let y = yoe + era * 400;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let d = doy - (153 * mp + 2) / 5 + 1;
    let mo = if mp < 10 { mp + 3 } else { mp - 9 };
    let y = if mo <= 2 { y + 1 } else { y };
    Ok(format!("{y:04}-{mo:02}-{d:02}T{h:02}:{m:02}:{s:02}Z"))
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::time::{Duration, UNIX_EPOCH};

    fn at(secs: u64) -> std::time::SystemTime {
        UNIX_EPOCH + Duration::from_secs(secs)
    }

    #[test]
    fn parses_hours_ago() {
        // 2026-07-04T00:00:00Z minus 24h = 2026-07-03T00:00:00Z
        let now = at(1783123200);
        assert_eq!(to_iso8601_utc("24h", now).unwrap(), "2026-07-03T00:00:00Z");
    }

    #[test]
    fn parses_days_ago() {
        let now = at(1783123200);
        assert_eq!(to_iso8601_utc("7d", now).unwrap(), "2026-06-27T00:00:00Z");
    }

    #[test]
    fn parses_minutes_ago() {
        let now = at(1783123200);
        assert_eq!(to_iso8601_utc("30m", now).unwrap(), "2026-07-03T23:30:00Z");
    }

    #[test]
    fn rejects_garbage_unit() {
        let now = at(1783123200);
        let err = to_iso8601_utc("xyz", now).unwrap_err();
        assert_eq!(err.exit_code(), 2);
    }

    #[test]
    fn rejects_unsupported_unit_suffix() {
        let now = at(1783123200);
        let err = to_iso8601_utc("5w", now).unwrap_err();
        assert_eq!(err.exit_code(), 2);
    }
}
