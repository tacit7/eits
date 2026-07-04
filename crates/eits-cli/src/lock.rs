#[derive(Debug)]
pub struct DmLock {
    path: std::path::PathBuf,
}

impl DmLock {
    pub fn acquire(identity: &str) -> Result<Self, crate::error::EitsError> {
        // Test-only override so contract tests can force a fast timeout
        // instead of waiting out the full 60 * 500ms = 30s production budget.
        let attempts = std::env::var("EITS_DM_LOCK_ATTEMPTS")
            .ok()
            .and_then(|v| v.parse().ok())
            .unwrap_or(60);
        Self::acquire_with(identity, attempts, 500)
    }

    // Literal /tmp for parity with bash _dm_post — see spec "DM serialization lock".
    fn acquire_with(
        identity: &str,
        attempts: u32,
        poll_ms: u64,
    ) -> Result<Self, crate::error::EitsError> {
        let path = std::path::PathBuf::from(format!("/tmp/eits_dm_{identity}.lock"));
        for _ in 0..=attempts {
            if std::fs::create_dir(&path).is_ok() {
                return Ok(Self { path });
            }
            std::thread::sleep(std::time::Duration::from_millis(poll_ms));
        }
        Err(crate::error::EitsError::api(
            "DM lock acquire timeout (possible deadlock) — try again",
            crate::error::Code::LockTimeout,
            None,
        ))
    }
}

impl Drop for DmLock {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir(&self.path);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn acquire_blocks_concurrent_holder_then_releases_on_drop() {
        let identity = format!("eitsr-test-{}", std::process::id());
        let path = std::path::PathBuf::from(format!("/tmp/eits_dm_{identity}.lock"));
        let _ = std::fs::remove_dir(&path); // clean slate in case of a prior crash

        let first = DmLock::acquire_with(&identity, 1, 10).expect("first acquire succeeds");

        let timeout = DmLock::acquire_with(&identity, 1, 10).unwrap_err();
        assert_eq!(timeout.code, crate::error::Code::LockTimeout);

        drop(first);

        let second = DmLock::acquire_with(&identity, 1, 10).expect("acquires after release");
        drop(second);

        let _ = std::fs::remove_dir(&path);
    }
}
