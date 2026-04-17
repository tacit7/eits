# EITS Tauri Desktop App — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Package EITS as a native macOS desktop app using Tauri v2 + ElixirKit, with the full Phoenix web app running unchanged inside a native window.

**Architecture:** Tauri provides the native window shell. ElixirKit bridges Rust and Elixir via TCP PubSub. On launch, Rust spawns `mix phx.server` (dev) or a release binary (prod), waits for a "ready" broadcast, then opens a webview pointing at the Phoenix server. The entire EITS web app is unchanged; ElixirKit is conditionally started only when launched via Tauri.

**Tech Stack:** Tauri v2, Rust, ElixirKit (livebook-dev/elixirkit), Phoenix 1.8, Elixir

**Spec:** `docs/superpowers/specs/2026-04-15-tauri-desktop-app-design.md`

---

## File Map

| Action | Path | Purpose |
|--------|------|---------|
| Create | `src-tauri/Cargo.toml` | Rust project config with tauri + elixirkit deps |
| Create | `src-tauri/build.rs` | Tauri build script |
| Create | `src-tauri/tauri.conf.json` | Tauri app config (no default windows, bundle settings) |
| Create | `src-tauri/src/main.rs` | Rust entry point, delegates to lib |
| Create | `src-tauri/src/lib.rs` | PubSub listener, Phoenix spawner, window creator |
| Modify | `mix.exs` | Add `{:elixirkit, github: "livebook-dev/elixirkit"}` dep |
| Modify | `lib/eye_in_the_sky/application.ex` | Conditional ElixirKit.PubSub child + ready broadcast |
| Modify | `.gitignore` | Ignore `src-tauri/target/` |

---

### Task 1: Add ElixirKit Dependency

**Files:**
- Modify: `mix.exs` (deps list)

- [ ] **Step 1: Add elixirkit to mix.exs deps**

In `mix.exs`, add to the `deps/0` function, after the `{:credo, ...}` line:

```elixir
{:elixirkit, github: "livebook-dev/elixirkit"}
```

- [ ] **Step 2: Fetch the dependency**

Run: `mix deps.get`

Expected: ElixirKit and its transitive deps are fetched. Output includes `* Getting elixirkit`.

- [ ] **Step 3: Verify it compiles**

Run: `mix compile`

Expected: Clean compilation, no errors. ElixirKit modules available.

- [ ] **Step 4: Verify the Rust crate is vendored**

Run: `ls deps/elixirkit/elixirkit_rs/Cargo.toml`

Expected: File exists. This is the path the Tauri `Cargo.toml` will reference.

- [ ] **Step 5: Commit**

```bash
git add mix.exs mix.lock
git commit -m "deps: add elixirkit for Tauri desktop integration"
```

---

### Task 2: Integrate ElixirKit PubSub into Application Supervision Tree

**Files:**
- Modify: `lib/eye_in_the_sky/application.ex`

- [ ] **Step 1: Read current application.ex**

Read `lib/eye_in_the_sky/application.ex` to confirm the current supervision tree structure. The existing code builds `children` in two steps: first a conditional LiveSvelte SSR list, then appends the main children list.

- [ ] **Step 2: Add conditional ElixirKit PubSub child**

At the top of `start/2`, after the `Oban.Telemetry.attach_default_logger(:info)` line and before the LiveSvelte SSR conditional, add:

```elixir
# ElixirKit PubSub — only started when launched via Tauri (ELIXIRKIT_PUBSUB env var set)
elixirkit_children =
  if pubsub = System.get_env("ELIXIRKIT_PUBSUB") do
    [{ElixirKit.PubSub, connect: pubsub, on_exit: fn -> System.stop() end}]
  else
    []
  end
```

Then prepend `elixirkit_children` to the final children list. Find the line:

```elixir
children =
  children ++
    [
```

And change it to:

```elixir
children =
  elixirkit_children ++
    children ++
    [
```

This ensures ElixirKit.PubSub starts first in the supervision tree (before Repo, Endpoint, etc.) and `on_exit` cleanly shuts down the app if the Tauri side terminates the PubSub connection.

- [ ] **Step 3: Add ready broadcast after supervisor starts**

Replace the current return at the bottom of `start/2`:

```elixir
opts = [strategy: :rest_for_one, name: EyeInTheSky.Supervisor]
Supervisor.start_link(children, opts)
```

With:

```elixir
opts = [strategy: :rest_for_one, name: EyeInTheSky.Supervisor]
result = Supervisor.start_link(children, opts)

# Signal Tauri that Phoenix is ready and accepting connections
if System.get_env("ELIXIRKIT_PUBSUB") do
  ElixirKit.PubSub.broadcast("messages", "ready")
end

result
```

- [ ] **Step 4: Verify standalone Phoenix still works**

Run: `mix phx.server`

Expected: Server starts normally on port 5001. No ElixirKit-related output (env var not set, so it's skipped).

Stop the server with Ctrl+C.

- [ ] **Step 5: Verify compilation is clean**

Run: `mix compile --warnings-as-errors`

Expected: No errors, no warnings.

- [ ] **Step 6: Commit**

```bash
git add lib/eye_in_the_sky/application.ex
git commit -m "feat: conditional ElixirKit PubSub integration for Tauri"
```

---

### Task 3: Create Tauri Project — Cargo Configuration

**Files:**
- Create: `src-tauri/Cargo.toml`
- Create: `src-tauri/build.rs`

- [ ] **Step 1: Create the src-tauri directory**

```bash
mkdir -p src-tauri/src
```

- [ ] **Step 2: Create Cargo.toml**

Write `src-tauri/Cargo.toml`:

```toml
[package]
name = "eye-in-the-sky"
version = "0.1.0"
edition = "2021"

[lib]
name = "eye_in_the_sky_lib"
crate-type = ["lib", "cdylib", "staticlib"]

[build-dependencies]
tauri-build = { version = "2", features = [] }

[dependencies]
tauri = { version = "2", features = [] }
tauri-plugin-opener = "2"
serde = { version = "1", features = ["derive"] }
serde_json = "1"
elixirkit = { path = "../deps/elixirkit/elixirkit_rs" }
```

Note: `elixirkit` points to the Mix-vendored crate at `../deps/elixirkit/elixirkit_rs` (one level up from `src-tauri/` to the project root, then into `deps/`).

- [ ] **Step 3: Create build.rs**

Write `src-tauri/build.rs`:

```rust
fn main() {
    tauri_build::build()
}
```

- [ ] **Step 4: Verify Cargo can resolve dependencies**

```bash
cd src-tauri && cargo check 2>&1 | head -20
```

Expected: Dependencies download and resolve. May fail on missing `src/lib.rs` — that's fine, we create it in the next task.

- [ ] **Step 5: Commit**

```bash
git add src-tauri/Cargo.toml src-tauri/build.rs
git commit -m "feat: add Tauri Cargo project with elixirkit dependency"
```

---

### Task 4: Create Tauri Project — Rust Source

**Files:**
- Create: `src-tauri/src/main.rs`
- Create: `src-tauri/src/lib.rs`

- [ ] **Step 1: Create main.rs**

Write `src-tauri/src/main.rs`:

```rust
// Prevents additional console window on Windows in release, DO NOT REMOVE!!
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

fn main() {
    eye_in_the_sky_lib::run()
}
```

- [ ] **Step 2: Create lib.rs**

Write `src-tauri/src/lib.rs`:

```rust
use tauri::Manager;

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    let pubsub = elixirkit::PubSub::listen("tcp://127.0.0.1:0").expect("failed to listen");

    tauri::Builder::default()
        .plugin(tauri_plugin_opener::init())
        .setup(move |app| {
            let app_handle = app.handle().clone();
            pubsub.subscribe("messages", move |msg| {
                if msg == b"ready" {
                    create_window(&app_handle);
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
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}

fn create_window(app_handle: &tauri::AppHandle) {
    let port = std::env::var("PORT").unwrap_or_else(|_| "5001".to_string());
    let url = format!("http://127.0.0.1:{}", port);
    let parsed_url: tauri::Url = url.parse().unwrap();

    tauri::WebviewWindowBuilder::new(app_handle, "main", tauri::WebviewUrl::External(parsed_url))
        .title("Eye in the Sky")
        .inner_size(1280.0, 800.0)
        .build()
        .unwrap();
}

fn elixir_command(rel_dir: &std::path::Path) -> std::process::Command {
    if cfg!(debug_assertions) {
        // Dev mode: run mix phx.server from the project root (one dir up from src-tauri)
        let mut command = elixirkit::mix("phx.server", &[]);
        command.current_dir("..");
        command
    } else {
        // Prod mode: run the bundled release
        let mut command = elixirkit::release(rel_dir, "eye_in_the_sky");
        command.env("PHX_SERVER", "true");
        command.env("PHX_HOST", "127.0.0.1");
        command.env(
            "PORT",
            std::env::var("PORT").unwrap_or_else(|_| "5001".to_string()),
        );
        command
    }
}
```

Key details:
- `create_window` reads `PORT` from env (default 5001) to match Phoenix config
- `elixir_command` uses `current_dir("..")` in dev to run from the project root
- In prod, it launches the release binary with required env vars
- Window ID is `"main"` (single window)

- [ ] **Step 3: Verify Rust compiles**

```bash
cd src-tauri && cargo check
```

Expected: Compilation succeeds. Warnings are OK for now.

- [ ] **Step 4: Commit**

```bash
git add src-tauri/src/main.rs src-tauri/src/lib.rs
git commit -m "feat: Tauri Rust source — PubSub, Phoenix spawner, window creator"
```

---

### Task 5: Create Tauri Configuration

**Files:**
- Create: `src-tauri/tauri.conf.json`

- [ ] **Step 1: Create tauri.conf.json**

Write `src-tauri/tauri.conf.json`:

```json
{
  "$schema": "https://schema.tauri.app/config/2",
  "productName": "Eye in the Sky",
  "version": "0.1.0",
  "identifier": "dev.eits.app",
  "build": {
    "beforeBuildCommand": "MIX_ENV=prod mix do compile + assets.deploy + release --overwrite --path src-tauri/target/rel",
    "beforeDevCommand": "mkdir -p src-tauri/target/rel"
  },
  "app": {
    "withGlobalTauri": false,
    "security": {
      "csp": null
    }
  },
  "bundle": {
    "active": true,
    "resources": {
      "target/rel": "rel"
    },
    "targets": "all",
    "icon": [
      "icons/32x32.png",
      "icons/128x128.png",
      "icons/128x128@2x.png",
      "icons/icon.icns",
      "icons/icon.ico"
    ]
  }
}
```

Notes:
- `beforeBuildCommand`: Compiles Elixir, deploys assets, creates a release into `src-tauri/target/rel` for bundling
- `beforeDevCommand`: Just creates the target dir so Tauri doesn't complain (dev doesn't need a release)
- `resources`: Bundles the release directory into the app bundle
- `withGlobalTauri: false`: We don't need JS Tauri APIs (Phoenix handles everything)
- No default windows (Rust creates the window after "ready")

- [ ] **Step 2: Create placeholder icons directory**

```bash
mkdir -p src-tauri/icons
```

Generate default Tauri icons (or use placeholders for now):

```bash
cd src-tauri && cargo tauri icon --help 2>/dev/null || echo "Install tauri-cli: cargo install tauri-cli"
```

For the POC, create minimal placeholder icons. If `cargo tauri icon` is available, use it with any PNG. Otherwise, this step can be deferred — Tauri will warn but still build without icons.

- [ ] **Step 3: Commit**

```bash
git add src-tauri/tauri.conf.json src-tauri/icons/
git commit -m "feat: Tauri configuration — bundle settings, build commands, app identity"
```

---

### Task 6: Update .gitignore

**Files:**
- Modify: `.gitignore`

- [ ] **Step 1: Add Tauri build artifacts to .gitignore**

Append to `.gitignore`:

```
# Tauri
/src-tauri/target/
```

- [ ] **Step 2: Commit**

```bash
git add .gitignore
git commit -m "chore: ignore Tauri build artifacts"
```

---

### Task 7: Install Tauri CLI and First Dev Build

**Files:** None (verification only)

- [ ] **Step 1: Verify Rust toolchain**

```bash
rustc --version && cargo --version
```

Expected: Rust 1.77+ and Cargo installed. If not:

```bash
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
```

- [ ] **Step 2: Install Tauri CLI**

```bash
cargo install tauri-cli
```

Expected: `cargo-tauri` binary installed. Verify:

```bash
cargo tauri --version
```

Expected: `tauri-cli 2.x.x`

- [ ] **Step 3: Ensure PostgreSQL is running**

```bash
pg_isready
```

Expected: `accepting connections`

- [ ] **Step 4: Run Tauri dev**

From the project root:

```bash
cd src-tauri && cargo tauri dev
```

Expected behavior:
1. Cargo compiles the Tauri app (first build takes several minutes)
2. Rust starts ElixirKit PubSub listener
3. Rust spawns `mix phx.server` from the project root
4. Phoenix boots, compiles assets, starts endpoint on port 5001
5. Elixir broadcasts "ready" via ElixirKit PubSub
6. A native macOS window opens showing the EITS web UI at `http://127.0.0.1:5001`
7. LiveView works, hot reload works, everything functions as in a browser

- [ ] **Step 5: Verify hot reload**

With Tauri dev running, edit any `.heex` template (e.g., add a comment). The webview should update via LiveView's live reload, same as in a browser.

- [ ] **Step 6: Verify clean shutdown**

Close the native window. Expected: Phoenix process terminates (ElixirKit `on_exit` calls `System.stop()`).

- [ ] **Step 7: Verify standalone Phoenix still works**

```bash
mix phx.server
```

Expected: Starts normally, no ElixirKit output, no regressions.

---

### Task 8: Verify and Document

**Files:**
- Modify: `docs/SETUP.md`

- [ ] **Step 1: Run mix compile --warnings-as-errors**

```bash
mix compile --warnings-as-errors
```

Expected: Clean compilation.

- [ ] **Step 2: Update SETUP.md with Tauri dev instructions**

Add a "Desktop App (Tauri)" section to `docs/SETUP.md` with:
- Prerequisites: Rust toolchain (`rustup`), `cargo install tauri-cli`
- Dev command: `cd src-tauri && cargo tauri dev`
- Note: First build is slow (compiling Rust deps), subsequent builds are fast
- Note: PostgreSQL must be running
- Note: `mix phx.server` still works independently

- [ ] **Step 3: Final commit**

```bash
git add docs/SETUP.md
git commit -m "docs: add Tauri desktop app dev setup instructions"
```
