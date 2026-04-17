use tauri::Manager;
use tauri::menu::{Menu, MenuItem, PredefinedMenuItem};
use tauri::tray::{MouseButton, MouseButtonState, TrayIconBuilder, TrayIconEvent};
use tauri_plugin_clipboard_manager::ClipboardExt;
use tauri_plugin_global_shortcut::{GlobalShortcutExt, Shortcut, ShortcutState};
use tauri_plugin_notification::NotificationExt;

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    let pubsub = elixirkit::PubSub::listen("tcp://127.0.0.1:0").expect("failed to listen");

    tauri::Builder::default()
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

            // --- Global shortcut: Cmd+Shift+E to show/focus window ---
            let shortcut = "CmdOrCtrl+Shift+E".parse::<Shortcut>()?;
            let app_handle_shortcut = app.handle().clone();
            app.global_shortcut().on_shortcut(shortcut, move |_app, _shortcut, event| {
                if event.state == ShortcutState::Pressed {
                    show_window(&app_handle_shortcut);
                }
            })?;

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
                    let _ = app_handle.notification()
                        .builder()
                        .title(title)
                        .body(body)
                        .show();
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
            if let tauri::WindowEvent::CloseRequested { api, .. } = event {
                let _ = window.hide();
                api.prevent_close();
            }
        })
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
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
    .build()
    .unwrap();

    let _ = window.show();
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
        command
    }
}
