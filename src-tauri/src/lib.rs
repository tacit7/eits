use tauri::Manager;

const PORT: &str = "5050";

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    let pubsub = elixirkit::PubSub::listen("tcp://127.0.0.1:0").expect("failed to listen");

    tauri::Builder::default()
        .plugin(tauri_plugin_opener::init())
        .setup(move |app| {
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
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}

fn create_window(app_handle: &tauri::AppHandle) {
    let url = format!("http://127.0.0.1:{}", PORT);
    let url = tauri::WebviewUrl::External(url.parse().unwrap());
    tauri::WebviewWindowBuilder::new(app_handle, "main", url)
        .title("Eye in the Sky")
        .inner_size(1200.0, 800.0)
        .build()
        .unwrap();
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
