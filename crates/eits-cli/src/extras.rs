use crate::error::{Code, EitsError};
use std::ffi::OsString;
use std::path::PathBuf;

/// Spec: discovery order — EITS_EXTRAS, ../libexec/eits-extras, sibling,
/// bash `eits` on PATH (guarding self-exec), bundled app path (later).
pub fn find_extras() -> Result<PathBuf, EitsError> {
    if let Ok(p) = std::env::var("EITS_EXTRAS") {
        let p = PathBuf::from(p);
        return if is_executable_file(&p) {
            Ok(p)
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
            for cand in [
                bin_dir.join("../libexec/eits-extras"),
                bin_dir.join("eits-extras"),
            ] {
                if is_executable_file(&cand) {
                    return Ok(cand);
                }
            }
        }
    }

    // Migration period: bash `eits` on PATH, but never exec ourselves.
    if let Some(path_eits) = which_on_path("eits") {
        let canon = path_eits.canonicalize().ok();
        if canon.is_some() && canon != me {
            return Ok(path_eits);
        }
    }

    Err(EitsError::api(
        "no extras script found (set EITS_EXTRAS or install scripts/eits on PATH)",
        Code::ExtrasNotFound,
        None,
    )
    .with_hint("set EITS_EXTRAS or install scripts/eits on PATH"))
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
    use std::os::unix::process::CommandExt;
    std::process::Command::new(path).args(args).exec()
}
