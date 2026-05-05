# Security

Security architecture and controls for the Eye in the Sky web application.

Last audited: 2026-05-01
Last updated: 2026-05-04 (Path traversal fixes, Claude/Codex env var blocking, dependency updates)

## Authentication

### Browser — WebAuthn / Passkeys

All browser routes require WebAuthn passkey authentication via `AuthHook` (LiveView `on_mount`).

- **Library**: `wax_` ~> 0.7
- **Registration**: Token-gated. Registration tokens are generated with `:crypto.strong_rand_bytes(32)`, Base64URL-encoded, with a 15-minute TTL. Tokens are consumed (deleted) after use — single-use only. The raw token is returned to the caller; only an HMAC-SHA256 hash (keyed on `secret_key_base`) is stored in the DB. Comparison hashes the presented token before lookup — plaintext is never persisted.
- **Login**: Challenge-response with passkey. Challenges are serialized to JSON in the session cookie (no Erlang `binary_to_term`).
- **Session rotation**: `configure_session(renew: true)` is called after both `login_complete` and `register_complete` to prevent session fixation.
- **Sign count tracking**: Passkey sign counts are verified and updated on each authentication. Per FIDO2 spec §6.1, authentication is rejected if `auth_data.sign_count <= passkey.sign_count` and either counter is non-zero — this detects cloned authenticators.
- **WebAuthn origin**: Configured via `WEBAUTHN_ORIGIN` env var. Required in production (raises on startup if unset). Falls back to the hardcoded default in dev/test.
- **DISABLE_AUTH bypass**: The `DISABLE_AUTH=true` env var skips LiveView auth. Guarded at both compile time (`config_env() != :prod`) and runtime (`env != :prod`). Cannot be activated in production.

**Test coverage**: The Accounts context and WebAuthn functions are tested in `test/eye_in_the_sky/accounts_test.exs` with 38 tests covering passkey creation/update/lookup, credential building, registration token lifecycle (create/peek/consume with expiry and one-time-use guarantees), and user session creation/validation/deletion.

### API — Bearer Token

All `/api/v1/*` routes (except webhooks and public settings) require a Bearer token via the `RequireAuth` plug. The `Accounts` context (which manages API keys, users, and sessions) has comprehensive test coverage: 38 tests in `test/eye_in_the_sky/accounts_test.exs` covering all 14 public functions including user CRUD, passkey lifecycle, registration tokens, user sessions, and API key validation.

#### Token Validation

- **Token comparison**: Uses `Plug.Crypto.secure_compare/2` (constant-time) to prevent timing attacks.
- **Validation flow**: The `RequireAuth` plug calls `valid_db_token?/1` to:
  1. Check the `EITS_API_KEY` env var first (backward compatibility with existing deployments)
  2. Hash the presented Bearer token using HMAC-SHA256
  3. Query the `api_keys` table for a row with matching `key_hash`
  4. Reject expired keys (where `valid_until` is in the past)
  5. Return `true` if any active key matches; otherwise `false`
- **Production validation**: If no active keys exist and `EITS_API_KEY` is unset, all requests are rejected with `401 Unauthorized`.
- **Development validation**: Dev/test environments allow passthrough for convenience when no keys are configured.

**Test coverage**: The `RequireAuth` plug has 18 tests covering missing headers, malformed headers (Basic/empty/no-token), unknown tokens, valid/expired DB API keys, env-var key matching, and 401 response shape. Located in `test/eye_in_the_sky_web/plugs/require_auth_test.exs`.

#### Key Storage and Rotation

Keys are stored as HMAC-SHA256 hashes in the `api_keys` table with the following schema:

| Column | Type | Purpose |
|--------|------|---------|
| `id` | binary UUID | Primary key |
| `key_hash` | string | HMAC-SHA256 hash of the generated key (never store plaintext) |
| `label` | string (optional) | Human-readable name for audit trails (e.g., "ci-bot", "production-agent") |
| `valid_until` | naive_datetime (optional) | Expiry timestamp; `null` means never expires |
| `inserted_at` | naive_datetime | Creation timestamp |
| `updated_at` | naive_datetime | Last update timestamp |

**Key generation flow:**
1. `mix eits.gen.api_key` generates a cryptographically random 32-byte key via `:crypto.strong_rand_bytes(32)`
2. The key is Base64URL-encoded for display
3. The plaintext key is hashed using HMAC-SHA256 via `hash_token/1` (keyed on `secret_key_base`)
4. Only the hash is inserted into the `api_keys` table; plaintext is never stored
5. The generated key is displayed once to the user (cannot be recovered later)

**Rotation and revocation:**
- Multiple active keys can coexist simultaneously — no downtime needed for rotation
- Each key has an optional `valid_until` field for time-bound key rotation
- To revoke a key: delete its `api_keys` row (immediate effect, no redeploy)
- To rotate a key: generate a new key, update consumer configs, then delete the old row
- Expired keys are silently rejected; deletion is clean and immediate

#### Mix Task Integration

The `eits.gen.api_key` mix task provides the command-line interface for key generation:

```bash
mix eits.gen.api_key                    # Generate and insert a new key, print once
mix eits.gen.api_key --label "ci-bot"   # Named key for audit tracking
```

The task outputs the Base64URL-encoded key once; this is the only time the plaintext key is visible. Store this key in your consumer's configuration (e.g., environment variables, secrets manager).

### Session Auth — Cookie-Based

The `SessionAuth` plug authenticates requests via signed session cookies. Used for browser-based access to admin dashboards.

- **Routes**: `/oban` (Oban job dashboard) and `/dev/dashboard` (LiveDashboard)
- **Mechanism**: Requires an active session cookie (set by WebAuthn login)
- **Difference from RequireAuth**: SessionAuth works with cookies (for browsers), while RequireAuth works with Bearer tokens (for API/CLI)
- **Pipeline**: `:browser` pipeline with `SessionAuth` plug

### Server-Side Session Tracking

Browser sessions are tracked in the `user_sessions` table in addition to the signed cookie. The `ValidateSession` plug runs on every browser request and rejects sessions that are missing from the DB or past their `expires_at`.

#### Session Table Schema

The `user_sessions` table holds server-side session records with the following columns:

| Column | Type | Purpose |
|--------|------|---------|
| `id` | binary UUID | Primary key |
| `user_id` | string | Reference to the authenticated user |
| `session_token` | string | Unique, cryptographically random session identifier |
| `expires_at` | naive_datetime | Session expiry timestamp (7 days from login) |
| `inserted_at` | naive_datetime | Session creation timestamp |
| `updated_at` | naive_datetime | Last update timestamp |

**Unique constraint**: `session_token` has a unique index to prevent duplicate active sessions.

#### Session Lifecycle

1. **Creation**: On successful WebAuthn login, a new `user_sessions` row is created with:
   - A random `session_token` via `:crypto.strong_rand_bytes(16)` (128 bits)
   - `expires_at` set to 7 days in the future
   - The token is stored in the Phoenix session cookie (signed, not encrypted)

2. **Validation**: The `ValidateSession` plug in the `:browser` pipeline runs on every request and:
   - Extracts the session token from the signed cookie
   - Queries the `user_sessions` table for a matching `session_token`
   - Checks if the row exists and if `expires_at` is in the future
   - Rejects the request (redirects to `/login`) if the row is missing or expired

3. **Logout**: The logout action deletes the `user_sessions` row:
   - The session is immediately invalidated server-side
   - The cookie is cleared on the client
   - No TTL wait; logout takes effect instantly

#### TTL and Expiry Enforcement

- **TTL**: 7 days from login. Sessions do not auto-renew; users must re-authenticate after 7 days.
- **Enforcement**: The `ValidateSession` plug checks both conditions on every request:
  - Row exists in the `user_sessions` table
  - `expires_at` is greater than `DateTime.utc_now()`
- **Early termination**: Admins can revoke sessions by deleting the `user_sessions` row; this invalidates the session immediately even if the cookie is still valid.

#### Cookie Handling

The session token is stored in a signed Phoenix session cookie configured with:

| Option | Value | Purpose |
|--------|-------|---------|
| `store` | `:cookie` | Signed cookie (tamper-proof via HMAC) |
| `signing_salt` | Configured in endpoint | Salt for HMAC key derivation |
| `same_site` | `"Lax"` | CSRF protection |
| `http_only` | `true` | Prevents JavaScript access (XSS protection) |
| `secure` | `true` in prod, `false` in dev | HTTPS-only in production |
| `max_age` | Not set (browser session cookie) | Browser deletes on close; TTL is enforced server-side via `expires_at` |

The browser deletes the session cookie on close (no persistent storage), and the server enforces the 7-day TTL via the `expires_at` column.

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
- **Default trusted ranges**: Loopback (127.0.0.1/8) and RFC 1918 private ranges (10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16).
- **Tailscale support**: Includes explicit trust for Tailscale CGNAT range `100.64.0.0/10` to properly rewrite `X-Forwarded-For` headers from Tailscale Funnel and other Tailscale reverse proxies.
- **Configuration**: Configured via `RemoteIp` plug with `proxies` option in `endpoint.ex`.

### Database TLS Verification

PostgreSQL connections use TLS with certificate verification in production to prevent MITM attacks.

**Configuration** (in `config/runtime.exs`):
- **Production**: Defaults to `verify_peer` with OTP system CA bundle and hostname verification
- **Development/Self-hosted**: Can override via `DATABASE_SSL_VERIFY=none` environment variable to disable verification if proper CAs are not available

**Implementation**:
```elixir
ssl_opts = case System.get_env("DATABASE_SSL_VERIFY") do
  "none" -> [verify: :verify_none]
  _ -> [verify: :verify_peer, cacerts: :public_key.cacerts_get(), customize_hostname_check: [...]]
end
```

**Verification details**:
- Uses OTP's `:public_key.cacerts_get()` to load system CA certificates
- Performs hostname verification via `:public_key.pkix_verify_hostname_match_fun(:https)`
- Rejects connections with invalid or self-signed certificates (unless explicitly disabled)

## Rate Limiting

Hammer v7 with ETS backend, applied to the `:webauthn` and `:api` pipelines.

| Endpoint | Limit | Window | Purpose |
|----------|-------|--------|---------|
| `POST /auth/login/challenge` | 10 | 1 minute | Username enumeration prevention |
| `POST /auth/login/complete` | 5 | 5 minutes | Brute force prevention |
| `POST /auth/register/challenge` | 5 | 1 hour | Registration abuse prevention |
| `POST /auth/register/complete` | 5 | 1 hour | Registration abuse prevention |
| All `/api/v1/*` routes | 60 | 1 minute | API bearer token brute force prevention |

- Keyed by remote IP (real IP via `RemoteIp` plug).
- Returns `429 Too Many Requests` with JSON error body when exceeded.
- Supervised via `EyeInTheSkyWeb.RateLimiter` in the application supervision tree.
- The `RateLimit` plug accepts configurable limits via opts; the `:api` pipeline uses a default of 60 req/min.

## Authorization

### Route-Level Access Control

| Route Pattern | Auth Method | Pipeline |
|---------------|-------------|----------|
| `/auth/login`, `/auth/register` | Public | `:browser` |
| `/auth/logout` | Session (clears it) | `:browser` |
| `/auth/*/challenge`, `/auth/*/complete` | Rate-limited, challenge-bound | `:webauthn` |
| `/` and all LiveView routes | Session + AuthHook | `:browser` + `AuthHook` |
| `/oban` dashboard | Session + SessionAuth | `:browser` + `SessionAuth` |
| `/dev/dashboard` | Session + SessionAuth | `:browser` + `SessionAuth` |
| `/api/v1/*` | Bearer token | `:api` (includes `RequireAuth`) |
| `/api/v1/webhooks/gitea` | HMAC signature | `:accepts_json` (no Bearer) |
| `/api/v1/settings/eits_workflow_enabled` | Public (read-only) | `:accepts_json` |
| Static assets | Public | `Plug.Static` (allowlisted paths only) |

### Static File Serving

`Plug.Static` is configured with an `only` allowlist: `~w(assets fonts images favicon.ico robots.txt sw.js manifest.json)`. The `uploads/` directory is deliberately excluded — uploaded files are stored in `priv/static/uploads/` but are not served via HTTP.

## Input Validation

### Path Traversal Prevention

File access handlers use `FileHelpers.path_within?/2` (realpath-based comparison) instead of string prefix checks:

**Project config viewer** (`project_live/config.ex`):
- `view_file` and `open_file` handlers verify paths are within the `.claude` directory using `path_within?(path, claude_dir)`.
- `String.starts_with?` was replaced because it does not resolve symlinks or `..` segments, allowing traversal attacks via crafted paths like `/home/user/.claude/../.ssh/id_rsa`.
- `path_within?` uses `File.cwd!()` and `Path.expand()` to canonicalize paths before comparison, making the check traversal-safe.

**Settings editor** (`overview_live/settings.ex`):
- `open_in_editor` handler is scoped to an explicit allowlist (`@allowed_editor_roots`) containing only `~/.claude`.
- Previously, `File.exists?` was the only check, allowing any path to be opened via a crafted WebSocket event.
- Now uses `path_within?` against the allowlist, rejecting all paths outside `~/.claude`.

### Database

- All database access uses Ecto with parameterized queries — no raw SQL.
- Input validation via Ecto changesets on all mutations.
- PostgreSQL database (`eits_dev`) with standard connection pooling.
- **Foreign key constraint handling**: Foreign key constraints are declared in changesets via `foreign_key_constraint/2` (e.g., `messages_session_id_fkey`). This ensures constraint violations return `{:error, changeset}` instead of raising `Ecto.ConstraintError` and crashing the GenServer. Errors are logged and handled gracefully at the call site.

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

## Database Security

### TOCTOU (Time-Of-Check-Time-Of-Use) Race Prevention

The application prevents SELECT-then-write races by collapsing multi-query operations into single atomic updates. This eliminates windows where concurrent requests can observe stale state.

**Toggle operations (2-query → 1-query)**:
- `Notes.toggle_starred/1`: Replaced `get_note` + `update_note` with single `UPDATE ... SET starred = NOT starred RETURNING *`
- `ChecklistItems.toggle_checklist_item/1`: Replaced `Repo.get` + `Repo.update` with single `UPDATE ... SET completed = NOT completed RETURNING *`
- `ChecklistItems.delete_checklist_item/1`: Replaced `Repo.get` + `Repo.delete` with single `DELETE ... RETURNING id`

These operations no longer have a race window: the server-side toggle is atomic.

**Insert-first patterns**:
- `MessageReactions.toggle_reaction/3`: Attempts `INSERT with on_conflict: :nothing` on the unique index `(message_id, session_id, emoji)`. If the row already exists (conflict fires, id is nil), the operation deletes instead. This prevents duplicate reaction rows under concurrent taps on the same emoji.

**User registration race (SELECT + INSERT → single INSERT with on_conflict)**:
- `Accounts.get_or_create_user/1`: Collapsed the `get_user_by_username` + `INSERT` race using `Repo.insert(on_conflict: :nothing, conflict_target: :username, returning: true)`. Concurrent logins for the same new user no longer produce `{:error, changeset}` from the unique constraint on username — both callers receive `{:ok, user}`. When a conflict fires, the query returns a zeroed `User` struct with `id: nil`; a fallback `get_user_by_username` retrieves the existing row. This eliminates the race window entirely.

**Upsert races (SELECT + write → single upsert)**:
- `PushSubscriptions.upsert/3`: Replaced `Repo.get_by` + conditional insert/update with single atomic `Repo.insert(on_conflict: [set: [auth, p256dh]], conflict_target: :endpoint)`. One round-trip regardless of new/existing row.
- `TaskTags.get_or_create_tag/1`: Replaced `Repo.get_by` + conditional insert with atomic `Repo.insert_all(..., on_conflict: {:replace, [:name]}, conflict_target: :name)`. ON CONFLICT DO UPDATE forces the row into RETURNING even when it already exists, so no second SELECT is needed.
- `Contexts.upsert_session_context/1`: Replaced `QueryHelpers.upsert` (which used `get_session_context` + insert/update) with atomic `Repo.insert(on_conflict: {:replace, [...]}, conflict_target: [:session_id])`.
- `Contexts.upsert_agent_context/1`: Replaced `QueryHelpers.upsert` with atomic `Repo.insert(on_conflict: {:replace, [:]}, conflict_target: [:agent_id, :project_id])`.

All upserts use the corresponding unique index as the `conflict_target`, ensuring atomicity and preventing duplicate rows under concurrent writes.

### Unbounded Query Mitigation

List operations that previously used unbounded `Repo.all()` now have explicit default limits to prevent full table scans on large datasets:

**Sessions**:
- `Sessions.list_active_sessions/0`: Default limit 500
- `Sessions.list_sessions_with_agent/1`: Default limit 500
- `Sessions.list_active_sessions_for_project/1`: Default limit 500

**Prompts**:
- `Prompts.list_prompts/0`: Default limit 500
- `Prompts.list_global_prompts/0`: Default limit 500
- `Prompts.list_project_prompts/1`: Default limit 500

**Tasks**:
- `TaskTags.list_tags/1`: Default limit 500 (with optional `:search` filter and `:limit` override)

**Jobs**:
- `ScheduledJobs.list_jobs/0`: Default limit 500
- `ScheduledJobs.list_spawn_agent_jobs_by_prompt_ids/1`: Default limit 500
- `ScheduledJobs.list_filesystem_agent_jobs/0`: Default limit 500
- `ScheduledJobs.list_orphaned_agent_jobs/0`: Default limit 200 (called in LiveView mount)

**Messages**:
- `Messages.Listings.list_pending_messages/0`: Default limit 200

**Channels**:
- `Channels.list_channels_for_project/1`: Default limit 500

**Canvases**:
- `Canvases.list_terminals/0`: Default limit 200 (with optional `:limit` override)

**IAM**:
- `IAM.list_policies/0`: Default limit 500
- `IAM.list_policies/1`: Default limit 500 (with opt-in `:limit` override)
- `IAM.PolicyCache.load_from_db/0`: Hard limit 5000 with `Logger.warning` if limit is reached, preventing unbounded cache scans on cache miss

All limit parameters accept `:limit` to override the default, but the application enforces ceilings to prevent accidental queries on millions of rows.

### Index Maintenance and Cleanup

**Invalid index rebuild** (Round 8):
- `notes_parent_id_bigint_project_idx` was marked INVALID (`indisvalid=false, indisready=false`), likely from a failed DDL. Zombie indexes impose write overhead (updates rewrite invalid index entries) with zero read benefit. Migration rebuilds the index to restore it to VALID state.

**Parent foreign key indexes** (Round 4):
- Added partial indexes on `sessions.parent_session_id` (WHERE NOT NULL) and `agents.parent_agent_id` (WHERE NOT NULL) for fork/checkpoint tree traversal. The partial index skips the vast majority of non-fork rows, improving query performance on tree operations.

**Job run indexes** (Round 7):
- Added compound index on `job_runs (job_id, started_at DESC)` for DISTINCT ON queries in `last_run_status_map` and `last_run_per_job` (prevents seq scan on 5000+ rows)
- Added partial index on `job_runs WHERE status = 'running'` for `list_running_job_ids` queries

**Zombie sweep optimization** (Round 5):
- Added two partial indexes on `sessions` filtered to `status = 'working'`:
  - Optimizes the OR condition on `last_activity_at`/`started_at` in zombie sweep logic
  - Converts full table scan to index scan on active sessions only

**Stale column removal**:
- Dropped `agents.session_id` column (271 stale rows, no foreign key, no index, never cast via changeset, zero code readers). Column cleanup improves schema hygiene and reduces write overhead.

**Constraint name fixes** (Round 7):
- Added missing unique index `idx_subagent_prompts_slug_project (slug, project_id) WHERE project_id IS NOT NULL`
- Renamed `subagent_prompts_slug_index` → `idx_subagent_prompts_slug_global` to match changeset `unique_constraint/2` declarations
- These fixes ensure constraint error translation works correctly in the Prompt changeset

### Performance Indexing (Round 9)

Three new CONCURRENTLY-built compound indexes optimize common query patterns on high-volume tables:

**`notifications(inserted_at, id)`**:
- **Problem**: `list_notifications/0` queries scan 12k+ notification rows, then perform an `Incremental Sort` (expensive in-memory sort of secondary key) because the compound index `(inserted_at, id)` was missing.
- **Solution**: Add compound index on `(inserted_at, id)` to provide both insertion order and stable tiebreaker in one index pass.
- **Benefit**: Eliminates sort overhead; queries now scan pre-sorted index entries.

**`messages(session_id, inserted_at)`**:
- **Problem**: Session-scoped time queries (`list_messages_for_session(session_id)` with recent-first ordering) were using the wrong index. The planner picked the `(channel_id, inserted_at)` index, forcing a full-time-window scan (275k+ rows) followed by filtering on `session_id`, resulting in poor selectivity.
- **Solution**: Add compound index on `(session_id, inserted_at)` to match the actual query predicate order.
- **Benefit**: Index is selective by session first, then scanned in time order — no full table time window scan.

**`commit_tasks(task_id)`**:
- **Problem**: When tasks are deleted (via `ON DELETE CASCADE`), Postgres must find all referencing rows in `commit_tasks`. The table has a composite unique index on `(commit_id, task_id)`, but a plain `task_id` lookup cannot use it efficiently.
- **Solution**: Add single-column index on `task_id` for fast reverse FK scans.
- **Benefit**: `ON DELETE CASCADE` operations complete faster; FK reverse-scans no longer require index scan of composite index with leading column mismatch.

## Secure Headers

Phoenix's `put_secure_browser_headers` plug adds:

| Header | Value |
|--------|-------|
| `x-frame-options` | `SAMEORIGIN` |
| `x-content-type-options` | `nosniff` |
| `x-xss-protection` | `1; mode=block` |

### Content-Security-Policy (CSP)

CSP is enforced via per-request nonce to allow inline scripts while maintaining XSS protection.

**Implementation**:
- `CspNonce` plug generates a unique base64-encoded nonce (16 random bytes) per request
- Nonce is stored in `conn.assigns.csp_nonce` and injected into the CSP header
- The nonce attribute is added to inline `<script>` tags in `root.html.heex` (theme initialization script)
- Production CSP uses `script-src 'self' 'nonce-<value>'` (no `unsafe-inline`)
- Development CSP uses `script-src 'self' 'unsafe-inline'` for convenience

**CSP Header (Production)**:
```
default-src 'self'; script-src 'self' 'nonce-<unique>'; style-src 'self' 'unsafe-inline' https://fonts.googleapis.com; font-src 'self' data: https://fonts.gstatic.com; ...
```

**Benefits**: Inline scripts execute only if they carry the correct nonce. Any XSS-injected script without the nonce is blocked, protecting against inline script injection attacks.

## Secrets Management

### Environment Variables

All secrets are loaded from environment variables via `.env` file (loaded by `dotenvy` at startup):

| Secret | Env Var | Required In |
|--------|---------|-------------|
| API bearer token (legacy) | `EITS_API_KEY` | Optional (superseded by `api_keys` table) |
| VAPID public key | `VAPID_PUBLIC_KEY` | All (for web push) |
| VAPID private key | `VAPID_PRIVATE_KEY` | Prod (raises without it) |
| Gitea webhook secret | `GITEA_WEBHOOK_SECRET` | All (rejects unsigned without it) |
| Database URL | `DATABASE_URL` | Prod |
| Secret key base | `SECRET_KEY_BASE` | Prod |
| WebAuthn primary origin | `WEBAUTHN_ORIGIN` | Prod (raises without it) |
| WebAuthn RP ID | `WEBAUTHN_RP_ID` | Prod (raises without it) |
| WebAuthn extra origins | `WEBAUTHN_EXTRA_ORIGINS` | Optional (for ngrok tunnels) |

No secrets are committed to source code. The `.env` file is in `.gitignore`. `.env.example` contains placeholders and generation instructions.

### Hook Script Environment Variables

The `eits-session-startup.sh` hook propagates API credentials to subsequent hooks via `CLAUDE_ENV_FILE`:

- **EITS_API_KEY**: If present, written to the env file using `printf %q` for safe shell escaping. This prevents metacharacters and special characters from corrupting the environment file.
- **Purpose**: Subsequent hooks (`eits-post-compact.sh`, etc.) inherit authenticated credentials for API calls.
- **Safe escaping**: `printf %q` quotes the value correctly, preventing injection or malformed syntax in the env file.

Example from `eits-session-startup.sh`:
```bash
[ -n "${EITS_API_KEY:-}" ] && printf 'export EITS_API_KEY=%q\n' "$EITS_API_KEY" >> "$CLAUDE_ENV_FILE"
```

### Key Rotation

**VAPID keys**:
```bash
mix run -e '{pub, priv} = :crypto.generate_key(:ecdh, :prime256v1); IO.puts("VAPID_PUBLIC_KEY=#{Base.url_encode64(pub, padding: false)}"); IO.puts("VAPID_PRIVATE_KEY=#{Base.url_encode64(priv, padding: false)}")'
```
Update `.env`, restart server, delete stale `push_subscriptions` rows. Clients must re-subscribe.

**API keys**:
```bash
mix eits.gen.api_key                    # generate and insert a new key
mix eits.gen.api_key --label "ci-bot"   # named key for tracking
```
Keys are stored as HMAC-SHA256 hashes in the `api_keys` table. To revoke a key, delete its row. To rotate, generate a new key, update consumer configs, then delete the old row. Multiple keys can be active simultaneously — no downtime needed for rotation.

## Process Execution

### Claude CLI Spawning

The app spawns Claude CLI processes as Erlang Ports via `EyeInTheSky.Claude.CLI`:

- Process arguments are built from a validated keyword list with known flags only.
- Sensitive flags (`-p`, `--system-prompt`, `--append-system-prompt`) are redacted in logs via `safe_log_args/1`.
- Port output buffer is capped at 4MB to prevent memory exhaustion.
- Idle timeout (configurable, default 5 minutes) kills stalled processes.
- Process cancellation sends `SIGTERM` to the process group, with `SIGKILL` fallback.

**Environment variable filtering** (`EyeInTheSky.Claude.CLI.Env`):
- Sensitive environment variables are stripped from spawned Claude processes to prevent credential leakage.
- **Blocked variables**: `CLAUDECODE`, `CLAUDE_CODE_ENTRYPOINT`, `BINDIR`, `ROOTDIR`, `EMU`, `SECRET_KEY_BASE`, `DATABASE_URL`
- **Blocked prefixes**: `RELEASE_*` (for release-bundled ERTS)
- **Conditional blocking**: `ANTHROPIC_API_KEY` is blocked by default (preserves Max plan OAuth authentication). When the `use_anthropic_api_key` setting is enabled, the key is passed through for token-based authentication (configurable per deployment via Settings UI).
- **PATH sanitization**: Entries containing `_build/prod/rel` or `/erts-` are stripped (release artifacts that can shadow production binaries).
- **Injected vars**: `EITS_SESSION_ID`, `EITS_AGENT_ID`, `EITS_CHANNEL_ID`, `EITS_WORKFLOW`, `CLAUDE_CODE_EFFORT_LEVEL` (when provided in opts).

**Rationale**: Without filtering, spawned Claude processes would inherit the entire server environment, including:
- `SECRET_KEY_BASE` and `DATABASE_URL`: Production database credentials would leak to arbitrary subprocess commands.
- `ANTHROPIC_API_KEY`: A stale or invalid API key in the server env would silently override Max plan OAuth, causing "Credit balance is too low" billing errors instead of prompting real auth.
- Poisoned PATH entries: Release-bundled ERTS could shadow system binaries and execute during spawned process startup.

### Codex CLI Spawning

The app spawns Codex CLI processes (Rust binary) as Erlang Ports via `EyeInTheSky.Codex.CLI`:

- Binary is located via standard search paths (`/usr/local/bin/codex`, `/opt/homebrew/bin/codex`, etc.).
- Subcommand: `codex exec` with `--json` flag for JSONL output streaming.
- Output is parsed into structured events (thread started, turn completed, etc.) and written to the `iam_decisions` table.

**Environment variable filtering** (`EyeInTheSky.Codex.CLI.build_env/1`):
- Mirrors the Claude CLI's denylist pattern to prevent credential leakage.
- **Blocked variables**: `SECRET_KEY_BASE`, `DATABASE_URL`, `ANTHROPIC_API_KEY`, `BINDIR`, `ROOTDIR`, `EMU`, `CLAUDECODE`, `CLAUDE_CODE_ENTRYPOINT`
- **Blocked prefixes**: `RELEASE_*`
- **Exception**: `OPENAI_API_KEY` is intentionally NOT blocked — Codex requires it for operation.
- All other environment variables are passed through to the spawned process.

**Rationale**: Same as Claude CLI — prevents database credentials and internal binaries from leaking to spawned subprocesses.

### Webhook Agent Spawning

The Gitea webhook controller spawns review agents with project path from config (not hardcoded). The `project_path` is configurable via `Application.get_env(:eye_in_the_sky_web, :project_path)`.

### Hook Script Environment Propagation

Hook scripts write environment variables to `CLAUDE_ENV_FILE` for downstream hooks to inherit. Special care is taken with sensitive values:

- **API key escaping**: `eits-session-startup.sh` uses `printf %q` (POSIX shell quoting) when writing `EITS_API_KEY` to the env file. This prevents metacharacters, spaces, and special characters from corrupting the shell syntax or being interpreted as command separators.
- **Error surfacing**: `eits-post-compact.sh` surfaces context-save failures to stderr instead of silently swallowing them. If API key is missing or invalid, the operator sees the error message: `"post-compact: failed to save context for session <uuid> (check EITS_API_KEY is set)"`
- **Fail-fast on permanent errors**: `eits teams status --wait` (used for polling team member status) fails immediately on HTTP 404/401/403 instead of retrying forever. Transient errors (429, 5xx) still retry with 5-second backoff. This prevents blocking waits when a team no longer exists or credentials are invalid.

## User Privacy Settings

### Agent Completion Notifications

Agent completion notifications are **opt-in** (default OFF) to respect user preferences and privacy:

- **Setting**: `agent_notifications` in the Settings UI (Settings > General > Notifications)
- **Default**: `"false"` — no notifications sent until explicitly enabled
- **Implementation**: `notify_agent_complete/2` in `AgentWorkerEvents` checks `EyeInTheSky.Settings.get_boolean("agent_notifications")` before spawning the notification task
- **Scope**: User-level preference stored in the settings table; applies to all agent completions for that user

## Dev-Only Features

These features are gated behind `Application.compile_env(:eye_in_the_sky_web, :dev_routes)` — they do not exist in production builds:

- `/dev/dashboard` — Phoenix LiveDashboard (telemetry metrics), protected by SessionAuth
- `/dev/mailbox` — Swoosh email preview

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
| `vite` | 6.4.2 | Asset bundler and dev server |
| `postcss` | 8.5.13 | CSS processor |

## Identity and Access Management (IAM)

IAM provides fine-grained policy control over Claude Code and API operations, evaluated via hook-based decision points.

### Architecture

**Policy model**: Rules with conditions, effects (allow/deny/instruct), and optional builtin matchers. Policies are matched against normalized hook payloads (tool name, action, resource path, environment context) and evaluated against optional conditions. System policies are immutable; custom policies can be created, edited, or deleted via the LiveView CRUD interface.

**Hook evaluation**: Policies are evaluated at four points in the Claude workflow:
- `UserPromptSubmit`: Evaluate before the user prompt is sent to Claude (can suppress/replace prompt)
- `PreToolUse`: Evaluate before a tool is executed (can deny, allow, or instruct)
- `PostToolUse`: Evaluate after a tool use completes (can suppress/modify output)
- `Stop`: Evaluate when Claude requests to stop execution (can deny or instruct)

**Evaluation algorithm**:
1. Coarse-filter: `agent_type` and `action` must match (or be `"*"`), and hook `event` must match (or policy has no `event` constraint)
2. For each survivor, check project scope, resource glob pattern, and conditions
3. Partition matches into denies, allows, and instructs
4. Resolve permission: deny > allow > fallback (default allow). Instructions always attach regardless of permission
5. Return decision with permission, winning policy, instructions, and reason

**Condition evaluation**: Pure, declarative JSON-based predicates via `ConditionEval` (e.g., `time_between`, `env_equals`, `session_state_equals`). Conditions fail-closed with telemetry on malformed predicates.

**Builtin matchers**: For policy detection that needs Elixir code (command parsing, path resolution, git-state inspection, API key redaction), policies can specify a `builtin_matcher` key that dispatches to a dedicated module in `EyeInTheSky.IAM.Builtin`. Matchers are registered in `BuiltinMatcher.Registry` — unknown keys are rejected at the changeset layer. Evaluation is wrapped in error handling (fail-closed: does not match on error) and telemetry.

**Sanitize matchers (`sanitize_api_keys`, `sanitize_prompt_api_keys`)**: The redaction accumulator uses prepend + `Enum.reverse/1` instead of list append (`acc ++ [item]`). This keeps each reduction step O(1) rather than O(n) — the reversal happens once after the fold, not on every match.

**Seeded system policies** (12 builtin matchers, 13 system policies):

| Key | Builtin Matcher | Action | Event | Effect | Purpose |
|-----|-----------------|--------|-------|--------|---------|
| `block_sudo` | `block_sudo` | Bash | PreToolUse | deny | Blocks `sudo`, `doas`, `pkexec`, `runas` privilege escalation |
| `block_rm_rf` | `block_rm_rf` | Bash | PreToolUse | deny | Blocks `rm -rf` against system/home paths |
| `protect_env_vars` | `protect_env_vars` | Bash | PreToolUse | deny | Blocks dumping/reading sensitive env vars (API keys, tokens) |
| `block_env_files` | `block_env_files` | * | PreToolUse | deny | Blocks direct access to `.env` files |
| `block_read_outside_cwd` | `block_read_outside_cwd` | * | PreToolUse | deny | Blocks reads outside the project working directory |
| `block_push_master` | `block_push_master` | Bash | PreToolUse | deny | Blocks `git push` to protected branches (main/master) |
| `block_curl_pipe_sh` | `block_curl_pipe_sh` | Bash | PreToolUse | deny | Blocks `curl\|sh`, `bash <(curl)`, `eval "$(curl)"` remote execution patterns |
| `block_work_on_main` | `block_work_on_main` | Bash | PreToolUse | deny | Blocks mutating git operations on protected branches |
| `warn_destructive_sql` | `warn_destructive_sql` | Bash | PreToolUse | instruct | Warns on `DROP/TRUNCATE/DELETE` without `WHERE` clause |
| `builtin.sanitize_api_keys` | `sanitize_api_keys` | * | PostToolUse | instruct | Redacts API keys from tool output (instructs to redaction) |
| `builtin.sanitize_prompt_api_keys` | `sanitize_prompt_api_keys` | * | UserPromptSubmit | instruct | Redacts API keys from user prompt (Anthropic, OpenAI, GitHub, AWS, generic) |
| `builtin.workflow_business_hours_only` | `workflow_business_hours_only` | * | PreToolUse | deny | Denies all PreToolUse when outside business hours (09:00–17:00 UTC via `time_between` condition) |
| `builtin.workflow_stop_gate` | (none) | * | Stop | instruct | Example policy for Stop event (disabled by default, no builtin matcher) |

### Hook Response Shapes

IAM converts policy decisions into JSON responses per the Claude Code hook protocol. Response shape depends on permission, instructions, and hook event type.

**PreToolUse — deny**:
```json
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "<policy message>"
  }
}
```

**PreToolUse — allow (no instructions)**:
```json
{
  "continue": true,
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "allow"
  }
}
```

**PreToolUse — allow (with instructions)**:
```json
{
  "continue": true,
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "allow",
    "additionalContext": "<rendered markdown of policy instructions>"
  }
}
```

**UserPromptSubmit — allow (with instructions/redaction)**:
```json
{
  "suppressUserPrompt": true,
  "hookSpecificOutput": {
    "hookEventName": "UserPromptSubmit",
    "userPrompt": "<redacted/sanitized prompt>"
  }
}
```

**PostToolUse/Stop — deny**:
```json
{
  "continue": false,
  "stopReason": "<policy message>"
}
```

**PostToolUse/Stop — allow (with instructions)**:
```json
{
  "continue": true,
  "suppressOutput": true,
  "hookSpecificOutput": {
    "hookEventName": "PostToolUse",
    "additionalContext": "<rendered markdown of policy instructions>"
  }
}
```

### Hook Integration

**Claude Code PreToolUse hook**: The app provides a shell script (`priv/scripts/iam-pretooluse.sh`) that Claude Code operators can wire into `settings.json` to enable hook-based policy evaluation. The script POSTs to `/api/v1/iam/decide` (unauthenticated, designed for CLI scripts with no session context) with the hook payload and receives a JSON decision. On network errors, the script fails open (never blocks tool calls).

**Configuration**: See `docs/IAM_HOOK_INSTALL.md` for wiring the hook script into Claude Code settings.json.

### Implementation Details

**Normalizer** (`lib/eye_in_the_sky/iam/normalizer.ex`): Converts Claude Code hook payloads into a normalized `Context` struct. Tool-specific extractors parse Bash scripts, file paths, API calls, etc. Unknown tools fall through to `:unknown`.

**Evaluator** (`lib/eye_in_the_sky/iam/evaluator.ex`): Core decision engine. Fetches enabled policies from cache, filters by agent_type/action/event, evaluates conditions and builtin matchers, resolves permission via deny > allow > fallback, and returns a `Decision` with all instructions attached (sorted by priority).

**PolicyCache** (`lib/eye_in_the_sky/iam/policy_cache.ex`): ETS-backed GenServer singleton. Caches all enabled policies in-memory with cache-invalidation hook triggered by policy mutations. Hit/miss telemetry for observability.

**Policy schema** (`lib/eye_in_the_sky/iam/policy.ex`): Ecto schema with `create_changeset` and `update_changeset` for custom policies, plus `enforce_locked_fields/1` guard that prevents editing of locked fields on system policies. Validates `builtin_matcher` against the Registry at write time.

**Audit trail**: Every decision is asynchronously written to `iam_decisions` table via `IAM.record_audit/4`. The audit write is spawned as a task to avoid blocking the HTTP response:

- **Function**: `IAM.record_audit(ctx, decision, raw_payload, duration_us)` in `lib/eye_in_the_sky/iam.ex`
- **Async execution**: Spawned via `Task.Supervisor.start_child(EyeInTheSky.TaskSupervisor, fn -> ... end)` to execute in background
- **Data captured**:
  - `decision_id`: UUID of the decision
  - `session_uuid`: Requester's session (binary, may be nil)
  - `event`, `agent_type`, `project_id`, `project_path`, `tool`, `resource_path`: Context snapshot
  - `permission`, `default`, `reason`: Permission decision details
  - `winning_policy_*` (id, system_key, name): Policy that decided the outcome
  - `instructions_snapshot`: Serialized policy instructions (id, system_key, name, message)
  - `evaluated_count`: Number of policies evaluated
  - `duration_us`: Evaluation latency in microseconds
  - `raw_payload`: Full hook payload for debugging
  - `inserted_at`: UTC timestamp
- **Indexing**: FK indexes on `winning_policy_id` and `project_id` enable fast audit queries by policy or project. Partial indexes exclude NULL FK values for better selectivity.

### Policy CRUD LiveView

New UI under `/iam/policies` (requires SessionAuth) for operator-facing policy management:

- **Index** (`/iam/policies`): List view with toggles for enable/disable, filters by agent_type/action/effect/enabled status, delete button (unavailable for system policies)
- **New** (`/iam/policies/new`): Create custom policy form with action, project scope, resource glob, conditions (decoded from JSON at submit time), effect, and priority. Changesets surface invalid JSON cleanly.
- **Edit** (`/iam/policies/:id`): Update form. System policies render locked fields with `disabled` input attributes; custom policies allow full editing. Server-side `enforce_locked_fields/1` guard catches any UI bypass attempts.

System policies cannot be deleted via the UI (no button rendered for rows with `system_key`). Custom policies have full CRUD.

### Message Security

DM delivery enforces an allowlist of receivable session statuses:

- **Receivable statuses**: `working` and `stopped` (sessions actively processing or between turns)
- **Non-receivable statuses**: `waiting`, `completed`, `failed`, `archived`, `compacting`, and any other status
- **Rejection**: DMs sent to non-receivable sessions are rejected with `422 Unprocessable Entity` and error message `"Target session is not active and cannot receive DMs"`
- **Purpose**: Prevents zombie agent sessions from receiving messages after their work is complete and data cleanup begins

The allowlist approach (vs. a blocklist) is more defensive: unknown future statuses are blocked by default rather than accidentally receivable.

## Architectural Linting (archdo)

The project uses [archdo](https://github.com/archdo/archdo) (pinned ref `1e651d57`) as an architectural linter to flag structural anti-patterns at the module level.

**Configuration**: `.archdo.exs` at the project root defines three layers and their allowed dependency directions:

| Layer | Pattern | May depend on |
|-------|---------|---------------|
| `interface` | `EyeInTheSkyWeb.*` | `domain`, `infrastructure` |
| `domain` | `EyeInTheSky.*` (excluding Repo/Mailer) | `infrastructure` |
| `infrastructure` | `EyeInTheSky.{Repo,Mailer}` | (none) |

**Baseline**: `.archdo_baseline.exs` records 1402 fingerprints (1963 original diagnostics) captured 2026-05-02. Baseline violations are accepted as pre-existing; only new violations added after the baseline was captured are flagged as regressions. Fingerprints are line-number independent so formatting changes do not churn them.

**Relevant rules**: Archdo rule `6.50` (quadratic list concatenation via `acc++`) was the trigger for the sanitize module fix above. New violations against the baseline fail CI.

## Known Gaps

- **No per-scope API keys** — `api_keys` table supports multiple keys but no scope/permission model. All keys have full API access. Acceptable for single-user deployment.
- **No audit logging** — auth failures and webhook rejections log to application logger but there is no structured security event store.
