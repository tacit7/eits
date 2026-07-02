# Desktop Build Setup (Tauri)

Eye in the Sky ships a macOS desktop app built with [Tauri v2](https://tauri.app). The desktop app embeds a full Phoenix/Elixir release inside the `.app` bundle and connects to a local PostgreSQL database — no external server required.

---

## Prerequisites

### Web stack (required by the Elixir release inside the bundle)

Everything in [docs/SETUP.md](SETUP.md) under "System Dependencies" applies here too:

| Dependency | Notes |
|-----------|-------|
| Elixir 1.15+ / OTP 26+ | `brew install elixir` |
| Node.js 22 LTS | Vite/Tailwind asset pipeline |
| PostgreSQL 17 | `brew install postgresql@17 && brew services start postgresql@17` |
| Mix deps | **`mix deps.get` must run before any `cargo build`** — `Cargo.toml` has a path dependency on `../deps/elixirkit/elixirkit_rs`, so the Hex package must be present on disk first |

### Rust / Tauri toolchain

```bash
# Install Rust via rustup (https://rustup.rs)
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh

# Tauri v2 CLI
cargo install tauri-cli --version "^2"

# macOS: Xcode Command Line Tools (provides clang, codesign, etc.)
xcode-select --install
```

Verify:

```bash
cargo tauri --version   # should print tauri-cli 2.x.x
rustc --version
```

---

## Building

### 1. Fetch dependencies first

```bash
# From the project root
mix deps.get
cd assets && npm install && cd ..
```

This step is mandatory before any Cargo build. `elixirkit_rs` lives at
`deps/elixirkit/elixirkit_rs` and Cargo resolves it as a path dependency.

### 2. Source environment variables

The `beforeBuildCommand` in `tauri.conf.json` runs `mix release` inside a
`MIX_ENV=prod` context. Phoenix production releases require several env vars
at build time (`SECRET_KEY_BASE`, `VAPID_PRIVATE_KEY`, etc.). Source the
project's `.env` and `.env.local` before invoking Cargo:

```bash
cd src-tauri    # or project root — wherever you run cargo tauri build from
set -a
. /path/to/eits/web/.env
. /path/to/eits/web/.env.local
set +a
```

### 3. Run the build

```bash
cargo tauri build
```

What happens under the hood (from `tauri.conf.json` `beforeBuildCommand`):

1. Fixes permissions on stale `target/release` artifacts (`chmod u+w`).
2. Touches `endpoint.ex` to force a recompile with `PHX_INSECURE_COOKIES=1`
   baked in (required so WebKit accepts the cookie over `http://`).
3. Runs `MIX_ENV=prod mix do compile + assets.deploy + release --overwrite
   --path src-tauri/target/rel` to build the Elixir release.
4. Cargo links the Rust layer against ElixirKit and bundles everything.

Build time: **~10–15 min cold** (full LLVM optimisation + Elixir release);
**~2 min warm** (incremental Rust + cached BEAM).

Output:

```
src-tauri/target/release/bundle/macos/Eye in the Sky.app
src-tauri/target/release/bundle/dmg/Eye in the Sky_0.2.0_aarch64.dmg
```

### macOS code-signing / entitlements

The release step calls `ElixirKit.Release.codesign/1` (wired in `mix.exs`).
Codesigning is required because BEAM uses JIT compilation — without the
entitlements in `src-tauri/Entitlements.plist`, macOS will kill the process
at startup:

| Entitlement | Why |
|-------------|-----|
| `cs.allow-jit` | BEAM JIT compiler |
| `cs.allow-unsigned-executable-memory` | BEAM runtime memory ops |
| `cs.disable-library-validation` | bundled `.so`/`.dylib` files |
| `cs.allow-dyld-environment-variables` | `DYLD_INSERT_LIBRARIES` (BEAM internals) |

If you lack a Developer ID certificate, the app will still build but macOS
Gatekeeper will block it. For local dev, right-click → Open → Open to bypass
once.

### Known build gotcha: EACCES on stale `target/release/rel/`

If a prior build completed successfully, `src-tauri/target/release/rel/`
contains mode-555 ERTS binaries. On the next build, `tauri-build` tries to
overwrite them with `O_TRUNC` and gets permission denied:

```
Permission denied (os error 13)
Error failed to build app: failed to build app
```

Fix — move the stale directory out of the way (`rm` is aliased to `rm-trash`
on this system; use `mv`):

```bash
mv src-tauri/target/release/rel /tmp/tauri-rel-stale-$(date +%s)
cargo tauri build
```

The two `rel` directories are distinct:
- `src-tauri/target/rel/` — produced by `mix release`, re-generated every build. Leave it alone.
- `src-tauri/target/release/rel/` — Cargo's copy inside the `.app`. This one goes stale.

---

## Runtime environment

The bundled `.app` does not read shell environment variables when launched via
Finder or the Dock. All runtime configuration is stored in
`~/.config/eits/.env` and loaded at startup by `config/runtime.exs` via Dotenvy.

### `setup.command` — first-run provisioner

Run once in Terminal after installing the DMG:

```bash
open "/Applications/Eye in the Sky.app/Contents/Resources/setup.command"
```

`setup.command` is idempotent — safe to re-run. It:

1. Installs Homebrew if missing.
2. Installs and starts PostgreSQL 17 via Homebrew.
3. Creates the `eits_dev` database (`createdb eits_dev`).
4. Writes `~/.config/eits/.env` with:
   - `DATABASE_URL=ecto://<OS-username>@localhost/eits_dev` — uses `$(whoami)` because Homebrew PostgreSQL creates a superuser named after the installing user, **not** `postgres`.
   - `SECRET_KEY_BASE` — generated fresh via `openssl rand -hex 64`. Never hardcoded; all installs get a unique key.
   - `PHX_SERVER=true`, `PHX_DISABLE_FORCE_SSL=1`, `DISABLE_AUTH=1`, `DATABASE_SSL_VERIFY=false`
5. Patches an existing `.env` if `DATABASE_URL` still references `postgres` (upgrade path from older installs).
6. Symlinks `~/.config/eits/.env` into the release directory so the release finds it at `rel/.env`.
7. Runs database migrations via `bin/eye_in_the_sky eval "EyeInTheSky.Release.migrate()"`.
8. Optionally installs Claude Code hooks (interactive prompt).

### Key runtime env vars

| Variable | Set by | Purpose |
|----------|--------|---------|
| `DATABASE_URL` | `setup.command` | PostgreSQL connection; must match OS username for Homebrew installs |
| `SECRET_KEY_BASE` | `setup.command` (generated) | Phoenix session signing; unique per install |
| `PHX_HOST` | `lib.rs` (`elixir_command`) | Set to `127.0.0.1`; controls the Phoenix URL config |
| `PORT` | `lib.rs` | `5050` — avoids port conflict with the dev server on 5001 |
| `DISABLE_AUTH` | `lib.rs` + `~/.config/eits/.env` | Bypasses passkey auth; WKWebView origin mismatch makes WebAuthn impractical locally |
| `PHX_DISABLE_FORCE_SSL` | `~/.config/eits/.env` | Disables HSTS + HTTPS redirect so WKWebView doesn't loop on `http://` |
| `DATABASE_SSL_VERIFY` | `lib.rs` | `false` — bundled ERTS has no OpenSSL; local Postgres has no SSL anyway |
| `RELEASE_DISTRIBUTION` | `lib.rs` | `none` — disables Erlang distribution to avoid EPMD conflicts with a running dev server |
| `WEBAUTHN_EXTRA_ORIGINS` | manual / Tailscale section | Additional allowed WebSocket origins |

### Why `PHX_INSECURE_COOKIES=1` is baked at compile time

WebKit drops cookies with `Secure` flag over `http://`. Without `PHX_INSECURE_COOKIES=1`, every LiveView mount gets a fresh empty session, causing ~30 reconnects per second. The `beforeBuildCommand` touches `endpoint.ex` before compiling so this flag is baked into the compiled release — not set at runtime.

---

## Launching the bundled app

After `setup.command` runs, click the app icon normally. The Rust layer starts
the Elixir release, waits for Phoenix to broadcast `"ready"` over ElixirKit
PubSub, then creates the WKWebView window pointing at `http://127.0.0.1:5050`.

**Do not use `open -n "Eye in the Sky.app"`** to launch programmatically.
Launch Services does not pass shell env vars, so any variables not in
`~/.config/eits/.env` will be missing. Always invoke the binary directly if
you need custom env:

```bash
# Direct binary launch (inherits shell env)
"/Applications/Eye in the Sky.app/Contents/MacOS/eye-in-the-sky"

# With overrides
PORT=5050 RELEASE_NODE=eits_tauri \
  "/Applications/Eye in the Sky.app/Contents/MacOS/eye-in-the-sky"
```

If you need to run the bundled app **alongside** the dev server (port 5001), add:

```bash
RELEASE_DISTRIBUTION=none PORT=5050 \
  "/Applications/Eye in the Sky.app/Contents/MacOS/eye-in-the-sky"
```

`RELEASE_DISTRIBUTION=none` prevents the EPMD node-name collision that occurs
when two BEAM nodes try to use the same `-sname eye_in_the_sky`.

---

## Remote access via Tailscale

The embedded Phoenix server currently binds all interfaces:

```elixir
# config/runtime.exs:231
ip: {0, 0, 0, 0, 0, 0, 0, 0},   # ::/0 — all interfaces
```

**Security implication:** The app spawns Claude CLI subprocesses on behalf of
agents. Any network-reachable unauthenticated endpoint is effectively an RCE
surface. **Never expose port 5050 to the public internet.** The desktop app
sets `DISABLE_AUTH=true`, which removes the passkey gate entirely.

> **Known issue:** The server should bind loopback (`127.0.0.1`) by default.
> A follow-up code change to `config/runtime.exs` is needed to set
> `ip: {127, 0, 0, 1}` when running as the Tauri bundle. Do not change
> `runtime.exs` in this branch — the binding change requires careful testing
> against the dev-server path.

### Tailscale recipe

Tailscale tunnels only to machines in your tailnet, so it's safe to expose
the app on your local network for accessing it from another one of your
devices (e.g., iPhone, iPad, secondary Mac).

**1. Install Tailscale:**

```bash
brew install tailscale
# Or download from https://tailscale.com/download
```

**2. Start Tailscale and log in:**

```bash
sudo tailscale up
```

**3. Set up a Tailscale HTTPS reverse proxy:**

```bash
tailscale serve --https=443 localhost:5050
```

This creates `https://<machine>.<tailnet>.ts.net` with a valid TLS certificate
issued by Tailscale's CA (trusted automatically on all your Tailscale devices).
No certificate management required.

**4. Allow the Tailscale origin for LiveView WebSockets and passkeys:**

Add your Tailscale hostname to `WEBAUTHN_EXTRA_ORIGINS` in
`~/.config/eits/.env`, then restart the app:

```
WEBAUTHN_EXTRA_ORIGINS=https://<machine>.<tailnet>.ts.net
```

This is read at startup by `config/runtime.exs` and added to Phoenix's
`check_origin` list, so LiveView WebSocket upgrades are accepted from the
Tailscale URL.

> **Note:** When `DISABLE_AUTH=true` is set (the default for the bundled app),
> `check_origin` is set to `false` and origin checking is disabled entirely.
> You only need `WEBAUTHN_EXTRA_ORIGINS` if you re-enable authentication.

**5. Access the app:**

Open `https://<machine>.<tailnet>.ts.net` on any of your Tailscale devices.

---

## Deep-link routing (`eits://`)

The bundle registers the `eits://` URL scheme with macOS on first launch.
Use it to navigate directly to pages from scripts or other apps:

```bash
open "eits://sessions"           # → /sessions
open "eits://tasks"              # → /tasks
open "eits://dm/2768"            # → /dm/2768
open "eits:///projects/1/sessions"  # → /projects/1/sessions
```

Deep links only work with the bundled `.app`, not `cargo tauri dev` (which
runs a bare binary with no Info.plist to register the scheme).

---

## IAM hook auto-install

Every time the bundled app starts, `lib.rs` calls `install_iam_hooks()`. This
writes Claude Code hooks into `~/.claude/settings.json` that POST tool events
to `http://127.0.0.1:5050/api/v1/iam/hook`. The installation is idempotent —
it skips hook groups that already reference `iam/hook`.

If you do not want IAM hooks installed automatically, remove the existing
entries from `~/.claude/settings.json` after quitting the app (the installer
runs on every startup).

---

## Diagnostic tips

| Symptom | Likely cause | Check |
|---------|--------------|-------|
| App launches but clicks do nothing | WebSocket origin rejected | `WEBAUTHN_EXTRA_ORIGINS` missing or `check_origin` blocking the socket. Check `/tmp/tauri-*.log` for `Could not check origin`. |
| `VAPID_PRIVATE_KEY is required in production` crash | `DISABLE_AUTH` not set | Ensure `~/.config/eits/.env` contains `DISABLE_AUTH=1` |
| `role "postgres" does not exist` | `DATABASE_URL` still uses wrong user | Re-run `setup.command`; it patches the URL to use `$(whoami)` |
| Port 5050 already in use | Dev server or stale process | `lsof -i :5050`; kill the conflicting process |
| `EACCES` during build | Stale `target/release/rel/` | `mv src-tauri/target/release/rel /tmp/rel-stale && cargo tauri build` |
| `name eye_in_the_sky seems to be in use` | EPMD node collision | Bundled release is using `-sname`; set `RELEASE_DISTRIBUTION=none` or use a unique `RELEASE_NODE` |
