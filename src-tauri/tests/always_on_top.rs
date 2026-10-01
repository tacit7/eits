//! Headless regression harness: compile the production setter/toggle against
//! menu/window doubles so these tests never start the desktop app or Phoenix.
//! Run with `rustc --test src-tauri/tests/always_on_top.rs -o /tmp/eits-pin-tests`
//! then `/tmp/eits-pin-tests`.
use std::{fs, process::Command};

#[test]
fn setter_and_toggle_synchronize_both_checkmarks() {
    let source = include_str!("../src/lib.rs");
    let mut functions = String::new();
    for name in [
        "toggle_always_on_top",
        "set_always_on_top",
        "sync_always_on_top_checkmarks",
    ] {
        let Some(start) = source.find(&format!("fn {name}(")) else {
            continue;
        };
        let body = source[start..].find('{').unwrap() + start;
        let mut depth = 1;
        let end = source[body + 1..]
            .char_indices()
            .find_map(|(index, ch)| {
                match ch {
                    '{' => depth += 1,
                    '}' => depth -= 1,
                    _ => {}
                }
                (depth == 0).then_some(body + index + 2)
            })
            .unwrap();
        functions.push_str(&source[start..end]);
        functions.push('\n');
    }
    let directory = std::env::temp_dir().join(format!("eits-pin-test-{}", std::process::id()));
    fs::create_dir_all(&directory).unwrap();
    let input = directory.join("main.rs");
    let binary = directory.join("regression");
    fs::write(&input, format!("{DOUBLES}\n{functions}\n{SCENARIOS}")).unwrap();
    let compiled = Command::new("rustc")
        .args(["--edition=2021", "-Awarnings"])
        .arg(&input)
        .arg("-o")
        .arg(&binary)
        .output()
        .unwrap();
    assert!(
        compiled.status.success(),
        "{}",
        String::from_utf8_lossy(&compiled.stderr)
    );
    let failures: Vec<_> = ["setter", "menu", "tray"]
        .into_iter()
        .filter_map(|scenario| {
            let result = Command::new(&binary).arg(scenario).output().unwrap();
            (!result.status.success())
                .then(|| format!("{scenario}: {}", String::from_utf8_lossy(&result.stderr)))
        })
        .collect();
    fs::remove_dir_all(&directory).unwrap();
    assert!(failures.is_empty(), "{}", failures.join("\n"));
}

const DOUBLES: &str = r#"
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
static ALWAYS_ON_TOP: AtomicBool = AtomicBool::new(false);
#[derive(Clone, Default)]
struct CheckMenuItem(Arc<AtomicBool>);
impl CheckMenuItem {
    fn set_checked(&self, on: bool) -> Result<(), ()> { self.0.store(on, Ordering::Relaxed); Ok(()) }
    fn checked(&self) -> bool { self.0.load(Ordering::Relaxed) }
}
struct TrayAlwaysOnTop(CheckMenuItem);
mod tauri {
    use super::*;
    pub mod menu { pub enum MenuItemKind { Check(super::super::CheckMenuItem) } }
    #[derive(Clone)]
    pub struct AppHandle { pub tray: Arc<TrayAlwaysOnTop>, pub menu: CheckMenuItem, pub window: CheckMenuItem }
    pub struct Menu(CheckMenuItem);
    impl Menu {
        pub fn get(&self, id: &str) -> Option<menu::MenuItemKind> {
            assert_eq!(id, "menu_always_on_top"); Some(menu::MenuItemKind::Check(self.0.clone()))
        }
    }
    impl AppHandle {
        pub fn menu(&self) -> Option<Menu> { Some(Menu(self.menu.clone())) }
        pub fn get_webview_window(&self, _: &str) -> Option<CheckMenuItem> { Some(self.window.clone()) }
        pub fn state<T>(&self) -> &TrayAlwaysOnTop { &self.tray }
    }
}
impl CheckMenuItem {
    fn set_always_on_top(&self, on: bool) -> Result<(), ()> { self.set_checked(on) }
}
"#;

const SCENARIOS: &str = r#"
fn main() {
    let app = tauri::AppHandle { tray: Arc::new(TrayAlwaysOnTop(CheckMenuItem::default())), menu: CheckMenuItem::default(), window: CheckMenuItem::default() };
    let assert_synced = |expected| {
        assert_eq!(app.menu.checked(), expected, "application menu");
        assert_eq!(app.tray.0.checked(), expected, "tray checkmark stale");
        assert_eq!(app.window.checked(), expected, "window");
        assert_eq!(ALWAYS_ON_TOP.load(Ordering::Relaxed), expected, "stored state");
    };
    match std::env::args().nth(1).unwrap().as_str() {
        "setter" => for on in [true, true, false, false] {
            assert_eq!(set_always_on_top(app.clone(), on), on);
            assert_synced(on);
        },
        "menu" => for expected in [true, false] {
            app.menu.set_checked(expected).unwrap();
            toggle_always_on_top(&app);
            assert_synced(expected);
        },
        "tray" => for expected in [true, false] {
            // Native clicks pre-toggle their own check item before dispatch.
            app.tray.0.set_checked(expected).unwrap();
            toggle_always_on_top(&app);
            assert_synced(expected);
        },
        _ => unreachable!(),
    }
}
"#;
