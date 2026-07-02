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
Finder or the Dock. The Rust layer in `src-tauri/src/lib.rs` (`elixir_command`)
injects a fixed set of env vars before spawning the Elixir release. In addition,
`config/runtime.exs` reads `.env` and `.env.local` from the release working
directory via Dotenvy — if those files exist they override the values injected
by Rust.

### How env provisioning works

`lib.rs` unconditionally sets these vars in the prod build path:

| Variable | Value | Purpose |
|----------|-------|---------|
| `PHX_SERVER` | `true` | Tells Phoenix to start the HTTP endpoint |
| `PHX_HOST` | `127.0.0.1` | Phoenix URL config — keeps links local |
| `PORT` | `5050` | Avoids port conflict with the dev server on 5001 |
| `DISABLE_AUTH` | `true` | Bypasses passkey auth; WKWebView origin mismatch makes WebAuthn impractical locally |
| `BYPASS_AUTH` | `true` | Secondary auth bypass flag checked by some auth paths |
| `DATABASE_SSL_VERIFY` | `false` | Bundled ERTS has no OpenSSL; local Postgres has no SSL |
| `PHX_DISABLE_FORCE_SSL` | `1` | Disables HSTS + HTTPS redirect so WKWebView doesn't loop on `http://` |

`lib.rs` also provides **hardcoded fallbacks** for two vars when they are not
already present in the environment:

| Variable | Fallback value | Note |
|----------|---------------|------|
| `DATABASE_URL` | `postgres://postgres:postgres@localhost/eits_dev?sslmode=disable` | Works with a standard PostgreSQL install; **fails on Homebrew Postgres** where the superuser is your OS login name, not `postgres` |
| `SECRET_KEY_BASE` | Hardcoded hex string in source | Acceptable for a single-machine desktop app not exposed to the network; all users share the same key unless overridden |

To override either fallback, set the variable in your shell before launching
the binary directly, or place it in `.env`/`.env.local` inside the release
directory (`Eye in the Sky.app/Contents/Resources/rel/`).

### Manual first-run setup

There is no automated provisioner bundled with this build. Before first launch:

1. **Ensure PostgreSQL is running:**
   ```bash
   brew install postgresql@17
   brew services start postgresql@17
   ```

2. **Create the database:**
   ```bash
   createdb eits_dev
   ```

3. **Run migrations** (using the bundled release binary):
   ```bash
   REL="/Applications/Eye in the Sky.app/Contents/Resources/rel"
   DATABASE_URL="ecto://$(whoami)@localhost/eits_dev" \
   DATABASE_SSL_VERIFY=false \
   PHX_SERVER=false \
   DISABLE_AUTH=1 \
   SECRET_KEY_BASE="$(openssl rand -hex 64)" \
   "$REL/bin/eye_in_the_sky" eval "EyeInTheSky.Release.migrate()"
   ```

4. **Override the DATABASE_URL fallback** if you are on Homebrew PostgreSQL (the
   default fallback uses `postgres` user which doesn't exist on Homebrew installs):
   ```bash
   # Launch directly with the correct user
   DATABASE_URL="ecto://$(whoami)@localhost/eits_dev" \
     "/Applications/Eye in the Sky.app/Contents/MacOS/eye-in-the-sky"
   ```

> **Note:** A shell script provisioner (`setup.command`) that automates steps
> 1–4, generates a unique `SECRET_KEY_BASE`, and installs Claude Code hooks is
> under development in the `tauri` branch but is not yet bundled in this build.

### `WEBAUTHN_EXTRA_ORIGINS`

To add extra allowed WebSocket origins (e.g. for Tailscale access), set this
var in the shell before launching the binary directly, or add it to `.env`
inside the release directory:

```
WEBAUTHN_EXTRA_ORIGINS=https://<machine>.<tailnet>.ts.net
```

### Why `PHX_INSECURE_COOKIES=1` is baked at compile time

WebKit drops cookies with `Secure` flag over `http://`. Without `PHX_INSECURE_COOKIES=1`, every LiveView mount gets a fresh empty session, causing ~30 reconnects per second. The `beforeBuildCommand` touches `endpoint.ex` before compiling so this flag is baked into the compiled release — not set at runtime.

---

## Launching the bundled app

Click the app icon to launch normally. The Rust layer starts the Elixir
release, waits for Phoenix to broadcast `"ready"` over ElixirKit PubSub, then
creates the WKWebView window pointing at `http://127.0.0.1:5050`.

**Do not use `open -n "Eye in the Sky.app"`** to launch programmatically.
Launch Services does not pass shell env vars. Always invoke the Tauri binary
directly if you need custom env overrides:

```bash
# Direct binary launch (inherits shell env)
"/Applications/Eye in the Sky.app/Contents/MacOS/eye-in-the-sky"

# With a custom DATABASE_URL (e.g. Homebrew Postgres)
DATABASE_URL="ecto://$(whoami)@localhost/eits_dev" \
  "/Applications/Eye in the Sky.app/Contents/MacOS/eye-in-the-sky"
```

If you need to run the bundled app **alongside** the dev server (port 5001),
the Elixir release will attempt to use the same Erlang node name. The Rust
layer does not set `RELEASE_DISTRIBUTION`, so you need to set it manually
before launching the binary to prevent EPMD collisions:

```bash
RELEASE_DISTRIBUTION=none \
  "/Applications/Eye in the Sky.app/Contents/MacOS/eye-in-the-sky"
```

This avoids the `name eye_in_the_sky seems to be in use by another Erlang node`
error. The `PORT=5050` is already set by `lib.rs`, so no port conflict occurs.

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

Set `WEBAUTHN_EXTRA_ORIGINS` before launching the binary, or add it to `.env`
inside the release directory (`Eye in the Sky.app/Contents/Resources/rel/.env`):

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
| `VAPID_PRIVATE_KEY is required in production` crash | `DISABLE_AUTH` not set | Launch with `DISABLE_AUTH=1` or add it to `rel/.env` in the app bundle |
| `role "postgres" does not exist` | `DATABASE_URL` uses wrong user | Override: `DATABASE_URL="ecto://$(whoami)@localhost/eits_dev" <binary>` |
| Port 5050 already in use | Dev server or stale process | `lsof -i :5050`; kill the conflicting process |
| `EACCES` during build | Stale `target/release/rel/` | `mv src-tauri/target/release/rel /tmp/rel-stale && cargo tauri build` |
| `name eye_in_the_sky seems to be in use` | EPMD node collision with running dev server | `RELEASE_DISTRIBUTION=none <binary>` (must be set before launch; lib.rs does not set it automatically) |
