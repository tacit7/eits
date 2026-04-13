# Running EITS in Production Mode

Production mode gives you compiled releases, pre-built assets, and Node SSR — the same setup that runs on a deployed server, but locally.

## When to use prod mode

- Testing that assets, SSR, and the full pipeline work end-to-end
- Checking performance (releases are faster than `mix phx.server`)
- Verifying the build before deploying
- Running on a mobile device via ngrok

For day-to-day development, use `mix phx.server` (dev mode) instead.

## Prerequisites

Same as dev setup (see [SETUP.md](SETUP.md)). You need:

- Elixir/OTP, Node.js, PostgreSQL, Caddy
- A working `.env` file with VAPID keys, API key, etc.
- The `eits_dev` database already set up (`mix ecto.setup`)

## Required `.env` variables

Before building, ensure `.env` contains all of these (missing any will raise at build time):

| Variable | How to generate |
|----------|----------------|
| `VAPID_PUBLIC_KEY` | `mix run -e '{pub, priv} = :crypto.generate_key(:ecdh, :prime256v1); IO.puts("VAPID_PUBLIC_KEY=" <> Base.url_encode64(pub, padding: false))'` |
| `VAPID_PRIVATE_KEY` | Same command (generate both together, never mix keys from separate runs) |
| `WEBAUTHN_ORIGIN` | Your app's full origin, e.g. `https://your-subdomain.ngrok-free.app` |
| `WEBAUTHN_RP_ID` | Registrable domain only, e.g. `your-subdomain.ngrok-free.app` |
| `SECRET_KEY_BASE` | `mix phx.gen.secret` (must be 64+ bytes) |
| `DATABASE_URL` | `ecto://postgres:postgres@localhost/eits_dev` |

**Important:** `dotenvy` does not reliably inject new env vars into the Erlang system env during `mix` commands. Always use `set -a; source .env; set +a` before any `MIX_ENV=prod mix` command — this exports all `.env` vars into the shell so they're available to the Erlang runtime.

## Quick start

```bash
# 0. Export .env into shell (required — dotenvy alone is not enough for mix commands)
set -a; source .env; set +a

# 1. Build everything
MIX_ENV=prod mix assets.deploy        # tailwind + vite client + vite SSR + phx.digest
MIX_ENV=prod mix release --overwrite  # compile BEAM release

# 2. Run it (from project root so dotenvy finds .env)
source .env
DATABASE_URL="ecto://postgres:postgres@localhost/eits_dev" \
WEBAUTHN_ORIGIN="https://eits.dev" \
WEBAUTHN_RP_ID="eits.dev" \
PHX_HOST="eits.dev" \
PHX_SERVER=true \
PORT=5001 \
_build/prod/rel/eye_in_the_sky/bin/eye_in_the_sky start
```

The release runs in the background. Access at `https://eits.dev` (through Caddy).

**All env vars from `.env` are loaded automatically** via Dotenvy. You only need to provide the ones that `.env` doesn't have: `DATABASE_URL`, `WEBAUTHN_ORIGIN`, `WEBAUTHN_RP_ID`, `PHX_HOST`.

## Managing the release

```bash
# Stop
_build/prod/rel/eye_in_the_sky/bin/eye_in_the_sky stop

# Remote console (attach to running node)
_build/prod/rel/eye_in_the_sky/bin/eye_in_the_sky remote

# Check if running
_build/prod/rel/eye_in_the_sky/bin/eye_in_the_sky pid
```

## What `mix assets.deploy` does

Four steps in sequence:

1. `tailwind eye_in_the_sky --minify` — compiles CSS
2. `vite build` — client JS bundle to `priv/static/`
3. `vite build --ssr js/server.js --outDir ../priv/svelte` — SSR bundle for Node
4. `phx.digest` — fingerprints all static files for cache busting

## Rebuilding after code changes

```bash
# Full rebuild
MIX_ENV=prod mix assets.deploy
MIX_ENV=prod mix release --overwrite

# Then restart
_build/prod/rel/eye_in_the_sky/bin/eye_in_the_sky stop
# ... start command from above ...
```

The `MIX_ENV=prod` prefix is needed for `mix` commands. The release binary doesn't need it; it's always prod.

## Environment variables reference

| Variable | Required | Source | Purpose |
|----------|----------|--------|---------|
| `DATABASE_URL` | yes | you set it | Postgres connection string |
| `SECRET_KEY_BASE` | yes | `.env` (generate once: `openssl rand -hex 64`) | Cookie signing (64+ bytes) |
| `PHX_HOST` | yes | you set it | Domain for URL generation |
| `PHX_SERVER` | yes | set to `true` | Starts the HTTP server |
| `PORT` | no | default 4000 | HTTP listen port |
| `WEBAUTHN_ORIGIN` | yes | you set it | WebAuthn origin (e.g., `https://eits.dev`) |
| `WEBAUTHN_RP_ID` | yes | you set it | WebAuthn relying party ID (e.g., `eits.dev`) |
| `VAPID_PUBLIC_KEY` | yes | `.env` | Web push (loaded from .env) |
| `VAPID_PRIVATE_KEY` | yes | `.env` | Web push (loaded from .env) |
| `EITS_API_KEY` | no | `.env` | REST API auth (loaded from .env) |
| `WEBAUTHN_EXTRA_ORIGINS` | no | `.env` | Extra allowed origins for websockets and passkeys (comma-separated) |

## Differences from dev mode

| | Dev (`mix phx.server`) | Prod (release) |
|--|--|--|
| Assets | Vite dev server with HMR | Pre-built, fingerprinted, gzip'd |
| SSR | ViteJS (HTTP to Vite dev server) | NodeJS (subprocess, `priv/svelte/server.js`) |
| Code reload | Yes | No |
| Error pages | Debug with stacktraces | Generic 500 |
| Logger | Debug level | Info level |
| Auth bypass | `DISABLE_AUTH=true` works | Ignored; passkeys required |
| Startup | ~5s (compile check) | ~1s (pre-compiled BEAM) |

## Accessing via ngrok

The prod release works with ngrok. Add your ngrok domain to `.env`:

```bash
WEBAUTHN_EXTRA_ORIGINS=https://your-subdomain.ngrok-free.app
```

This allows both WebSocket connections and passkey auth from the ngrok origin. Rebuild the release after changing `.env` since `check_origin` is set at boot.

```bash
ngrok http http://localhost:5001
```

## Troubleshooting

**`VAPID_PRIVATE_KEY environment variable is required in production`** (even though it's in `.env`)
`dotenvy`'s `source!/1` does not reliably set new env vars into the Erlang system env during `mix` commands. Fix: always prefix with `set -a; source .env; set +a` before any `MIX_ENV=prod mix` command.

**`The module LiveSvelte.SSR.NodeJS.Supervisor was given as a child to a supervisor but it does not exist`**
Caused by `alias LiveSvelte.SSR.NodeJS` in `application.ex` shadowing the `NodeJS` package — `NodeJS.Supervisor` resolved to the wrong module. Fixed in `application.ex`: alias removed, `NodeJS.Supervisor` used directly, `LiveSvelte.SSR.NodeJS.server_path()` fully qualified.

**`cookie store expects conn.secret_key_base to be at least 64 bytes`**
Your `SECRET_KEY_BASE` is too short. Use `openssl rand -hex 64` (produces 128 hex chars).


**WebSocket 403 on ngrok**
Add the ngrok URL to `WEBAUTHN_EXTRA_ORIGINS` in `.env` and rebuild the release.

**`Could not start application esbuild`**
Run `mix deps.unlock esbuild && mix deps.get` — stale lockfile reference.

**Erlang node name conflict**
Previous release didn't stop cleanly:
```bash
pkill -f eye_in_the_sky
_build/prod/rel/eye_in_the_sky/bin/eye_in_the_sky start
```
