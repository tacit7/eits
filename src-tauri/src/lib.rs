use tauri::Manager;
use tauri::menu::{Menu, MenuItem};
use tauri::tray::{MouseButton, MouseButtonState, TrayIconBuilder, TrayIconEvent};

const PORT: &str = "5050";

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    let pubsub = elixirkit::PubSub::listen("tcp://127.0.0.1:0").expect("failed to listen");

    tauri::Builder::default()
        .plugin(tauri_plugin_opener::init())
        .plugin(tauri_plugin_window_state::Builder::default().build())
        .setup(move |app| {
            let show_item = MenuItem::with_id(app, "show", "Show EITS", true, None::<&str>)?;
            let quit_item = MenuItem::with_id(app, "quit", "Quit", true, None::<&str>)?;
            let menu = Menu::with_items(app, &[&show_item, &quit_item])?;

            TrayIconBuilder::new()
                .icon(app.default_window_icon().cloned().unwrap())
                .tooltip("Eye in the Sky")
                .menu(&menu)
                .show_menu_on_left_click(false)
                .on_menu_event(|app, event| match event.id.as_ref() {
                    "show" => {
                        if let Some(window) = app.get_webview_window("main") {
                            let _ = window.show();
                            let _ = window.set_focus();
                        }
                    }
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
                        let app = tray.app_handle();
                        if let Some(window) = app.get_webview_window("main") {
                            let _ = window.show();
                            let _ = window.set_focus();
                        }
                    }
                })
                .build(app)?;

            let app_handle = app.handle().clone();

            // Wait for Phoenix to broadcast "ready" before opening the webview.
            // Avoids the WebView loading before the endpoint is accepting
            // connections, which would otherwise cause refresh/reconnect loops.
            pubsub.subscribe("messages", move |msg| {
                if msg == b"ready" {
                    create_window(&app_handle);
                } else {
                    println!("[rust] {}", String::from_utf8_lossy(msg));
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

fn create_window(app_handle: &tauri::AppHandle) {
    let url = format!("http://127.0.0.1:{}", PORT);
    let parsed_url: tauri::Url = url.parse().unwrap();

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

fn elixir_command(rel_dir: &std::path::Path) -> std::process::Command {
    if cfg!(debug_assertions) {
        let mut command = elixirkit::mix("phx.server", &[]);
        command.current_dir("..");
        command.env("PORT", PORT);
        // Bypass auth (HTTP + LiveView) for the POC. BYPASS_AUTH already
        // defaults to true in dev.exs; DISABLE_AUTH covers the LiveView hook.
        command.env("DISABLE_AUTH", "true");
        // Skip Vite/Tailwind watchers — Vite's config loader picks up main's
        // node_modules across the worktree boundary and fails. Phoenix serves
        // pre-built assets from priv/static instead.
        command.env("SKIP_WATCHERS", "1");
        command
    } else {
        let mut command = elixirkit::release(rel_dir, "eye_in_the_sky");
        command.env("PHX_SERVER", "true");
        command.env("PHX_HOST", "127.0.0.1");
        command.env("PORT", PORT);
        command.env("DISABLE_AUTH", "true");
        command.env("BYPASS_AUTH", "true");
        command
    }
}
