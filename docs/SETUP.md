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

Caddy listens on 443, terminates TLS with `tls internal`, and proxies to Phoenix on port 5000 (plain HTTP). Both `https://eits.dev` and `https://localhost` are served. Phoenix does not handle TLS directly.

## 4. Start Phoenix

```bash
mix phx.server
```

App is available at `https://eits.dev`.

## 5. Register the first user

WebAuthn registration requires a one-time token. Generate one with:

```bash
mix eits.register <username>
```

Open the printed URL in the browser. It will prompt you to register a passkey (Touch ID, Face ID, or hardware key). Token expires in 15 minutes.

After registering, log in at `https://eits.dev/auth/login`.

Subsequent users also need a registration token — there is no self-signup.

### Logging in

1. Go to `https://eits.dev/auth/login`
2. Enter your username
3. Your browser/device will prompt for a passkey (Touch ID, Face ID, hardware key, or phone)
4. Approve — you're in

Sessions are stored as browser cookies. No password involved.

### Skip auth in dev (DISABLE_AUTH)

If you want to develop without setting up passkeys, set `DISABLE_AUTH=true` in `.env`:

```bash
DISABLE_AUTH=true
```

This bypasses all LiveView session auth. **Dev and test only** — the flag is ignored in production at both compile time and runtime. Caddy still needs to be running for the app to start correctly.

## 6. Claude Code Hooks

EITS uses Claude Code hooks for session lifecycle tracking, task enforcement, and commit logging.

**Hook scripts live in `priv/scripts/` and are registered by absolute path — nothing is copied to `~/.claude/hooks/`.**

Run the install script to generate the `settings.json` snippet:

```bash
./scripts/install.sh
# Prints the full hooks JSON block — manually merge it into ~/.claude/settings.json
```

Registered hooks:

| Event | Script | Purpose |
|-------|--------|---------|
| `SessionStart` (startup/resume/clear) | `eits-session-startup.sh`, `eits-session-resume.sh` | Registers session, writes env vars (`EITS_SESSION_UUID`, `EITS_AGENT_UUID`, `EITS_PROJECT_ID`, `EITS_URL`) to `$CLAUDE_ENV_FILE`, injects context |
| `SessionStart` (compact) | `eits-session-compact.sh` | Resets session to working after compaction |
| `SessionEnd` | `eits-session-end.sh` | Moves in-progress tasks to In Review; marks session `completed` |
| `Stop` | `eits-session-stop.sh` | Sets session status to `idle` after each turn |
| `PreToolUse` (Edit\|Write) | `eits-pre-tool-use.sh` | Blocks edits if session has no name or no active task |
| `PostToolUse` (Bash) | `eits-post-tool-commit.sh` | Logs git commits to EITS automatically |
| `UserPromptSubmit` | `eits-prompt-submit.sh` | Sets session to `working` on each prompt |
| `PreCompact` | `eits-pre-compact.sh` | Sets session to `compacting` before context compaction |

### Disable hooks

Set `EITS_WORKFLOW=0` in your environment or `.env` to disable all hook behavior for a session. All scripts check this var and exit immediately.

### Verify

```bash
# Check scripts exist
ls priv/scripts/eits-*.sh

# Check what's registered
jq '.hooks' ~/.claude/settings.json
```

See [docs/EITS_HOOKS.md](EITS_HOOKS.md) for full hook behavior, context injection details, and the workflow guard.

## 6a. Claude Code Skills

EITS ships a set of skills that live in `~/.claude/skills/`. These are loaded automatically by Claude Code and control how agents interact with the tracking system.

| Skill | Trigger | Purpose |
|-------|---------|---------|
| `eits-init` | Session start | Registers agent + session; required before any file edits |
| `eits-workflow` | `eits-workflow` | Task/commit/note lifecycle (`eits tasks`, `eits commits`, `eits notes`) |
| `eits-dm` | `DM from:` prefix | Receive and reply to inter-agent DMs |
| `eits-chat` | `eits-chat:` prefix | Handle @mentions from the web UI chat |
| `eits-teams` | `eits-teams` | Create teams, spawn agents, monitor coordinated work |
| `eits-superpowers` | `eits-superpowers` | EITS-native dev workflow: task tracking, team spawning, mockup-first UI |
| `i-end-session` | `i-end-session` | Clean session close: update tracking → commit → mark completed (commits auto-logged by hook) |
| `task-workable` | `task-workable` | Create tasks for the auto-worker (haiku or sonnet model) |

**Entrypoint rule** — all skills respect `$CLAUDE_CODE_ENTRYPOINT`:

| Value | Mode | Method |
|-------|------|--------|
| `sdk-cli` | Spawned/headless agent | `EITS-CMD:` directives in stdout |
| `cli` | Interactive session | `eits` bash script |

Skills are version-controlled in `priv/skills/`. Install them by copying to `~/.claude/skills/`:

```bash
cp -r priv/skills/eits-* ~/.claude/skills/
cp -r priv/skills/i-end-session ~/.claude/skills/
cp -r priv/skills/task-workable ~/.claude/skills/
```

Re-run this any time a skill is updated in the repo.

## 7. MCP Server

The EITS MCP server runs at `https://eits.dev/mcp`. Add to `~/.claude/settings.json` under `mcpServers`:

```json
"eits-web": {
  "type": "http",
  "url": "https://eits.dev/mcp"
}
```

## 8. API Key & Environment

The REST API requires a bearer token. Generate one with:

```bash
mix eits.gen.api_key
```

Copy `.env.example` to `.env` and fill in all required variables:

```bash
cp .env.example .env
# edit .env and set:
# - EITS_API_KEY (generated above)
# - VAPID_PRIVATE_KEY (for web push notifications)
```

**Required environment variables for production:**

| Variable | Source | Purpose |
|----------|--------|---------|
| `EITS_API_KEY` | `mix eits.gen.api_key` | REST API authentication |
| `VAPID_PRIVATE_KEY` | Generate via `mix run -e '{pub, priv} = :crypto.generate_key(:ecdh, :prime256v1); IO.puts(Base.url_encode64(priv, padding: false))'` | Web push notifications (raises at startup if missing in prod) |
| `VAPID_PUBLIC_KEY` | Same command above | Public key for service worker (optional in dev, defaults to committed value) |

Phoenix loads `.env` automatically at startup via `dotenvy`.

Add both to `~/.zshrc` for persistence:

```bash
export EITS_API_KEY="<generated-key>"
export EITS_URL="http://localhost:5000/api/v1"
```

**Webhook configuration (optional for dev):**

By default, unsigned Gitea webhooks are rejected in all environments. To allow unsigned webhooks in dev for testing:

```elixir
# config/dev.exs
config :eye_in_the_sky_web, :allow_unsigned_webhooks, true
```

**Reverse proxy configuration (Tailscale, ngrok):**

If you're accessing the app via a reverse proxy (Tailscale Funnel, ngrok, etc.), the `RemoteIp` plug needs to trust that proxy to correctly rewrite `X-Forwarded-For` headers.

The app is configured to trust:
- Loopback (127.0.0.1/8)
- RFC 1918 private ranges (10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16)
- Tailscale CGNAT (100.64.0.0/10) — for Tailscale Funnel and other Tailscale reverse proxies

No additional configuration is needed for Tailscale. The CGNAT range is already configured in `endpoint.ex`.

## 9. PWA & Web Push (Optional)

The app includes Web Push and PWA install capability.

**Browser setup:**
1. Visit `https://eits.dev` (requires HTTPS via Caddy)
2. Browser may prompt to "Install app" or show in app menu
3. Click install to add to home screen / app drawer

**Push notifications:**
1. Browser requests permission when registering service worker
2. Grant "Allow notifications" when prompted
3. Subscriptions are stored in `/push_subscriptions` table via REST API

**Service worker:**
- Registered from `assets/js/push_notifications.js`
- Runs at `priv/static/sw.js`
- Handles incoming push events and displays notifications

**Configuration (production):**
Set `WEB_PUSH_ENCRYPTION_KEY` env var (base64-encoded 16-byte key) for push encryption. Missing key disables push (app still works).

---

## 10. CLI Tools

The `scripts/eits` script provides shell access to the REST API.

**Add to PATH** (add to `~/.zshrc`):

```bash
export PATH="$HOME/projects/eits/web/scripts:$PATH"
export EITS_API_KEY="<generated-key>"
export EITS_URL="http://localhost:5000/api/v1"
```

**Usage:**

```bash
eits projects list
eits tasks list --project 1 --state 2
eits tasks create --title "fix auth bug" --project 1
eits tasks done 42
eits notes create --parent-type session --parent-id <uuid> --body "finding"
eits dm --from agent-1 --to <session_uuid> --message "hello"
```

Requires `curl` and `jq`.

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
| Port | 5000 (HTTP) | 5002 |
| TLS | Caddy handles (port 443) | Caddy handles (port 443) |
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

## ngrok (External Access / Tunneling)

ngrok creates a public HTTPS tunnel to your local dev server, useful for testing webhooks, mobile access, or sharing your dev instance.

**Install:**

```bash
brew install ngrok
```

**Authenticate (one-time):**

Sign up at [ngrok.com](https://ngrok.com), then:

```bash
ngrok config add-authtoken <your-token>
```

Get your token from the ngrok dashboard under "Your Authtoken". Without this step you'll get `err_ngrok_3004`.

**Start tunnel:**

```bash
# Tunnel to Phoenix — must specify http:// explicitly
ngrok http http://localhost:5000
```

ngrok will display a public URL like `https://abc123.ngrok-free.app`. Use that to access your local app externally.

**Important:** Always use `http://localhost:5000`, not just `5000`. Without the scheme, ngrok may try HTTPS to your upstream and fail with `err_ngrok_3004` ("invalid or incomplete HTTP response").

**Common errors:**

| Error | Fix |
|-------|-----|
| `err_ngrok_3004` (auth) | Run `ngrok config add-authtoken <token>` |
| `err_ngrok_3004` (gateway) | Use `ngrok http http://localhost:5000` — ngrok is sending HTTPS to a plain HTTP server |
| `err_ngrok_108` | ngrok agent already running; kill it with `pkill ngrok` |
| `err_ngrok_334` | Endpoint already online; kill existing ngrok first |

**Notes:**
- Free tier gives one tunnel at a time with random subdomain
- The public URL changes each restart unless you have a paid plan with reserved domains
- LiveView WebSocket connections work through ngrok out of the box

### WebAuthn via ngrok

WebAuthn ties credentials to an origin. To register or log in through an ngrok URL, you must tell the server to accept that origin.

**1. Add the ngrok URL to `.env`:**

```bash
WEBAUTHN_EXTRA_ORIGINS=https://your-subdomain.ngrok-free.app
```

Comma-separate multiple origins if needed. This is read at boot via `Dotenvy.source/1` — restart the server after editing.

**2. Restart Phoenix:**

```bash
mix phx.server
```

**3. Generate a registration token:**

```bash
mix eits.register <username>
```

Replace the domain in the printed URL with your ngrok URL:

```
https://your-subdomain.ngrok-free.app/auth/register?token=<token>
```

Open that URL on the device you want to register (e.g., iPhone). The passkey will be bound to the ngrok `rp_id` and will work for login via that ngrok URL.

**Note:** Passkeys registered via ngrok (`rp_id: your-subdomain.ngrok-free.app`) are separate credentials from those registered via `eits.dev`. Both can coexist — the server accepts challenges from either origin independently.

---

## Key Notes

- Migrations auto-run on startup via `Ecto.Migrator` — no manual step needed beyond `ecto.setup`
- Caddy `tls internal` auto-generates and manages the local cert; run `caddy trust` once to install the CA
- Phoenix serves plain HTTP on port 5000; Caddy handles all TLS on port 443
- `.env` is loaded automatically at startup via `dotenvy`; copy `.env.example` to get started
- No `.tool-versions` or `.nvmrc` — use Node 22 LTS
- Oban background jobs require the DB to be up before server starts
- `mix precommit` runs compile + deps.unlock + format + test in one shot; run before committing
