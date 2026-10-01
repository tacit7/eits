# Per-session API authorization

Status: proposed
Scope: `GET /api/v1/dm`, `GET /api/v1/dm/:id`, and `GET /api/v1/dm/wait`

## Problem

The DM read endpoints currently pass through the global `RequireAuth` plug and
then use `x-eits-session` as the caller identity. `RequireAuth` proves only that
the caller has a deployment-wide API key. The header proves nothing: a caller
with that key can replace it with any session UUID or integer ID. The
controller's recipient comparison therefore prevents accidental cross-session
reads, but not reads by another authenticated session.

The Rust CLI reinforces this model. Its HTTP client sends the same
`EITS_API_KEY` bearer token for every request and adds `x-eits-session` from
ordinary session metadata. `dm inbox`, `dm read`, `dm wait`, and `dm watch`
therefore assert rather than authenticate their session identity.

This cannot be fixed by another comparison in `MessagingController`. The
server needs a credential whose successful verification establishes a session
principal.

## Security goals

1. A credential issued to session A can read or wait for DMs addressed to A,
   but cannot read or wait for DMs addressed to session B.
2. The authenticated session ID comes from credential verification, never from
   a query parameter or `x-eits-session`.
3. Session credentials are independently revocable and rotatable, are stored
   only as hashes, and are not written to prompts, logs, command arguments, or
   API responses after issuance.
4. The existing global API key is not accepted as an implicit session
   credential on the protected DM read routes after enforcement is enabled.
5. Existing browser DM behavior is unaffected; this design covers the JSON API
   used by agent/CLI processes.

## Non-goals

- This change does not define end-user or multi-tenant authorization.
- It does not immediately scope every API mutation. In particular, sender
  authorization for `POST /api/v1/dm` should be a following slice using the
  same principal, but is not required to close the DM-read weakness.
- It does not make `x-eits-session` secret. That header may remain as a
  rate-limit hint during migration, but it must not grant access.

## Proposed model

### Opaque session credentials

Add a `session_api_credentials` table and an associated context module. Use a
separate table instead of a token column on `sessions` so credentials can be
rotated, revoked, and audited without rewriting session records.

| Column | Type | Notes |
| --- | --- | --- |
| `id` | UUID | Primary key |
| `session_id` | bigint FK | Required; cascade on session deletion |
| `token_hash` | string | Unique HMAC-SHA256 hash; never store plaintext |
| `scopes` | string array | Initially `dm:read`; validated against a fixed allowlist |
| `expires_at` | UTC datetime | Required; bounded lifetime |
| `revoked_at` | UTC datetime | Nullable; immediate revocation without deletion |
| `last_used_at` | UTC datetime | Nullable, updated asynchronously or rate-limited |
| timestamps | UTC datetimes | Issuance/audit metadata |

Generate 32 random bytes with `:crypto.strong_rand_bytes/1`, Base64URL encode
them, and prefix the result with `eits_session_` so secret scanners and support
diagnostics can identify the credential class. Hash with an application secret
using the same HMAC pattern as `Accounts.ApiKey`; use a distinct derivation
label so equal plaintexts cannot produce interchangeable API-key and
session-credential hashes.

Return the plaintext exactly once from an issuance function such as:

```elixir
SessionCredentials.issue(session, scopes: ["dm:read"], expires_at: expires_at)
# => {:ok, %{credential: row, token: plaintext}}
```

The context, not controllers or launchers, owns generation, hashing, scope
validation, expiry, revocation, and lookup.

### Authenticated principal

Introduce a `SessionApiAuth` plug for routes that accept a session credential.
It reads a bearer token, verifies the hash, expiry and revocation state, loads
the referenced session, and assigns a value with an explicit type:

```elixir
conn.assigns.api_principal
# => %ApiPrincipal{kind: :session, session_id: 42, session_uuid: "...", scopes: MapSet.new(["dm:read"])}
```

Authentication and authorization remain separate:

- The plug returns `401` for a missing, malformed, expired, revoked, or unknown
  credential.
- A scope plug or controller boundary returns `403` when a valid credential
  lacks `dm:read`.
- Resource lookup is always constrained by the principal's database session
  ID. Request-supplied identity is never copied into the principal.

Do not extend `RequireAuth.authenticated?/2` to return a boolean for both token
classes. A boolean discards the identity needed for authorization and makes it
easy to repeat the current bug. If shared parsing is useful, evolve API auth to
return a tagged principal such as `{:ok, %ApiPrincipal{kind: :global}}` or
`{:ok, %ApiPrincipal{kind: :session, ...}}`.

### Route behavior

Put the three DM read routes through a session-authenticated pipeline, separate
from the current global `:api` pipeline. The authenticated principal is the
only source of recipient identity.

`GET /dm`

- Make the `session`/`session_id` query parameter optional.
- With no parameter, list messages for `principal.session_id`.
- During compatibility, a supplied parameter may be resolved, but it must
  equal `principal.session_id`; otherwise return `403`.

`GET /dm/:id`

- Fetch with a recipient-constrained query, for example
  `Messages.get_inbound_dm(principal.session_id, id)`, rather than fetching by
  ID and checking afterward.
- Return `404` when the row does not exist for that recipient. This avoids
  revealing whether another session owns a guessed message ID.

`GET /dm/wait`

- Subscribe only to `principal.session_id` and query only that recipient's
  backlog.
- Keep the current absolute-deadline and cursor semantics unchanged.
- A supplied `session` parameter is only a compatibility assertion and must
  match the principal before subscription.

The CLI may continue sending `x-eits-session` for rate limiting, but the plug
and controller must ignore it for authorization. If the header disagrees with
the authenticated principal, log a sanitized warning and use the principal for
the rate-limit bucket; do not fall back to the header.

## Issuance and delivery

Use `EITS_SESSION_TOKEN` for the plaintext credential. Keep it distinct from
`EITS_API_KEY` during migration so the CLI can select credentials per request
and so a global key is never mistaken for session proof.

### App-managed sessions

The server already knows the database session before it builds provider
environments in the Claude, Codex, Codex app-server, and Pi launch paths. Issue
or rotate a credential there and pass `EITS_SESSION_TOKEN` through the existing
environment-building options alongside `EITS_SESSION_UUID`. Never put it in an
initial prompt or a command-line `-c` argument; those are observable in prompt
history or process listings. Redaction and blocked-environment rules must cover
the new variable and token prefix.

### Externally managed sessions

Self-registration currently requires a global key and returns session
metadata. A session process that retains that global key can still impersonate
other sessions, even if it also receives a scoped token. Therefore the final
model must split bootstrap from runtime:

1. A trusted launcher or startup hook uses an administrator/bootstrap
   credential to register or resume a session.
2. The server issues a session credential in that authenticated exchange and
   returns its plaintext once.
3. The launcher stores it in the session-specific Codex/Claude env file with
   mode `0600`, removes the bootstrap/global key from the child environment,
   and starts or resumes the agent with only `EITS_SESSION_TOKEN`.
4. Resume rotates the credential. End/archive/revocation invalidates active
   credentials according to the lifecycle policy.

A global-key exchange performed by the agent itself is only a transitional
bridge, not the security boundary, because the agent can retain the global
key. Enforcement must not be declared complete until ordinary agent runtimes
no longer receive `EITS_API_KEY`.

For detached sessions where no trusted launcher can receive a one-time secret,
add a short-lived, single-use bootstrap grant bound to the expected session
UUID and project. Do not expose a general credential-mint endpoint to an
unscoped session caller.

## CLI changes

The Rust CLI is authoritative for the `dm` command family. Extend its config
with `session_token`, loaded from direct `EITS_SESSION_TOKEN` first and then the
existing session-specific Codex env file.

Add an HTTP-client path that intentionally chooses one credential:

- `dm inbox`, `dm read`, `dm wait`, and `dm watch` send
  `Authorization: Bearer $EITS_SESSION_TOKEN` and do not attach the global API
  key to that request.
- Other commands retain their current authentication until their own scope
  migrations are designed.
- Missing `EITS_SESSION_TOKEN` produces an actionable CLI configuration error
  once server enforcement is active.

Do not silently retry a `401` with the global key. Such a fallback would
reintroduce the vulnerability and hide incomplete rollout.

Because `dm` is Rust-owned, implementation must follow
`docs/EITS_RUST_CLI_MIGRATION.md` and update Rust config/client tests plus the
relevant golden help or compatibility tests. The legacy Bash fallback must not
become a second implementation of these commands.

## Lifecycle policy

- Default lifetime: the lesser of 24 hours or the configured maximum session
  runtime. Long-running sessions rotate before expiry.
- Resume: issue a new credential and revoke the previous active credential
  after a short overlap window only if reconnect safety requires it.
- Completed/failed: allow a small configurable grace period if stop hooks must
  read final messages; otherwise revoke immediately.
- Archived/deleted: revoke immediately.
- Rotation and revocation are server-side operations and never require the old
  plaintext token.

Status alone must not authorize a request: a valid, unexpired, unrevoked
credential remains the source of identity. Lifecycle callbacks merely change
credential validity.

## Rollout plan

1. **Credential foundation**
   - Add schema, migration, context, token redaction, principal type, and unit
     tests for issue/verify/expire/revoke/rotate.
   - No route behavior changes.
2. **Dual-run observability**
   - Issue and inject session credentials for app-managed sessions.
   - Teach the Rust CLI to send them on DM reads.
   - On the server, verify the credential and record sanitized metrics for
     missing tokens or principal/header mismatches, while the old path remains
     available behind an explicit transition flag.
3. **DM-read enforcement**
   - Move the three GET routes to `SessionApiAuth`.
   - Derive all recipient queries and subscriptions from the principal.
   - Reject global keys and header-only identity on these routes.
4. **External-launcher cutover**
   - Complete bootstrap exchange and remove `EITS_API_KEY` from agent runtime
     environments and session env files.
   - Remove the transition flag and compatibility authentication path.
5. **Follow-on scopes**
   - Bind `POST /dm` sender identity to the principal.
   - Migrate session/task/note/commit endpoints to explicit session scopes,
     leaving global keys for administrator/human automation only.

Each step should be independently deployable. Step 3 must not ship until
telemetry shows all supported launch modes possess a session credential.

## Required tests

Controller/integration tests:

- A's credential can list, read, and wait for A's DMs.
- A's credential plus B's header or query parameter cannot access B.
- A global API key plus B's asserted identity cannot access B's DM GET routes.
- Missing, random, expired, and revoked session credentials return `401`.
- A valid credential without `dm:read` returns `403`.
- `GET /dm/:id` returns `404` for a DM owned by another recipient.
- Wait subscribes to the authenticated session and ignores broadcasts carrying
  a different `to_session_id`, preserving the original absolute deadline.
- UUID and integer request aliases cannot change the authenticated principal.

CLI tests:

- DM read/wait/watch requests use the session token and never the global token.
- Other command families retain the global token during migration.
- Direct environment values override session env-file values.
- Missing session token has a clear failure and no global-token retry.
- Long-poll and ordinary request paths apply identical session auth headers.

Launcher tests:

- Every supported provider receives `EITS_SESSION_TOKEN` without the global
  key.
- Tokens are absent from argv, prompts, logs, and serialized session metadata.
- Rotation updates the session env file atomically with restrictive
  permissions and invalidates the prior credential as specified.

## Rejected alternatives

**Trust `x-eits-session` after global bearer auth.** This is the current model;
the header remains caller-controlled.

**Sign `x-eits-session` with the global key.** Every agent that knows the
global key can sign any session identity, so it provides no isolation.

**Store one token directly on `sessions`.** This makes overlap rotation,
revocation history, multiple launchers, and audit metadata awkward and invites
plaintext storage.

**Put the session UUID inside a JWT signed by the app.** This can work, but an
opaque credential is simpler here: it supports immediate revocation, does not
leak session metadata, and matches the existing hashed-secret operational
model. A JWT would still require a revocation mechanism for session shutdown.

**Accept a global key as `dm:read:any` indefinitely.** Any compromised agent
that still receives that key could continue reading every inbox. Emergency
administrator access, if required, should be a separately issued and audited
scope, not an implicit property of legacy keys.

## Implementation boundaries

This design intentionally does not change production authorization in the
same patch. Credential persistence, provider launchers, CLI configuration, and
route enforcement cross several trust boundaries; landing only the controller
comparison would create a false sense of isolation. The rollout slices above
are the minimum safe units for implementation and review.
