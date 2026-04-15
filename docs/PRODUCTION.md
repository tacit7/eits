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
- A target Postgres database:
  - local: `eits_dev` already set up (`mix ecto.setup`)
  - Supabase: a project database or session pooler connection string

## Required `.env` variables

Before building, ensure the env file you are using contains all of these. Missing required production values will raise at boot time.

| Variable | How to generate |
|----------|----------------|
| `VAPID_PUBLIC_KEY` | `mix run -e '{pub, priv} = :crypto.generate_key(:ecdh, :prime256v1); IO.puts("VAPID_PUBLIC_KEY=" <> Base.url_encode64(pub, padding: false))'` |
| `VAPID_PRIVATE_KEY` | Same command (generate both together, never mix keys from separate runs) |
| `WEBAUTHN_ORIGIN` | Your app's full origin, e.g. `https://your-subdomain.ngrok-free.app` |
| `WEBAUTHN_RP_ID` | Registrable domain only, e.g. `your-subdomain.ngrok-free.app` |
| `SECRET_KEY_BASE` | `mix phx.gen.secret` (must be 64+ bytes) |
| `DATABASE_URL` | Local: `ecto://postgres:postgres@localhost/eits_dev`; Supabase: session pooler URL |
| `PHX_HOST` | Host only, no scheme, e.g. `your-subdomain.ngrok-free.app` |
| `PHX_SERVER` | `true` for release/server startup |
| `PORT` | Local HTTP port, usually `5001` |

Runtime config reads values from Dotenvy and from the shell. Exporting the env file is still recommended for release builds and for commands that run outside Phoenix config:

```bash
set -a
source .env
set +a
```

Use `source .env_supabase` instead when running against Supabase.

## Supabase setup

Use the Supabase **session pooler** connection string for this app. The direct database URL can require IPv6 and may fail from some local networks or hosts. The session pooler URL looks like this:

```bash
DATABASE_URL="postgresql://postgres.<project-ref>:<password>@aws-1-us-east-1.pooler.supabase.com:5432/postgres"
```

Recommended Supabase env file:

```bash
# .env_supabase
DATABASE_URL="postgresql://postgres.<project-ref>:<password>@aws-1-us-east-1.pooler.supabase.com:5432/postgres"
POOL_SIZE=5
ECTO_IPV6=false

PHX_SERVER=true
PHX_HOST=your-subdomain.ngrok-free.app
PORT=5001

WEBAUTHN_ORIGIN=https://your-subdomain.ngrok-free.app
WEBAUTHN_RP_ID=your-subdomain.ngrok-free.app
WEBAUTHN_EXTRA_ORIGINS=https://your-subdomain.ngrok-free.app

SECRET_KEY_BASE=<64+ byte secret from mix phx.gen.secret>
VAPID_PUBLIC_KEY=<public key>
VAPID_PRIVATE_KEY=<private key>
EITS_API_KEY=<optional API key>
GITEA_WEBHOOK_SECRET=<optional webhook secret>
```

The app config sets `prepare: :unnamed` for Supabase pooler compatibility and enables SSL for `DATABASE_URL` in dev and prod.

### Restoring local data into Supabase

For a clean migration from local `eits_dev` to Supabase, prefer a full custom-format dump and restore.

```bash
# 1. Create a full local dump
pg_dump -U postgres -d eits_dev \
  --no-owner \
  --no-acl \
  --format=custom \
  --file=/tmp/eits_dev_full_for_supabase.dump

# 2. Export Supabase env
set -a
source .env_supabase
set +a

# 3. Reset only Supabase's public schema
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c '
DROP SCHEMA public CASCADE;
CREATE SCHEMA public;
GRANT USAGE ON SCHEMA public TO postgres, anon, authenticated, service_role;
GRANT ALL ON SCHEMA public TO postgres;
'

# 4. Restore schema and data
pg_restore \
  --no-owner \
  --no-acl \
  --no-comments \
  --exit-on-error \
  --dbname "$DATABASE_URL" \
  /tmp/eits_dev_full_for_supabase.dump
```

If the restore fails while adding foreign keys, inspect the error before retrying. In the existing local data we migrated, a few legacy rows referenced missing parents. The fixes used were:

```sql
update agents
set project_id = null
where project_id = 0;

update messages
set session_id = null
where session_id is not null
and not exists (select 1 from sessions s where s.id = messages.session_id);

delete from session_metrics
where session_id is not null
and not exists (select 1 from sessions s where s.id = session_metrics.session_id);

delete from task_sessions
where not exists (select 1 from tasks t where t.id = task_sessions.task_id)
or not exists (select 1 from sessions s where s.id = task_sessions.session_id);

delete from task_tags
where not exists (select 1 from tasks t where t.id = task_tags.task_id)
or not exists (select 1 from tags g where g.id = task_tags.tag_id);
```

Then replay the remaining foreign-key constraints from the dump list instead of reloading all data.

Verify Supabase after restore:

```bash
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c '
select count(*) as tables
from information_schema.tables
where table_schema = '\''public'\'' and table_type = '\''BASE TABLE'\'';

select count(*) as migrations from schema_migrations;

select count(*) as foreign_keys
from pg_constraint
where connamespace = '\''public'\''::regnamespace and contype = '\''f'\'';
'
```

## Quick start

### Local Postgres

```bash
# 0. Export .env into shell
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

### Supabase

```bash
# 0. Export Supabase env
set -a
source .env_supabase
set +a

# 1. Build everything
MIX_ENV=prod mix assets.deploy
MIX_ENV=prod mix release --overwrite

# 2. Start the release
_build/prod/rel/eye_in_the_sky/bin/eye_in_the_sky start
```

Access through the host in `PHX_HOST`. For an ngrok-backed local release:

```bash
ngrok http http://localhost:5001
```

The release process should show a Supabase pooler `DATABASE_URL` if inspected:

```bash
ps eww -p "$(pgrep -f '_build/prod/rel/eye_in_the_sky/.*/beam.smp' | head -n 1)" \
  | tr ' ' '\n' \
  | rg 'DATABASE_URL|PHX_HOST|PORT|POOL_SIZE|ECTO_IPV6'
```

Do not paste the raw process output into shared logs unless the password is redacted.

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
set -a; source .env_supabase; set +a  # or source .env for local Postgres
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
| `POOL_SIZE` | no | `.env_supabase` | Supabase pooler connections; use `5` locally |
| `ECTO_IPV6` | no | `.env_supabase` | Use `false` for Supabase pooler; direct Supabase DB may require IPv6 |
| `SECRET_KEY_BASE` | yes | `.env` (generate once: `openssl rand -hex 64`) | Cookie signing (64+ bytes) |
| `PHX_HOST` | yes | you set it | Domain for URL generation |
| `PHX_SERVER` | yes | set to `true` | Starts the HTTP server. Only `true` or `1` enable it |
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
Export the env file before building or starting:

```bash
set -a
source .env_supabase  # or .env
set +a
```

**App is still using local Postgres instead of Supabase**
Verify the env file and the live Ecto connection:

```bash
rg '^DATABASE_URL=' .env .env_supabase

PHX_SERVER=false mix run -e '
r = EyeInTheSky.Repo.query!("select current_database(), current_user, inet_server_addr()::text, inet_server_port(), version()", [])
IO.inspect(r.rows, label: "repo_connection")
'
```

Supabase should report database `postgres`, PostgreSQL `17.x`, and the pooler URL should use `aws-...pooler.supabase.com`. Local Postgres usually reports database `eits_dev` and `Postgres.app`.

**Supabase direct URL connection refused**
Use the session pooler URL from Supabase instead of `db.<project-ref>.supabase.co`. Direct URLs can require IPv6.

**Supabase password authentication failed**
Reset or copy the database password in Supabase and update `DATABASE_URL`. URL-encode special characters in the password if you build the URL manually.

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
