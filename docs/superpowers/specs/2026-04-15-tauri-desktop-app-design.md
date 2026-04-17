# EITS Tauri Desktop App — Design Spec

**Date:** 2026-04-15
**Status:** Draft
**Approach:** Tauri v2 + ElixirKit (livebook-dev/elixirkit)

## Goal

Package EITS as a native macOS desktop application using Tauri for the window shell and ElixirKit for Rust-to-Elixir communication. This is a minimal proof-of-concept; the full EITS web app runs unchanged inside a native window.

## Scope

### In scope (POC)
- Tauri v2 project (`src-tauri/`) in the EITS web repo
- ElixirKit PubSub bridge (Rust↔Elixir TCP socket)
- Tauri spawns Phoenix server, waits for "ready" signal, opens webview
- Dev workflow: `cargo tauri dev` launches everything
- macOS only (for now)

### Out of scope (future tasks)
- System tray icon
- Native OS notifications
- Global hotkey
- Auto-launch on login
- Deep links (`eits://`)
- Window state persistence
- Embedded PostgreSQL
- Distributable installer / code signing / notarization
- Linux and Windows builds

## Architecture

### Process flow

1. User launches the Tauri app (or `cargo tauri dev`)
2. Rust starts ElixirKit PubSub listener on a random local TCP port
3. Rust subscribes to the `"messages"` topic
4. Rust spawns the Elixir process with `ELIXIRKIT_PUBSUB` env var
   - Dev: `mix phx.server`
   - Prod (future): release binary from `src-tauri/target/rel/`
5. Elixir boots, Phoenix starts, supervision tree comes up
6. Elixir broadcasts `"ready"` via ElixirKit PubSub
7. Rust receives `"ready"`, creates a webview window at `http://127.0.0.1:{PORT}`
8. On app close: child Elixir process is terminated automatically

### Prerequisites

- PostgreSQL running externally (no embedded DB)
- Elixir/Erlang installed (dev only; release bundles the BEAM)
- Rust toolchain (rustup) for Tauri compilation
- Node.js for Vite asset pipeline

### Directory structure

```
web/
├── src-tauri/                  # NEW — Tauri project
│   ├── Cargo.toml              # tauri v2, elixirkit_rs path dep
│   ├── tauri.conf.json         # bundle ID, no default windows
│   ├── src/
│   │   └── lib.rs              # PubSub listener, process spawner, window creator
│   └── App.entitlements        # macOS code signing (future)
├── mix.exs                     # MODIFIED — add elixirkit dep
├── lib/
│   └── eye_in_the_sky/
│       └── application.ex      # MODIFIED — conditional ElixirKit PubSub child
└── ...                         # everything else unchanged
```

## Elixir Changes

### mix.exs

Add dependency:

```elixir
{:elixirkit, github: "livebook-dev/elixirkit"}
```

### application.ex

Conditionally start ElixirKit PubSub when `ELIXIRKIT_PUBSUB` is set (meaning we were launched by Tauri). When the env var is absent, the app behaves exactly as it does today.

```elixir
# At the top of the children list
children =
  if pubsub_url = System.get_env("ELIXIRKIT_PUBSUB") do
    [{ElixirKit.PubSub, pubsub_url}]
  else
    []
  end

children = children ++ [
  # ... existing supervision tree (unchanged)
]
```

After `Supervisor.start_link/2` succeeds, broadcast readiness:

```elixir
{:ok, pid} = Supervisor.start_link(children, opts)

if System.get_env("ELIXIRKIT_PUBSUB") do
  ElixirKit.PubSub.broadcast("messages", "ready")
end

{:ok, pid}
```

### Zero impact on existing behavior

- No env var = no ElixirKit = app works exactly as before
- `mix phx.server` still works standalone
- All tests pass unchanged
- No route, LiveView, or database changes

## Rust/Tauri Side

### Cargo.toml

```toml
[dependencies]
tauri = { version = "2", features = [] }
elixirkit = { path = "../deps/elixirkit/elixirkit_rs" }
```

Note: `elixirkit_rs` is vendored via the Mix dependency into `deps/elixirkit/elixirkit_rs/`.

### tauri.conf.json

```json
{
  "productName": "Eye in the Sky",
  "identifier": "dev.eits.app",
  "build": {},
  "app": {
    "windows": []
  }
}
```

No default windows — Rust creates the window programmatically after receiving the "ready" broadcast.

### lib.rs

Core logic:

1. Create PubSub listener on `127.0.0.1:0` (OS-assigned port)
2. Subscribe to `"messages"` topic
3. Determine dev vs prod mode
4. Spawn Elixir process:
   - Dev: `mix phx.server` with `ELIXIRKIT_PUBSUB` and `PORT` env vars
   - Prod: release binary with same env vars
5. Block on subscription until `"ready"` message arrives
6. Create webview window: `http://127.0.0.1:{PORT}`, 1280x800, titled "Eye in the Sky"

### Port handling

Reads `PORT` from environment (default: 5001). Passes it to the Elixir process and uses the same value for the webview URL. No automatic port conflict resolution in the POC.

### Window configuration

- Title: "Eye in the Sky"
- Default size: 1280x800
- Resizable: yes
- macOS native titlebar
- No frameless/custom chrome

## Dev Workflow

```bash
# Option 1: standalone Phoenix (no Tauri, works as always)
mix phx.server

# Option 2: Tauri dev (spawns Phoenix, opens native window)
cd src-tauri && cargo tauri dev
```

Hot reload works in Tauri dev mode because the webview points at the live Phoenix server with Vite watchers running.

## Future Features

Each is a discrete task layered on top of the POC:

| Feature | Mechanism | Notes |
|---------|-----------|-------|
| System tray | tauri-plugin-tray | Agent status indicators, quick actions |
| Notifications | tauri-plugin-notification | Agent done, DM received, task complete |
| Global hotkey | tauri-plugin-global-shortcut | Summon EITS from anywhere |
| Auto-launch | tauri-plugin-autostart | Start with macOS login |
| Deep links | tauri-plugin-deep-link | `eits://session/123` |
| Window state | tauri-plugin-window-state | Remember position/size |
| Embedded Postgres | Custom Rust process mgmt | Self-contained DB for distribution |
| Installer | Tauri bundler + code signing | DMG/pkg for macOS distribution |
| Linux/Windows | Cross-compilation | Extend CI matrix |

## Risks

- **ElixirKit stability**: It's Livebook's internal library, not a general-purpose crate. API may change without notice.
- **Rust toolchain requirement**: Developers need `rustup` installed, adding to the dev setup.
- **Port conflicts**: If port 5001 is already in use (e.g., standalone Phoenix running), Tauri dev will fail. Manual PORT override required.
- **First compile time**: Initial `cargo build` for Tauri is slow (minutes). Subsequent builds are incremental.
