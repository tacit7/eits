use std::sync::atomic::{AtomicU32, Ordering};
use tauri::Manager;
use tauri::menu::{Menu, MenuItem, PredefinedMenuItem, Submenu};
use tauri::tray::{MouseButton, MouseButtonState, TrayIconBuilder, TrayIconEvent};
use tauri_plugin_clipboard_manager::ClipboardExt;
use tauri_plugin_deep_link::DeepLinkExt;
use tauri_plugin_global_shortcut::{GlobalShortcutExt, Shortcut, ShortcutState};

/// Monotonic counter for generating unique secondary window labels.
static WINDOW_COUNTER: AtomicU32 = AtomicU32::new(2);

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    let pubsub = elixirkit::PubSub::listen("tcp://127.0.0.1:0").expect("failed to listen");

    tauri::Builder::default()
        .plugin(tauri_plugin_single_instance::init(|app, argv, _cwd| {
            show_window(app);
            for arg in argv.iter().skip(1) {
                if arg.starts_with("eits://") {
                    route_deep_link(app, arg);
                }
            }
        }))
        .plugin(tauri_plugin_deep_link::init())
        .plugin(tauri_plugin_opener::init())
        .plugin(tauri_plugin_window_state::Builder::default().build())
        .plugin(tauri_plugin_notification::init())
        .plugin(tauri_plugin_global_shortcut::Builder::new().build())
        .plugin(tauri_plugin_clipboard_manager::init())
        .plugin(tauri_plugin_dialog::init())
        .setup(move |app| {
            // --- System tray with navigation ---
            let show_item = MenuItem::with_id(app, "show", "Show EITS", true, None::<&str>)?;
            let sep1 = PredefinedMenuItem::separator(app)?;
            let nav_dashboard = MenuItem::with_id(app, "nav_dashboard", "Dashboard", true, None::<&str>)?;
            let nav_sessions = MenuItem::with_id(app, "nav_sessions", "Sessions", true, None::<&str>)?;
            let nav_tasks = MenuItem::with_id(app, "nav_tasks", "Tasks", true, None::<&str>)?;
            let nav_teams = MenuItem::with_id(app, "nav_teams", "Teams", true, None::<&str>)?;
            let sep2 = PredefinedMenuItem::separator(app)?;
            let quit_item = MenuItem::with_id(app, "quit", "Quit", true, None::<&str>)?;
            let menu = Menu::with_items(app, &[
                &show_item,
                &sep1,
                &nav_dashboard,
                &nav_sessions,
                &nav_tasks,
                &nav_teams,
                &sep2,
                &quit_item,
            ])?;

            TrayIconBuilder::new()
                .icon(app.default_window_icon().cloned().unwrap())
                .tooltip("Eye in the Sky")
                .menu(&menu)
                .show_menu_on_left_click(false)
                .on_menu_event(|app, event| match event.id.as_ref() {
                    "show" => show_window(app),
                    "nav_dashboard" => navigate_to(app, "/"),
                    "nav_sessions" => navigate_to(app, "/sessions"),
                    "nav_tasks" => navigate_to(app, "/tasks"),
                    "nav_teams" => navigate_to(app, "/teams"),
                    "quit" => app.exit(0),
                    _ => {}
                })
                .on_tray_icon_event(|tray, event| {
                    if let TrayIconEvent::Click {
                        button: MouseButton::Left,
                        button_state: MouseButtonState::Up,
                        ..
                    } = event
                    {
                        show_window(tray.app_handle());
                    }
                })
                .build(app)?;

            // --- App menu bar (macOS) ---
            let app_menu = Submenu::with_items(app, "Eye in the Sky", true, &[
                &PredefinedMenuItem::about(app, Some("About Eye in the Sky"), None)?,
                &PredefinedMenuItem::separator(app)?,
                &MenuItem::with_id(app, "menu_settings", "Settings...", true, Some("CmdOrCtrl+,"))?,
                &PredefinedMenuItem::separator(app)?,
                &PredefinedMenuItem::hide(app, None)?,
                &PredefinedMenuItem::hide_others(app, None)?,
                &PredefinedMenuItem::show_all(app, None)?,
                &PredefinedMenuItem::separator(app)?,
                &PredefinedMenuItem::quit(app, None)?,
            ])?;
            let edit_menu = Submenu::with_items(app, "Edit", true, &[
                &PredefinedMenuItem::undo(app, None)?,
                &PredefinedMenuItem::redo(app, None)?,
                &PredefinedMenuItem::separator(app)?,
                &PredefinedMenuItem::cut(app, None)?,
                &PredefinedMenuItem::copy(app, None)?,
                &PredefinedMenuItem::paste(app, None)?,
                &PredefinedMenuItem::select_all(app, None)?,
            ])?;
            let view_menu = Submenu::with_items(app, "View", true, &[
                &MenuItem::with_id(app, "menu_dashboard", "Dashboard", true, Some("CmdOrCtrl+1"))?,
                &MenuItem::with_id(app, "menu_sessions", "Sessions", true, Some("CmdOrCtrl+2"))?,
                &MenuItem::with_id(app, "menu_tasks", "Tasks", true, Some("CmdOrCtrl+3"))?,
                &MenuItem::with_id(app, "menu_teams", "Teams", true, Some("CmdOrCtrl+4"))?,
                &PredefinedMenuItem::separator(app)?,
                &MenuItem::with_id(app, "menu_reload", "Reload", true, Some("CmdOrCtrl+R"))?,
            ])?;
            let window_menu = Submenu::with_items(app, "Window", true, &[
                &MenuItem::with_id(app, "menu_new_window", "New Window", true, Some("CmdOrCtrl+N"))?,
                &PredefinedMenuItem::separator(app)?,
                &PredefinedMenuItem::minimize(app, None)?,
                &PredefinedMenuItem::maximize(app, None)?,
                &PredefinedMenuItem::separator(app)?,
                &PredefinedMenuItem::close_window(app, None)?,
            ])?;
            let menubar = Menu::with_items(app, &[
                &app_menu, &edit_menu, &view_menu, &window_menu,
            ])?;
            app.set_menu(menubar)?;
            app.on_menu_event(|app, event| match event.id.as_ref() {
                "menu_new_window" => open_new_window(app, "/"),
                "menu_settings" => navigate_to(app, "/settings"),
                "menu_dashboard" => navigate_to(app, "/"),
                "menu_sessions" => navigate_to(app, "/sessions"),
                "menu_tasks" => navigate_to(app, "/tasks"),
                "menu_teams" => navigate_to(app, "/teams"),
                "menu_reload" => {
                    if let Some(window) = app.get_webview_window("main") {
                        let port = std::env::var("PORT").unwrap_or_else(|_| "5050".to_string());
                        let url = format!("http://127.0.0.1:{}", port);
                        if let Ok(parsed) = url.parse::<tauri::Url>() {
                            let _ = window.navigate(parsed);
                        }
                    }
                }
                _ => {}
            });

            // --- Global shortcut: Cmd+Shift+E to show/focus window ---
            let shortcut = "CmdOrCtrl+Shift+E".parse::<Shortcut>()?;
            let app_handle_shortcut = app.handle().clone();
            app.global_shortcut().on_shortcut(shortcut, move |_app, _shortcut, event| {
                if event.state == ShortcutState::Pressed {
                    show_window(&app_handle_shortcut);
                }
            })?;

            // --- Global shortcut: Cmd+Option+I to open Web Inspector ---
            let devtools_shortcut = "CmdOrCtrl+Alt+I".parse::<Shortcut>()?;
            let app_handle_devtools = app.handle().clone();
            app.global_shortcut().on_shortcut(devtools_shortcut, move |_app, _shortcut, event| {
                if event.state == ShortcutState::Pressed {
                    if let Some(window) = app_handle_devtools.get_webview_window("main") {
                        window.open_devtools();
                    }
                }
            })?;

            // --- Deep links: eits://... URLs routed into the main webview ---
            let app_handle_dl = app.handle().clone();
            app.deep_link().on_open_url(move |event| {
                for url in event.urls() {
                    route_deep_link(&app_handle_dl, url.as_str());
                }
            });
            if let Ok(Some(urls)) = app.deep_link().get_current() {
                for url in urls {
                    route_deep_link(app.handle(), url.as_str());
                }
            }

            // --- IAM hook installer ---
            // Write ~/.claude/settings.json hooks on every startup so agents
            // automatically POST tool events to the local IAM endpoint.
            // Idempotent: skips events that already have the hook present.
            let port = std::env::var("PORT").unwrap_or_else(|_| "5050".to_string());
            install_iam_hooks(&port);

            // --- ElixirKit PubSub: message dispatch ---
            let app_handle = app.handle().clone();

            // Wait for Phoenix to broadcast "ready" before opening the webview.
            // Avoids the WebView loading before the endpoint is accepting
            // connections, which would otherwise cause refresh/reconnect loops.
            pubsub.subscribe("messages", move |msg| {
                if msg == b"ready" {
                    create_window(&app_handle);
                } else if msg.starts_with(b"notify:") {
                    // Format: notify:<title>|<body>
                    let payload = String::from_utf8_lossy(&msg[7..]);
                    let parts: Vec<&str> = payload.splitn(2, '|').collect();
                    let title = parts.first().unwrap_or(&"EITS").to_string();
                    let body = parts.get(1).unwrap_or(&"").to_string();
                    send_notification(&title, &body);
                } else if msg.starts_with(b"badge:") {
                    // Format: badge:<count> (0 to clear)
                    let count_str = String::from_utf8_lossy(&msg[6..]);
                    if let Ok(count) = count_str.trim().parse::<i64>() {
                        if let Some(window) = app_handle.get_webview_window("main") {
                            let badge = if count == 0 { None } else { Some(count) };
                            let _ = window.set_badge_count(badge);
                        }
                    }
                } else if msg.starts_with(b"clipboard:") {
                    // Format: clipboard:<text>
                    let text = String::from_utf8_lossy(&msg[10..]).to_string();
                    let _ = app_handle.clipboard().write_text(text);
                } else if msg.starts_with(b"save-file:") {
                    // Format: save-file:<filename>|<content>
                    let payload = String::from_utf8_lossy(&msg[10..]).to_string();
                    let parts: Vec<&str> = payload.splitn(2, '|').collect();
                    let filename = parts.first().unwrap_or(&"export.txt").to_string();
                    let content = parts.get(1).unwrap_or(&"").to_string();
                    let app_clone = app_handle.clone();
                    tauri::async_runtime::spawn(async move {
                        save_file_dialog(&app_clone, &filename, &content).await;
                    });
                } else if msg.starts_with(b"navigate:") {
                    // Format: navigate:<path>
                    let path = String::from_utf8_lossy(&msg[9..]).to_string();
                    navigate_to(&app_handle, &path);
                } else {
                    println!("[eits-tauri] {}", String::from_utf8_lossy(msg));
                }
            });

            let app_handle = app.handle().clone();

            tauri::async_runtime::spawn_blocking(move || {
                let rel_dir = app_handle
                    .path()
                    .resource_dir()
                    .unwrap()
                    .join("rel");
                let mut command = elixir_command(&rel_dir);
                command.env("ELIXIRKIT_PUBSUB", pubsub.url());
                let status = command.status().expect("failed to start Elixir");
                app_handle.exit(status.code().unwrap_or(1));
            });

            Ok(())
        })
        .on_window_event(|window, event| {
            match event {
                tauri::WindowEvent::CloseRequested { api, .. } => {
                    if window.label() == "main" {
                        // Main window: hide instead of close so the app stays alive in the tray.
                        let _ = window.hide();
                        api.prevent_close();
                    }
                    // Secondary windows: allow normal close (do nothing, default behaviour).
                }
                tauri::WindowEvent::DragDrop(tauri::DragDropEvent::Drop { paths, .. }) => {
                    let paths_json: Vec<String> = paths.iter()
                        .filter_map(|p| p.to_str().map(|s| format!("\"{}\"", s.replace('\\', "\\\\").replace('"', "\\\""))))
                        .collect();
                    let js = format!(
                        "window.dispatchEvent(new CustomEvent('tauri:file-drop', {{ detail: {{ paths: [{}] }} }}))",
                        paths_json.join(",")
                    );
                    if let Some(wv) = window.app_handle().get_webview_window("main") {
                        let _ = wv.eval(&js);
                    }
                }
                _ => {}
            }
        })
        .build(tauri::generate_context!())
        .expect("error building tauri application")
        .run(|app_handle, event| {
            // macOS: dock icon clicked with no visible windows → show the hidden window.
            if let tauri::RunEvent::Reopen { has_visible_windows, .. } = event {
                if !has_visible_windows {
                    show_window(app_handle);
                }
            }
        });
}

fn show_window(app_handle: &tauri::AppHandle) {
    if let Some(window) = app_handle.get_webview_window("main") {
        let _ = window.show();
        let _ = window.set_focus();
    }
}

fn create_window(app_handle: &tauri::AppHandle) {
    let port = std::env::var("PORT").unwrap_or_else(|_| "5050".to_string());
    let url = format!("http://127.0.0.1:{}", port);
    let parsed_url: tauri::Url = url.parse().unwrap();

    // Start hidden, let window-state plugin restore position before showing
    let window = tauri::WebviewWindowBuilder::new(
        app_handle,
        "main",
        tauri::WebviewUrl::External(parsed_url),
    )
    .title("Eye in the Sky")
    .inner_size(1280.0, 800.0)
    .visible(false)
    .devtools(true)
    .build()
    .unwrap();

    let _ = window.show();
}

/// Open a new secondary window at the given path.
/// Each call gets a unique label ("window-2", "window-3", …) so Tauri
/// treats them as independent windows. Secondary windows close normally
/// (unlike "main" which hides to keep the app alive in the tray).
fn open_new_window(app_handle: &tauri::AppHandle, path: &str) {
    let n = WINDOW_COUNTER.fetch_add(1, Ordering::Relaxed);
    let label = format!("window-{}", n);
    let port = std::env::var("PORT").unwrap_or_else(|_| "5050".to_string());
    let url = format!("http://127.0.0.1:{}{}", port, path);
    let parsed_url: tauri::Url = match url.parse() {
        Ok(u) => u,
        Err(e) => {
            eprintln!("[eits-tauri] open_new_window: bad url {url}: {e}");
            return;
        }
    };
    match tauri::WebviewWindowBuilder::new(
        app_handle,
        &label,
        tauri::WebviewUrl::External(parsed_url),
    )
    .title("Eye in the Sky")
    .inner_size(1280.0, 800.0)
    .devtools(true)
    .build()
    {
        Ok(_) => {}
        Err(e) => eprintln!("[eits-tauri] open_new_window: failed to create {label}: {e}"),
    }
}

/// Map an `eits://...` deep-link URL to a Phoenix route and navigate.
fn route_deep_link(app_handle: &tauri::AppHandle, url_str: &str) {
    let url = match url_str.parse::<tauri::Url>() {
        Ok(u) => u,
        Err(_) => return,
    };
    if url.scheme() != "eits" {
        return;
    }
    let host = url.host_str().unwrap_or("");
    let tail = url.path().trim_start_matches('/');
    let path = match (host, tail.is_empty()) {
        ("sessions", false) => format!("/dm/{}", tail),
        ("dm", false) => format!("/dm/{}", tail),
        ("sessions", true) => "/sessions".to_string(),
        ("tasks", _) => "/tasks".to_string(),
        ("projects", false) => format!("/projects/{}", tail),
        ("", false) => format!("/{}", tail),
        _ => "/".to_string(),
    };
    navigate_to(app_handle, &path);
}

/// Navigate the main webview to a path (e.g., "/sessions", "/tasks")
fn navigate_to(app_handle: &tauri::AppHandle, path: &str) {
    if let Some(window) = app_handle.get_webview_window("main") {
        let _ = window.show();
        let _ = window.set_focus();
        let port = std::env::var("PORT").unwrap_or_else(|_| "5050".to_string());
        let url = format!("http://127.0.0.1:{}{}", port, path);
        if let Ok(parsed) = url.parse::<tauri::Url>() {
            let _ = window.navigate(parsed);
        }
    }
}

/// Show a native save file dialog and write content to the chosen path
async fn save_file_dialog(app_handle: &tauri::AppHandle, filename: &str, content: &str) {
    use tauri_plugin_dialog::DialogExt;
    let file_path = app_handle.dialog()
        .file()
        .set_file_name(filename)
        .blocking_save_file();

    if let Some(path) = file_path {
        let _ = std::fs::write(path.as_path().unwrap(), content);
    }
}

/// Send a native macOS notification. In dev mode the app binary lacks a proper
/// .app bundle so macOS Notification Center silently drops Tauri plugin
/// notifications. Fall back to osascript which always works.
fn send_notification(title: &str, body: &str) {
    if cfg!(debug_assertions) {
        let script = format!(
            "display notification \"{}\" with title \"{}\"",
            body.replace('\\', "\\\\").replace('"', "\\\""),
            title.replace('\\', "\\\\").replace('"', "\\\""),
        );
        match std::process::Command::new("osascript")
            .arg("-e")
            .arg(&script)
            .output()
        {
            Ok(out) if out.status.success() => {}
            Ok(out) => eprintln!("[eits-tauri] osascript failed: {}", String::from_utf8_lossy(&out.stderr)),
            Err(e) => eprintln!("[eits-tauri] osascript spawn failed: {}", e),
        }
    } else {
        // Prod builds have a proper .app bundle; Tauri plugin works.
        // This branch can't use app_handle — notifications go through osascript too for simplicity.
        let script = format!(
            "display notification \"{}\" with title \"{}\"",
            body.replace('\\', "\\\\").replace('"', "\\\""),
            title.replace('\\', "\\\\").replace('"', "\\\""),
        );
        let _ = std::process::Command::new("osascript")
            .arg("-e")
            .arg(&script)
            .output();
    }
}

fn elixir_command(rel_dir: &std::path::Path) -> std::process::Command {
    if cfg!(debug_assertions) {
        // Dev mode: run mix phx.server from the project root (one dir up from src-tauri)
        let mut command = elixirkit::mix("phx.server", &[]);
        command.current_dir("..");
        command.env("PORT", "5050");
        command.env("DISABLE_AUTH", "true");
        // Skip Vite/Tailwind watchers — Vite's config loader picks up main's
        // node_modules across the worktree boundary and fails. Phoenix serves
        // pre-built assets from priv/static instead.
        command.env("SKIP_WATCHERS", "1");
        command
    } else {
        // Prod mode: run the bundled release
        let mut command = elixirkit::release(rel_dir, "eye_in_the_sky");
        command.env("PHX_SERVER", "true");
        command.env("PHX_HOST", "127.0.0.1");
        command.env("PORT", "5050");
        command.env("DISABLE_AUTH", "true");
        command.env("BYPASS_AUTH", "true");
        // Disable SSL for local Postgres — bundled ERTS has no OpenSSL.
        command.env("DATABASE_SSL_VERIFY", "false");
        // Prevent Phoenix from redirecting http://localhost:5050 → https://
        // WKWebView would get a redirect loop if force_ssl is active.
        command.env("PHX_DISABLE_FORCE_SSL", "1");

        // Required by runtime.exs in prod — raises if absent.
        // For the desktop app: DATABASE_URL points to local Postgres,
        // SECRET_KEY_BASE is a stable desktop-only secret (not web-facing).
        if std::env::var("DATABASE_URL").is_err() {
            command.env("DATABASE_URL", "postgres://postgres:postgres@localhost/eits_dev?sslmode=disable");
        }
        if std::env::var("SECRET_KEY_BASE").is_err() {
            command.env(
                "SECRET_KEY_BASE",
                "bnsVqob9r8+zpVEcTxUEWHIamQVlRwx2xBgVP56XZAWIUJDTGAiG/WxzD7twxmPN7c2aaaaf50e1f72b3653c8f33bc1b3239e318214ceed08588536f5e62526b9dc405154507082f8caa48786531104ba0a8b66a9ffd7b3148e36649db0c28a1e3e",
            );
        }

        command
    }
}

/// Install EITS IAM hooks into ~/.claude/settings.json.
///
/// Idempotent — checks each event type independently and only adds a hook
/// group when none of the existing entries reference "iam/hook". Safe to
/// call on every startup.
///
/// Fail-open design: any I/O or parse error is logged and silently skipped.
/// The generated hook command uses `|| true` so Claude Code always sees
/// exit 0 even when Phoenix is not yet reachable (connection refused / timeout).
fn install_iam_hooks(port: &str) {
    let home = match std::env::var("HOME") {
        Ok(h) => std::path::PathBuf::from(h),
        Err(_) => {
            eprintln!("[eits-tauri] HOME not set; IAM hooks not installed");
            return;
        }
    };

    let claude_dir = home.join(".claude");
    let settings_path = claude_dir.join("settings.json");

    // Read existing file or start with an empty object.
    let mut root: serde_json::Value = if settings_path.exists() {
        match std::fs::read_to_string(&settings_path) {
            Ok(raw) => match serde_json::from_str(&raw) {
                Ok(v) => v,
                Err(e) => {
                    eprintln!("[eits-tauri] settings.json parse error: {e}; IAM hooks not installed");
                    return;
                }
            },
            Err(e) => {
                eprintln!("[eits-tauri] Could not read settings.json: {e}; IAM hooks not installed");
                return;
            }
        }
    } else {
        serde_json::json!({})
    };

    // Ensure root is an object (guard against malformed files).
    if !root.is_object() {
        eprintln!("[eits-tauri] settings.json root is not an object; IAM hooks not installed");
        return;
    }

    // Build the hook group to inject.
    let cmd = format!(
        "curl -sf --max-time 5 -X POST http://127.0.0.1:{port}/api/v1/iam/hook \
         -H 'Content-Type: application/json' -d @- || true"
    );
    let group_entry = serde_json::json!({
        "matcher": "",
        "hooks": [{ "type": "command", "command": cmd }]
    });

    let hooks_obj = root
        .as_object_mut()
        .unwrap()
        .entry("hooks")
        .or_insert_with(|| serde_json::json!({}));

    // Guard: if "hooks" is somehow not an object, bail.
    if !hooks_obj.is_object() {
        eprintln!("[eits-tauri] settings.json hooks field is not an object; IAM hooks not installed");
        return;
    }

    let mut installed_any = false;

    for event in &["PreToolUse", "PostToolUse", "Stop"] {
        let event_hooks = hooks_obj
            .as_object_mut()
            .unwrap()
            .entry(*event)
            .or_insert_with(|| serde_json::json!([]));

        // Ensure the event value is an array.
        if !event_hooks.is_array() {
            eprintln!("[eits-tauri] hooks.{event} is not an array; skipping");
            continue;
        }

        // Check whether any existing entry already references our endpoint.
        let already = event_hooks
            .as_array()
            .map(|groups| {
                groups.iter().any(|g| {
                    g.get("hooks")
                        .and_then(|h| h.as_array())
                        .map(|entries| {
                            entries.iter().any(|e| {
                                e.get("command")
                                    .and_then(|c| c.as_str())
                                    .map(|s| s.contains("iam/hook"))
                                    .unwrap_or(false)
                            })
                        })
                        .unwrap_or(false)
                })
            })
            .unwrap_or(false);

        if !already {
            event_hooks.as_array_mut().unwrap().push(group_entry.clone());
            installed_any = true;
        }
    }

    if !installed_any {
        println!("[eits-tauri] IAM hooks already present in settings.json; nothing to do");
        return;
    }

    // Ensure ~/.claude/ directory exists before writing.
    if let Err(e) = std::fs::create_dir_all(&claude_dir) {
        eprintln!("[eits-tauri] Could not create ~/.claude/: {e}");
        return;
    }

    match serde_json::to_string_pretty(&root) {
        Ok(json_str) => match std::fs::write(&settings_path, json_str) {
            Ok(()) => println!(
                "[eits-tauri] IAM hooks written to {}",
                settings_path.display()
            ),
            Err(e) => eprintln!("[eits-tauri] Could not write settings.json: {e}"),
        },
        Err(e) => eprintln!("[eits-tauri] Could not serialize settings.json: {e}"),
    }
}
