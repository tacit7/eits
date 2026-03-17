# Security

Security architecture and controls for the Eye in the Sky web application.

Last audited: 2026-03-17

## Authentication

### Browser — WebAuthn / Passkeys

All browser routes require WebAuthn passkey authentication via `AuthHook` (LiveView `on_mount`).

- **Library**: `wax_` ~> 0.7
- **Registration**: Token-gated. Registration tokens are generated with `:crypto.strong_rand_bytes(32)`, Base64URL-encoded, with a 15-minute TTL. Tokens are consumed (deleted) after use — single-use only.
- **Login**: Challenge-response with passkey. Challenges are serialized to JSON in the session cookie (no Erlang `binary_to_term`).
- **Session rotation**: `configure_session(renew: true)` is called after both `login_complete` and `register_complete` to prevent session fixation.
- **Sign count tracking**: Passkey sign counts are verified and updated on each authentication to detect cloned authenticators.
- **DISABLE_AUTH bypass**: The `DISABLE_AUTH=true` env var skips LiveView auth. Guarded at both compile time (`config_env() != :prod`) and runtime (`env != :prod`). Cannot be activated in production.

### API — Bearer Token

All `/api/v1/*` routes (except webhooks and public settings) require a Bearer token via the `RequireAuth` plug.

- **Token comparison**: Uses `Plug.Crypto.secure_compare/2` (constant-time) to prevent timing attacks.
- **Secure by default in production**: If `EITS_API_KEY` is not set, the plug rejects all requests in production. Dev/test environments allow passthrough for convenience.
- **Token generation**: `mix eits.gen.api_key` generates a cryptographically random key.
- **Single shared token**: No per-user scoping. Suitable for single-user deployments.

### Webhook — HMAC Signature

`POST /api/v1/webhooks/gitea` uses HMAC-SHA256 signature verification.

- **Secret source**: `GITEA_WEBHOOK_SECRET` env var.
- **Comparison**: `Plug.Crypto.secure_compare/2` on the computed vs received signature.
- **Secure by default**: Unsigned requests are rejected in all environments. Dev can opt in to unsigned requests via `config :eye_in_the_sky_web, :allow_unsigned_webhooks, true` in `config/dev.exs`.

## Session Security

### Cookie Configuration

Defined in `endpoint.ex` `@session_options`:

| Flag | Value | Purpose |
|------|-------|---------|
| `store` | `:cookie` | Signed cookie (tamper-proof, not encrypted) |
| `signing_salt` | Configured | HMAC signing salt for cookie integrity |
| `same_site` | `"Lax"` | Prevents CSRF via cross-origin requests |
| `http_only` | `true` | Cookie inaccessible to JavaScript (XSS protection) |
| `secure` | `true` in prod, `false` in dev | Cookie only sent over HTTPS in production |

### CSRF Protection

- Browser routes use Phoenix's `protect_from_forgery` plug via the `:browser` pipeline.
- WebAuthn JSON endpoints skip CSRF but are protected by challenge-response binding and rate limiting.
- API routes use Bearer token auth (stateless, no CSRF needed).
- CSRF meta tag is rendered in `root.html.heex` for LiveView form submissions.

## Transport Security

### HTTPS Enforcement

- **Production**: `force_ssl: [hsts: true, rewrite_on: [:x_forwarded_proto]]` in `runtime.exs`.
- HTTP requests are redirected to HTTPS. HSTS header tells browsers to always use HTTPS.
- `rewrite_on: [:x_forwarded_proto]` supports TLS-terminating reverse proxies (nginx, Tailscale Funnel, ngrok).

### Proxy Support

- `RemoteIp` plug in `endpoint.ex` rewrites `conn.remote_ip` from `X-Forwarded-For` headers.
- Placed before `Plug.Session` and the router so all downstream plugs and rate limiting see the real client IP.
- Trusts only loopback and private ranges as proxies by default.

## Rate Limiting

Hammer v7 with ETS backend, applied to the `:webauthn` pipeline.

| Endpoint | Limit | Window | Purpose |
|----------|-------|--------|---------|
| `POST /auth/login/challenge` | 10 | 1 minute | Username enumeration prevention |
| `POST /auth/login/complete` | 5 | 5 minutes | Brute force prevention |
| `POST /auth/register/challenge` | 5 | 1 hour | Registration abuse prevention |
| `POST /auth/register/complete` | 5 | 1 hour | Registration abuse prevention |

- Keyed by remote IP (real IP via `RemoteIp` plug).
- Returns `429 Too Many Requests` with JSON error body when exceeded.
- Supervised via `EyeInTheSkyWeb.RateLimiter` in the application supervision tree.

## Authorization

### Route-Level Access Control

| Route Pattern | Auth Method | Pipeline |
|---------------|-------------|----------|
| `/auth/login`, `/auth/register` | Public | `:browser` |
| `/auth/logout` | Session (clears it) | `:browser` |
| `/auth/*/challenge`, `/auth/*/complete` | Rate-limited, challenge-bound | `:webauthn` |
| `/` and all LiveView routes | Session + AuthHook | `:browser` + `AuthHook` |
| `/oban` dashboard | Session + RequireAuth | `:browser` + `:require_auth` |
| `/api/v1/*` | Bearer token | `:api` (includes `RequireAuth`) |
| `/api/v1/webhooks/gitea` | HMAC signature | `:accepts_json` (no Bearer) |
| `/api/v1/settings/eits_workflow_enabled` | Public (read-only) | `:accepts_json` |
| `/dev/*` | Dev-only (compile-time flag) | `:browser` |
| Static assets | Public | `Plug.Static` (allowlisted paths only) |

### Static File Serving

`Plug.Static` is configured with an `only` allowlist: `~w(assets fonts images favicon.ico robots.txt sw.js manifest.json)`. The `uploads/` directory is deliberately excluded — uploaded files are stored in `priv/static/uploads/` but are not served via HTTP.

### EditorController

`POST /api/v1/editor/open` executes a system editor on a file path. Hardened with:

- **Editor allowlist**: Only `code`, `vim`, `nvim`, `nano`, `emacs`, `cursor`, `zed` are permitted.
- **Path prefix validation**: Paths are expanded with `Path.expand/1` and must start with the configured `allowed_path_prefix` (defaults to user home directory). Paths outside this prefix are rejected with 422.

## Input Validation

### Database

- All database access uses Ecto with parameterized queries — no raw SQL.
- Input validation via Ecto changesets on all mutations.
- PostgreSQL database (`eits_dev`) with standard connection pooling.

### WebAuthn Challenge Serialization

Challenges are serialized to JSON (not Erlang `binary_to_term`) before storing in the session cookie:

- Binary fields (challenge bytes, credential IDs) are Base64-encoded.
- Atoms use `String.to_existing_atom/1` on deserialization to prevent atom table pollution.
- Function references (`origin_verify_fun`) are hardcoded on reconstruction, never deserialized.
- COSE keys use integer-keyed JSON maps with Base64-encoded binary values.

### File Uploads

- Restricted to specific extensions: `.jpg`, `.jpeg`, `.png`, `.gif`, `.pdf`, `.txt`, `.md`, `.csv`, `.json`, `.xml`, `.html`.
- Max 10 files per upload, 50MB per file.
- Files stored with UUID filenames (original name discarded for storage).
- Upload paths in message bodies use relative paths from web root, not absolute filesystem paths.

## Secure Headers

Phoenix's `put_secure_browser_headers` plug adds:

| Header | Value |
|--------|-------|
| `x-frame-options` | `SAMEORIGIN` |
| `x-content-type-options` | `nosniff` |
| `x-xss-protection` | `1; mode=block` |

**Not yet implemented**: Content-Security-Policy (CSP). The app uses inline scripts for theme initialization and loads Google Fonts from external CDNs, which requires a nonce-based or hash-based CSP configuration.

## Secrets Management

### Environment Variables

All secrets are loaded from environment variables via `.env` file (loaded by `dotenvy` at startup):

| Secret | Env Var | Required In |
|--------|---------|-------------|
| API bearer token | `EITS_API_KEY` | Prod (rejects without it) |
| VAPID public key | `VAPID_PUBLIC_KEY` | All (for web push) |
| VAPID private key | `VAPID_PRIVATE_KEY` | Prod (raises without it) |
| Gitea webhook secret | `GITEA_WEBHOOK_SECRET` | All (rejects unsigned without it) |
| Database URL | `DATABASE_URL` | Prod |
| Secret key base | `SECRET_KEY_BASE` | Prod |
| WebAuthn extra origins | `WEBAUTHN_EXTRA_ORIGINS` | Optional (for ngrok tunnels) |

No secrets are committed to source code. The `.env` file is in `.gitignore`. `.env.example` contains placeholders and generation instructions.

### Key Rotation

**VAPID keys**:
```bash
mix run -e '{pub, priv} = :crypto.generate_key(:ecdh, :prime256v1); IO.puts("VAPID_PUBLIC_KEY=#{Base.url_encode64(pub, padding: false)}"); IO.puts("VAPID_PRIVATE_KEY=#{Base.url_encode64(priv, padding: false)}")'
```
Update `.env`, restart server, delete stale `push_subscriptions` rows. Clients must re-subscribe.

**API key**:
```bash
mix eits.gen.api_key
```
Update `.env` and all hook/CLI configurations that use it.

## Process Execution

### Claude CLI Spawning

The app spawns Claude CLI processes as Erlang Ports:

- Process arguments are built from a validated keyword list with known flags only.
- Sensitive flags (`-p`, `--system-prompt`, `--append-system-prompt`) are redacted in logs via `safe_log_args/1`.
- Port output buffer is capped at 4MB to prevent memory exhaustion.
- Idle timeout (configurable, default 5 minutes) kills stalled processes.
- Process cancellation sends `SIGTERM` to the process group, with `SIGKILL` fallback.

### Webhook Agent Spawning

The Gitea webhook controller spawns review agents with project path from config (not hardcoded). The `project_path` is configurable via `Application.get_env(:eye_in_the_sky_web, :project_path)`.

## Dev-Only Features

These features are gated behind `Application.compile_env(:eye_in_the_sky_web, :dev_routes)` — they do not exist in production builds:

- `/dev/dashboard` — Phoenix LiveDashboard (telemetry metrics)
- `/dev/mailbox` — Swoosh email preview
- `/dev/test-login` — Sets session cookie without WebAuthn (for testing)

## Dependencies

Security-relevant dependencies:

| Package | Version | Purpose |
|---------|---------|---------|
| `wax_` | ~> 0.7 | WebAuthn/passkey implementation |
| `hammer` | ~> 7.0 | Rate limiting (ETS backend) |
| `remote_ip` | ~> 1.2 | Real IP extraction from proxy headers |
| `plug_crypto` | (via Phoenix) | Timing-safe comparison, session signing |
| `bandit` | ~> 1.5 | HTTP server |
| `web_push_encryption` | ~> 0.3 | VAPID-signed web push |
| `dotenvy` | ~> 0.8 | Environment variable loading from `.env` |

## Known Gaps

- **No Content-Security-Policy header** — inline theme script and Google Fonts CDN need nonce-based or hash-based CSP. Planned but deferred.
- **Single shared API key** — no per-user/per-scope token model. Acceptable for single-user deployment.
- **No audit logging** — auth failures and webhook rejections log to application logger but there is no structured security event store.
