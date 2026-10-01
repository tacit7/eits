use crate::error::{Code, EitsError};
use std::ffi::OsString;
use std::path::PathBuf;

/// Spec: discovery order — EITS_EXTRAS, ../libexec/eits-extras,
/// sibling eits-extras, legacy eits-extras on PATH.
pub fn find_extras() -> Result<PathBuf, EitsError> {
    find_extras_with_source().map(|(path, _)| path)
}

/// Resolve only: never execute the selected fallback.
pub fn find_extras_with_source() -> Result<(PathBuf, &'static str), EitsError> {
    if let Ok(p) = std::env::var("EITS_EXTRAS") {
        let p = PathBuf::from(p);
        return if is_executable_file(&p) {
            Ok((p, "EITS_EXTRAS"))
        } else {
            Err(EitsError::api(
                format!("EITS_EXTRAS={} is not an executable file", p.display()),
                Code::ExtrasNotFound,
                None,
            )
            .with_hint("Point EITS_EXTRAS at an executable eits-extras script"))
        };
    }

    let me = std::env::current_exe()
        .ok()
        .and_then(|p| p.canonicalize().ok());
    if let Some(me) = &me {
        if let Some(bin_dir) = me.parent() {
            for (cand, source) in [
                (bin_dir.join("../libexec/eits-extras"), "libexec"),
                (bin_dir.join("eits-extras"), "sibling"),
            ] {
                if is_executable_file(&cand) {
                    return Ok((cand, source));
                }
            }
        }
    }

    if let Some(path_eits_extras) = which_on_path("eits-extras") {
        let canon = path_eits_extras.canonicalize().ok();
        if canon.is_some() && canon != me {
            return Ok((path_eits_extras, "PATH"));
        }
    }

    Err(EitsError::api(
        "no extras script found (set EITS_EXTRAS or install eits-extras on PATH)",
        Code::ExtrasNotFound,
        None,
    )
    .with_hint("set EITS_EXTRAS or install eits-extras on PATH"))
}

fn is_executable_file(p: &std::path::Path) -> bool {
    use std::os::unix::fs::PermissionsExt;
    p.is_file()
        && p.metadata()
            .map(|m| m.permissions().mode() & 0o111 != 0)
            .unwrap_or(false)
}

fn which_on_path(name: &str) -> Option<PathBuf> {
    std::env::var_os("PATH").and_then(|paths| {
        std::env::split_paths(&paths)
            .map(|d| d.join(name))
            .find(|p| is_executable_file(p))
    })
}

pub fn exec_extras(path: &std::path::Path, args: &[OsString]) -> std::io::Error {
    use std::io::Write;
    use std::os::unix::process::CommandExt;
    // Keep arguments and paths private, and never let a diagnostic prevent delegation.
    let _ = std::io::stderr()
        .write_all(b"[eits] delegating to legacy eits-extras; output format may differ\n");
    std::process::Command::new(path).args(args).exec()
}
