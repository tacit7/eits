use std::sync::atomic::{AtomicBool, AtomicU32, Ordering};
use tauri::Manager;
use tauri::menu::{AboutMetadata, CheckMenuItem, Menu, MenuItem, PredefinedMenuItem, Submenu};
use tauri::tray::{MouseButton, MouseButtonState, TrayIconBuilder, TrayIconEvent};
#[cfg(not(debug_assertions))]
use tauri_plugin_clipboard_manager::ClipboardExt;
use tauri_plugin_deep_link::DeepLinkExt;
use tauri_plugin_global_shortcut::{GlobalShortcutExt, Shortcut, ShortcutState};

/// Monotonic counter for generating unique secondary window labels.
static WINDOW_COUNTER: AtomicU32 = AtomicU32::new(2);

/// Always-on-top state — persisted in memory, toggled via menu/tray.
static ALWAYS_ON_TOP: AtomicBool = AtomicBool::new(false);

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
            // --- System tray ---
            let show_item = MenuItem::with_id(app, "show", "Show EITS", true, None::<&str>)?;
            let always_on_top_item = CheckMenuItem::with_id(app, "always_on_top", "Always on Top", true, false, None::<&str>)?;
            let sep1 = PredefinedMenuItem::separator(app)?;
            let nav_dashboard = MenuItem::with_id(app, "nav_dashboard", "Dashboard", true, None::<&str>)?;
            let nav_sessions = MenuItem::with_id(app, "nav_sessions", "Sessions", true, None::<&str>)?;
            let nav_tasks = MenuItem::with_id(app, "nav_tasks", "Tasks", true, None::<&str>)?;
            let nav_teams = MenuItem::with_id(app, "nav_teams", "Teams", true, None::<&str>)?;
            let sep2 = PredefinedMenuItem::separator(app)?;
            let quit_item = MenuItem::with_id(app, "quit", "Quit", true, None::<&str>)?;
            let tray_menu = Menu::with_items(app, &[
                &show_item,
                &always_on_top_item,
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
                .menu(&tray_menu)
                .show_menu_on_left_click(false)
                .on_menu_event(|app, event| match event.id.as_ref() {
                    "show" => show_window(app),
                    "always_on_top" => toggle_always_on_top(app),
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
                &PredefinedMenuItem::about(app, Some("About Eye in the Sky"), Some(AboutMetadata {
                    version: Some(env!("CARGO_PKG_VERSION").to_string()),
                    website: Some("https://eits.dev".to_string()),
                    website_label: Some("eits.dev".to_string()),
                    authors: Some(vec!["EITS Team".to_string()]),
                    license: Some("Proprietary".to_string()),
                    ..Default::default()
                }))?,
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
            let always_on_top_menu_item = CheckMenuItem::with_id(
                app, "menu_always_on_top", "Always on Top", true, false,
                Some("CmdOrCtrl+Shift+T"),
            )?;
            let view_menu = Submenu::with_items(app, "View", true, &[
                &MenuItem::with_id(app, "menu_dashboard", "Dashboard", true, Some("CmdOrCtrl+1"))?,
                &MenuItem::with_id(app, "menu_sessions", "Sessions", true, Some("CmdOrCtrl+2"))?,
                &MenuItem::with_id(app, "menu_tasks", "Tasks", true, Some("CmdOrCtrl+3"))?,
                &MenuItem::with_id(app, "menu_teams", "Teams", true, Some("CmdOrCtrl+4"))?,
                &PredefinedMenuItem::separator(app)?,
                &always_on_top_menu_item,
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
                "menu_always_on_top" => toggle_always_on_top(app),
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
            let port = std::env::var("PORT").unwrap_or_else(|_| "5050".to_string());
            install_iam_hooks(&port);

            // --- ElixirKit PubSub ---
            #[cfg(debug_assertions)]
            {
                println!("[eits-tauri] dev mode — skipping ElixirKit spawn, connecting to external Phoenix server");
                let app_handle_dev = app.handle().clone();
                drop(pubsub);
                create_window(&app_handle_dev);
            }

            #[cfg(not(debug_assertions))]
            {
                let app_handle = app.handle().clone();

                pubsub.subscribe("messages", move |msg| {
                    if msg == b"ready" {
                        create_window(&app_handle);
                    } else if msg.starts_with(b"notify:") {
                        // Format: notify:<title>|<body>  or  notify:<title>|<body>|<path>
                        let payload = String::from_utf8_lossy(&msg[7..]);
                        let parts: Vec<&str> = payload.splitn(3, '|').collect();
                        let title = parts.first().unwrap_or(&"EITS").to_string();
                        let body = parts.get(1).unwrap_or(&"").to_string();
                        let nav_path = parts.get(2).map(|s| s.to_string());

                        let app_clone = app_handle.clone();
                        send_notification(&title, &body, nav_path, &app_clone);

                        if let Some(w) = app_handle.get_webview_window("main") {
                            let _ = w.request_user_attention(Some(tauri::UserAttentionType::Informational));
                        }
                    } else if msg.starts_with(b"badge:") {
                        let count_str = String::from_utf8_lossy(&msg[6..]);
                        if let Ok(count) = count_str.trim().parse::<i64>() {
                            if let Some(window) = app_handle.get_webview_window("main") {
                                let badge = if count == 0 { None } else { Some(count) };
                                let _ = window.set_badge_count(badge);
                            }
                        }
                    } else if msg.starts_with(b"clipboard:") {
                        let text = String::from_utf8_lossy(&msg[10..]).to_string();
                        let _ = app_handle.clipboard().write_text(text);
                    } else if msg.starts_with(b"save-file:") {
                        let payload = String::from_utf8_lossy(&msg[10..]).to_string();
                        let parts: Vec<&str> = payload.splitn(2, '|').collect();
                        let filename = parts.first().unwrap_or(&"export.txt").to_string();
                        let content = parts.get(1).unwrap_or(&"").to_string();
                        let app_clone = app_handle.clone();
                        tauri::async_runtime::spawn(async move {
                            save_file_dialog(&app_clone, &filename, &content).await;
                        });
                    } else if msg.starts_with(b"navigate:") {
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
            }

            Ok(())
        })
        .on_window_event(|window, event| {
            match event {
                tauri::WindowEvent::CloseRequested { api, .. } => {
                    if window.label() == "main" {
                        let _ = window.hide();
                        api.prevent_close();
                    }
                }
                tauri::WindowEvent::ThemeChanged(theme) => {
                    let theme_name = match theme {
                        tauri::Theme::Dark => "dark",
                        _ => "light",
                    };
                    let js = format!(
                        "window.dispatchEvent(new CustomEvent('tauri:theme-changed', \
                         {{ detail: {{ theme: '{}' }} }}))",
                        theme_name
                    );
                    if let Some(wv) = window.app_handle().get_webview_window(window.label()) {
                        let _ = wv.eval(&js);
                    }
                }
                tauri::WindowEvent::DragDrop(tauri::DragDropEvent::Drop { paths, .. }) => {
                    // Forward dropped file paths into the webview as a CustomEvent.
                    // A JS listener in app.js picks this up and pushes the paths to
                    // the active LiveView session via pushEvent.
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

fn toggle_always_on_top(app_handle: &tauri::AppHandle) {
    let current = ALWAYS_ON_TOP.load(Ordering::Relaxed);
    let next = !current;
    ALWAYS_ON_TOP.store(next, Ordering::Relaxed);

    if let Some(window) = app_handle.get_webview_window("main") {
        let _ = window.set_always_on_top(next);
    }

    // Sync checkmark on the menu-bar item.
    if let Some(menu) = app_handle.menu() {
        if let Some(tauri::menu::MenuItemKind::Check(item)) = menu.get("menu_always_on_top") {
            let _ = item.set_checked(next);
        }
    }
}

fn create_window(app_handle: &tauri::AppHandle) {
    let port = std::env::var("PORT").unwrap_or_else(|_| "5050".to_string());
    let url = format!("http://127.0.0.1:{}", port);
    let parsed_url: tauri::Url = url.parse().unwrap();

    let window = tauri::WebviewWindowBuilder::new(
        app_handle,
        "main",
        tauri::WebviewUrl::External(parsed_url),
    )
    .title("Eye in the Sky")
    .title_bar_style(tauri::TitleBarStyle::Overlay)
    .hidden_title(true)
    .inner_size(1280.0, 800.0)
    .visible(false)
    .devtools(true)
    .build()
    .unwrap();

    // Sidebar vibrancy — frosted-glass effect over the entire window.
    #[cfg(target_os = "macos")]
    {
        use window_vibrancy::{apply_vibrancy, NSVisualEffectMaterial};
        apply_vibrancy(&window, NSVisualEffectMaterial::Sidebar, None, None).ok();
    }

    let _ = window.eval("document.documentElement.setAttribute('data-tauri-overlay', '1')");
    let _ = window.show();
}

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

/// Send a native notification. If `nav_path` is provided, clicking the
/// notification navigates the main window to that path.
#[cfg(not(debug_assertions))]
fn send_notification(title: &str, body: &str, nav_path: Option<String>, app_handle: &tauri::AppHandle) {
    use tauri_plugin_notification::NotificationExt;

    let mut builder = app_handle
        .notification()
        .builder()
        .title(title)
        .body(body);

    // Embed the path in the notification identifier so we can retrieve it
    // in the action callback. Format: "eits-nav:<path>" or "eits-default".
    let id = match &nav_path {
        Some(path) => format!("eits-nav:{}", path),
        None => "eits-default".to_string(),
    };
    builder = builder.identifier(&id);

    if let Err(e) = builder.show() {
        eprintln!("[eits-tauri] notification error: {e}");
    }

    // If the window is already visible, also navigate immediately on receipt.
    // This handles the case where the user has the app focused.
    if let Some(path) = nav_path {
        if let Some(window) = app_handle.get_webview_window("main") {
            if window.is_visible().unwrap_or(false) {
                navigate_to(app_handle, &path);
            }
        }
    }
}

#[cfg(not(debug_assertions))]
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

#[cfg(not(debug_assertions))]
fn elixir_command(rel_dir: &std::path::Path) -> std::process::Command {
    if cfg!(debug_assertions) {
        let mut command = elixirkit::mix("phx.server", &[]);
        command.current_dir("..");
        command.env("PORT", "5050");
        command.env("DISABLE_AUTH", "true");
        command.env("SKIP_WATCHERS", "1");
        command
    } else {
        let mut command = elixirkit::release(rel_dir, "eye_in_the_sky");
        command.env("PHX_SERVER", "true");
        command.env("PHX_HOST", "127.0.0.1");
        command.env("PORT", "5050");
        command.env("DISABLE_AUTH", "true");
        command.env("BYPASS_AUTH", "true");
        command.env("DATABASE_SSL_VERIFY", "false");
        command.env("PHX_DISABLE_FORCE_SSL", "1");

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

    if !root.is_object() {
        eprintln!("[eits-tauri] settings.json root is not an object; IAM hooks not installed");
        return;
    }

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

        if !event_hooks.is_array() {
            eprintln!("[eits-tauri] hooks.{event} is not an array; skipping");
            continue;
        }

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
