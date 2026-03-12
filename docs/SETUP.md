# Local Development Setup

## System Dependencies

| Dependency | Version | Notes |
|-----------|---------|-------|
| Elixir | 1.15+ | OTP 26+ included |
| Node.js | 22 LTS | Svelte 5 + esbuild require 18+ |
| PostgreSQL | 12+ | `eits_dev` database |
| Caddy | any | HTTPS proxy for WebAuthn |
| NATS | optional | Port 4222, currently disabled in code |

```bash
brew install elixir node postgresql caddy
brew services start postgresql
createuser -P postgres   # password: postgres
```

## 1. Clone & Deps

```bash
mix deps.get
cd assets && npm install && cd ..
```

## 2. Database

```bash
mix ecto.setup   # creates DB + runs all migrations
```

Or manually:

```bash
mix ecto.create
mix ecto.migrate
```

## 3. HTTPS via Caddy (required for WebAuthn/passkeys)

WebAuthn requires HTTPS with a matching origin. The app is configured for `https://eits.dev`.

**Add to `/etc/hosts`:**

```bash
sudo sh -c 'echo "127.0.0.1 eits.dev" >> /etc/hosts'
```

**Trust Caddy's local CA (one-time):**

```bash
caddy trust
```

**Start Caddy** (from project root, in a separate terminal):

```bash
caddy run --config Caddyfile
```

Caddy listens on port 443 and proxies to Phoenix on port 5000. Phoenix itself does not need to serve HTTPS directly for local dev.

## 4. Start Phoenix

```bash
mix phx.server
```

App is available at `https://eits.dev`.

## 5. Register the first user

WebAuthn registration requires a one-time token. Generate one in iex:

```bash
iex -S mix
```

```elixir
{:ok, token} = EyeInTheSkyWeb.Accounts.create_registration_token("your_username")
IO.puts("https://eits.dev/auth/register?token=#{token.token}")
```

Open that URL in the browser. It will prompt you to register a passkey (Touch ID, Face ID, or hardware key). Token expires in 15 minutes.

After registering, log in at `https://eits.dev/auth/login`.

Subsequent users also need a registration token — there is no self-signup.

## 6. Claude Code Hooks

EITS uses Claude Code hooks for session tracking, task logging, and MCP integration.

```bash
./priv/scripts/install.sh
# Manually merge the output into ~/.claude/settings.json
```

Hooks registered:

| Hook | Purpose |
|------|---------|
| `SessionStart` | Registers session, sets `EITS_SESSION_ID`, `EITS_AGENT_ID`, `EITS_PROJECT_ID` |
| `SessionEnd` | Marks session completed |
| `Stop` | Marks session waiting |
| `PreToolUse` / `PostToolUse` | Action logging |

## 7. MCP Server

The EITS MCP server runs at `http://localhost:5000/mcp`. Add to `~/.claude.json` under `mcpServers`:

```json
"eits-web": {
  "type": "http",
  "url": "http://localhost:5000/mcp"
}
```

---

## Supabase (Alternative DB)

A `supabase-db` git worktree is configured at `.claude/worktrees/supabase-db` pointing to a Supabase-hosted Postgres instance instead of local `eits_dev`.

**Worktree location:** `.claude/worktrees/supabase-db`
**Branch:** `supabase-db`
**DB host:** `db.flcmhdqoulbmvnqrolux.supabase.co:5432` (IPv6 direct connection)
**Region:** AWS us-east-1 (North Virginia)

### Start the Supabase-backed app

```bash
# From worktree (runs on port 5002, Caddy proxies eits.dev → 5002)
cd .claude/worktrees/supabase-db
mix phx.server
```

Caddy (`Caddyfile`) proxies `eits.dev` → `localhost:5002` when using this worktree.

To switch back to local DB, update `Caddyfile` to proxy to `localhost:5000` and run `caddy reload --config Caddyfile`.

### Key config differences from local dev

| | Local | Supabase worktree |
|--|--|--|
| DB | `eits_dev` on localhost | Supabase PostgreSQL (IPv6) |
| Port | 5000 | 5002 |
| HTTPS listener | Port 5001 (self-signed) | Disabled (Caddy handles TLS) |
| Oban notifier | `Oban.Notifiers.PG` | `Oban.Notifiers.Postgres` (poll-based; Supabase `postgres` user can't use `LISTEN/NOTIFY`) |
| `socket_options` | default | `[:inet6]` (Supabase direct connection is IPv6-only) |

### Supabase gotchas

- **Network restrictions**: Supabase has IP allowlisting under Project Settings → Database → Network restrictions. Your IPv6 must be allowed.
- **Direct connection is IPv6-only**: The `db.xxx.supabase.co:5432` host has no A record. Erlang needs `socket_options: [:inet6]` to connect. If using the session pooler instead, remove that option and use `aws-0-us-east-1.pooler.supabase.com:5432` with username `postgres.<project-ref>`.
- **Oban notifier**: `Oban.Notifiers.PG` uses `LISTEN/NOTIFY` which requires superuser. Supabase's `postgres` user is not a superuser. Use `Oban.Notifiers.Postgres` (poll-based) instead.
- **Free tier pausing**: Supabase free/nano plans pause projects after 7 days of inactivity. Resume from the dashboard if connections are refused.

### Re-migrating data

If you need to re-sync local → Supabase:

```bash
# 1. Drop all FK constraints on Supabase (see migration session notes)
# 2. Truncate all tables
# 3. Dump and restore
pg_dump eits_dev --no-owner --no-acl --data-only | \
  PGPASSWORD='<password>' psql "postgresql://postgres@db.flcmhdqoulbmvnqrolux.supabase.co:5432/postgres"
# 4. Null out orphaned FK refs (agents.project_id = 0, etc.)
# 5. Re-add FK constraints
```

---

## Key Notes

- Migrations auto-run on startup via `Ecto.Migrator` — no manual step needed beyond `ecto.setup`
- Caddy `tls internal` auto-generates and manages the local cert; no manual cert generation needed
- Phoenix also has an HTTPS listener on port 5001 (`priv/cert/localhost+2.pem`) but that cert is for `localhost`, not `eits.dev` — use Caddy on 443 for WebAuthn
- No `.tool-versions` or `.nvmrc` — use Node 22 LTS
- No `.env.example` — dev uses hardcoded values in `config/dev.exs`; prod vars are documented in `config/runtime.exs`
- Oban background jobs require the DB to be up before server starts
