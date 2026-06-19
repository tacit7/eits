# IAM Policies

An IAM policy is a declarative rule that controls whether a tool call is allowed, denied, or
allowed with advisory context. Policies match against tool calls using condition predicates and
optional builtin matcher modules.

---

## Policy Schema

```elixir
# Ecto schema: iam_policies table
field :system_key,      :string           # nil on user policies; "builtin.*" on system policies
field :name,            :string           # human-readable label
field :effect,          :string           # "allow" | "deny" | "instruct"
field :agent_type,      :string           # "*" or an agent definition slug
field :project_path,    :string           # "*" or a path glob
field :action,          :string           # "*" or a tool name: "Bash", "Edit", "Write", etc.
field :resource_glob,   :string           # glob matched against tool resource path
field :condition,       :map              # condition predicates (see below); {} = always matches
field :priority,        :integer          # higher wins; default 0
field :enabled,         :boolean          # global enabled flag; default true
field :message,         :string           # shown to Claude on deny/instruct
field :editable_fields, {:array, :string} # locked fields on system policies
field :builtin_matcher, :string           # registered key → Builtin.* module
field :event,           :string           # "PreToolUse" | "PostToolUse" | "Stop" | "UserPromptSubmit"
```

**`effect`** is the outcome (`deny`, `allow`, `instruct`). **`action`** is the tool name filter
(`"Bash"`, `"Edit"`, `"*"` for any). These are separate fields.

---

## Condition Predicates

The `condition` map can contain any of three predicates. All present predicates must match
(AND logic). An empty `{}` always matches.

| Predicate | Value format | Description |
|-----------|-------------|-------------|
| `"time_between"` | `["HH:MM", "HH:MM"]` (UTC) | Matches if current UTC time is within the window. Wraps midnight (e.g. `["22:00","06:00"]`) |
| `"env_equals"` | `%{"VAR" => "value", ...}` | All listed env vars must equal the given string at evaluation time |
| `"session_state_equals"` | `"string"` | Matches if `ctx.metadata["session_state"]` equals the value |

Example — policy active only during business hours:

```json
{
  "time_between": ["09:00", "17:00"]
}
```

Example — policy active only in production:

```json
{
  "env_equals": {"MIX_ENV": "prod"},
  "time_between": ["00:00", "23:59"]
}
```

**Evaluation errors** (malformed values, unknown predicates) are treated as non-matching and
emit a telemetry event `[:eye_in_the_sky, :iam, :condition, :error]` — they never crash the
evaluator.

---

## Effects

| Effect | Behavior |
|--------|----------|
| `"deny"` | Blocks the tool call. Returns `permissionDecision: "deny"` with the policy `message` as the reason. |
| `"allow"` | Explicitly permits the tool call. Useful for allowlisting specific resources that a deny policy would otherwise block. |
| `"instruct"` | Advisory — does not block. Injects the `message` into Claude's context window as `additionalContext` (visible in Claude as a system reminder, not a chat message). |

---

## Builtin Matchers

System policies can specify a `builtin_matcher` key that dispatches to a specialized Elixir
module. The module receives the full hook payload and returns `true`/`false`. All 36 registered
matchers are in `EyeInTheSky.IAM.BuiltinMatcher.Registry`.

**Fail-closed**: If a matcher raises, `safe_builtin_match/2` catches it, logs a telemetry event,
and returns `false` (no match). A buggy matcher can never cause a policy to fire incorrectly.

### Registered Matchers

#### Filesystem Safety
| Key | Module | Effect | Purpose |
|-----|--------|--------|---------|
| `block_sudo` | `Builtin.BlockSudo` | deny | Deny any `sudo` invocation |
| `block_rm_rf` | `Builtin.BlockRmRf` | deny | Deny `rm -rf` and similar destructive patterns |
| `block_env_files` | `Builtin.BlockEnvFiles` | deny | Deny writes to `.env*` files |
| `block_read_outside_cwd` | `Builtin.BlockReadOutsideCwd` | deny | Deny Read outside the working directory (URL paths filtered out to avoid false positives) |
| `block_secrets_write` | `Builtin.BlockSecretsWrite` | deny | Deny Write/Edit on `.pem`, `.key`, `.crt`, SSH identity files |
| `protect_env_vars` | `Builtin.ProtectEnvVars` | deny | Deny Bash commands that print or exfiltrate sensitive env vars |
| `block_curl_pipe_sh` | `Builtin.BlockCurlPipeSh` | deny | Deny `curl | bash` and `wget | sh` patterns |

#### Git & Version Control
| Key | Module | Effect | Purpose |
|-----|--------|--------|---------|
| `block_push_master` | `Builtin.BlockPushMaster` | deny | Deny `git push` to master/main |
| `block_work_on_main` | `Builtin.BlockWorkOnMain` | deny | Deny commits directly on main (worktree-aware: extracts `cd` targets to check the right branch) |
| `block_force_push` | `Builtin.BlockForcePush` | deny | Deny `git push --force` / `git push -f` |
| `warn_git_amend` | `Builtin.WarnGitAmend` | instruct | Warn on `git commit --amend` or `git rebase -i` |
| `warn_all_files_staged` | `Builtin.WarnAllFilesStaged` | instruct | Warn when `git add -A` or `git add .` stages everything |
| `warn_git_stash_drop` | `Builtin.WarnGitStashDrop` | instruct | Warn on `git stash drop` or `git stash clear` |
| `require_commit_before_stop` | `Builtin.RequireCommitBeforeStop` | instruct | On Stop event: warn if uncommitted changes exist |

#### Cloud CLI Safety
| Key | Module | Effect | Purpose |
|-----|--------|--------|---------|
| `block_aws_cli` | `Builtin.BlockAwsCli` | deny | Block destructive AWS CLI operations |
| `block_gcloud` | `Builtin.BlockGcloud` | deny | Block destructive GCP CLI operations |
| `block_az_cli` | `Builtin.BlockAzCli` | deny | Block destructive Azure CLI operations |
| `block_kubectl` | `Builtin.BlockKubectl` | deny | Block destructive kubectl operations |
| `block_terraform` | `Builtin.BlockTerraform` | deny | Block destructive terraform operations |
| `block_helm` | `Builtin.BlockHelm` | deny | Block destructive helm operations |
| `block_gh_pipeline` | `Builtin.BlockGhPipeline` | deny | Block `gh workflow run/enable/disable` and `gh run rerun/cancel` |

#### SQL & Databases
| Key | Module | Effect | Purpose |
|-----|--------|--------|---------|
| `warn_destructive_sql` | `Builtin.WarnDestructiveSql` | instruct | Warn on DROP, DELETE, TRUNCATE |
| `warn_schema_alteration` | `Builtin.WarnSchemaAlteration` | instruct | Warn on ALTER TABLE |
| `warn_db_cli` | `Builtin.WarnDbCli` | instruct | Warn when a DB shell client is invoked (psql, sqlite3, mysql, mongosh, redis-cli, etc.) |

#### Secrets & Sanitization
| Key | Module | Effect | Purpose |
|-----|--------|--------|---------|
| `sanitize_api_keys` | `Builtin.SanitizeApiKeys` | instruct | Redact API key patterns in tool output |
| `sanitize_prompt_api_keys` | `Builtin.SanitizePromptApiKeys` | instruct | Redact API keys in UserPromptSubmit payloads |
| `sanitize_connection_strings` | `Builtin.SanitizeConnectionStrings` | instruct | Redact DB connection strings |
| `sanitize_jwt` | `Builtin.SanitizeJwt` | instruct | Redact JWT tokens |
| `sanitize_private_key_content` | `Builtin.SanitizePrivateKeyContent` | instruct | Redact PEM-encoded private key content |
| `sanitize_bearer_tokens` | `Builtin.SanitizeBearerTokens` | instruct | Redact `Bearer <token>` values |

#### Package & Publishing
| Key | Module | Effect | Purpose |
|-----|--------|--------|---------|
| `warn_package_publish` | `Builtin.WarnPackagePublish` | instruct | Warn on `npm publish`, `hex publish`, `gem push`, etc. |
| `warn_global_package_install` | `Builtin.WarnGlobalPackageInstall` | instruct | Warn on global package installs (`npm install -g`, etc.) |
| `prefer_package_manager` | `Builtin.PreferPackageManager` | instruct | Warn when using a package manager that differs from the project's configured preference. Requires `"packageManager"` condition key (`"npm"` \| `"yarn"` \| `"pnpm"` \| `"bun"`). No-op without the condition. |

#### Files & Background
| Key | Module | Effect | Purpose |
|-----|--------|--------|---------|
| `warn_large_file_write` | `Builtin.WarnLargeFileWrite` | instruct | Warn when writing large files |
| `warn_background_process` | `Builtin.WarnBackgroundProcess` | instruct | Warn on background operator `&` in Bash commands |

#### Workflows
| Key | Module | Effect | Purpose |
|-----|--------|--------|---------|
| `workflow_business_hours_only` | `Builtin.WorkflowBusinessHoursOnly` | deny | Block tool calls outside configured business hours |

---

## Evaluator Algorithm

`EyeInTheSky.IAM.Evaluator.decide/2` runs this pipeline:

1. **Build candidates**: fetch global enabled policies from `PolicyCache.all_enabled/0` (ETS).
   Also fetch document-contributed policies from `PolicyCache.for_agent_type/1` if
   `ctx.agent_type` is a non-wildcard string. Each candidate is
   `%{policy: Policy.t(), source: :global | {:document, id, name, agent_type}}`.

2. **Filter**: run `candidate_matches?/2` on each candidate:
   - `event` must match `ctx.event` (or be `"*"`)
   - `agent_type` must match `ctx.agent_type` (or be `"*"`) — skipped for document candidates
     (the document attachment IS the scope)
   - `action` must match `ctx.action` (tool name) (or be `"*"`)
   - `resource_glob` glob matched against `ctx.resource` (or be nil/empty)
   - `project_path` glob matched against `ctx.project_path` (or be `"*"`)
   - `condition` evaluated via `ConditionEval.matches?/3`
   - `builtin_matcher` dispatched via `safe_builtin_match/2` if set

3. **Partition** passing candidates into `denies`, `allows`, `instructs`.

4. **Resolve permission**:
   - Any deny → winner = lowest rank `{-priority, id, source_rank}`; `default?: false`
   - No deny, any allow → winner = lowest rank allow; `default?: false`
   - No deny, no allow → fallback permission (`:allow` by default); `winner = nil`; `default?: true`

5. **Instructions**: all `instruct` matches are always attached to the decision, sorted by rank,
   regardless of the final permission or whether fallback fired.

**Deny wins unconditionally** — no allow policy can override a matched deny.

---

## Agent Type Enrichment from Session

Claude Code hook payloads do not include an `agent_type` field. The IAM controller
enriches the params before normalization:

```elixir
# IAMController.decide/2
params
|> enrich_agent_type()       # resolves agent_type from session_id if not present
|> Normalizer.normalize()
|> Evaluator.decide()
```

`enrich_agent_type/1` calls `Sessions.agent_type_for_session/1`, which does a 3-table join:

```
sessions → agents → agent_definitions → slug
```

The resolved slug becomes `agent_type` in the context. This is what makes document-based
policies fire correctly for named agent types (e.g. `"code-auditor"`). If the session UUID
is missing or the join finds no row, `agent_type` defaults to `"*"`.

`Map.put_new` is used — an explicit `agent_type` in the payload always wins over the DB-resolved one.

---

## Policy Documents

Policy documents are named collections of policies that can be attached to agent type strings.
Document attachment is a **parallel activation path** separate from the global `enabled` flag:

- A policy with `enabled: false` (globally disabled) **will** be evaluated if it belongs to a
  document attached to the requesting agent type.
- A policy with `enabled: true` (globally enabled) **also** appears in the global candidate pool.
- The same policy can be evaluated twice (once from global, once from a document) — both trace
  entries appear in the decision, and the first deny/allow wins by rank.

Attachment is via `iam_agent_type_documents` table: `{agent_type, document_id}` unique pairs.
`PolicyCache.for_agent_type/1` loads document candidates keyed by `{:agent_type_candidates, agent_type}`.

### Bulk Attach

```elixir
IAM.attach_documents_to_agent_type("code-reviewer", [1, 2, 3])
# {:ok, 2}  → 2 new attachments; doc already attached is skipped (ON CONFLICT DO NOTHING)
```

Transactional. Cache invalidated only on full success.

### Source Metadata

Every candidate carries an `EvaluationSource`:
- `:global` — came from the global enabled pool
- `{:document, id, name, attached_agent_type}` — came from a document

The decision's `winning_source` field stores `EvaluationSource.label/1`:
- `"global"` or `"document \"Name\" → code-reviewer"` — use this for UI display, never
  pattern-match the raw tuple in LiveView.

---

## System Policies

System policies have a non-nil `system_key` (e.g. `"builtin.block_sudo"`). They differ from
user policies in two ways:

| Aspect | User policy | System policy |
|--------|-------------|---------------|
| `system_key` | nil | Required (`"builtin.*"`) |
| `builtin_matcher` | Not allowed | Optional (any registered key) |
| `editable_fields` | All fields | Limited set: `enabled`, `priority`, `condition`, `message` |
| Locked fields | None | `name`, `effect`, `action`, `event`, `builtin_matcher`, `system_key`, etc. |

The `update_changeset` enforces `editable_fields` via `enforce_locked_fields/2` — attempts to
change locked fields return a changeset error.

### Seeding

`EyeInTheSky.IAM.Seeds.run/0` runs at boot and idempotently inserts system policies. It uses
`seed_builtin/1`, which no-ops if the row already exists. This means user modifications to
editable fields (enabled, priority, condition, message) survive restarts.

### Reseeding

`IAM.reseed_builtin/1` force-overwrites an existing system policy to its canonical seed
definition, bypassing the locked-field guard (intentional — this is an explicit admin reset):

```elixir
IAM.reseed_builtin("builtin.block_sudo")
# {:ok, %Policy{}} — overwrites all fields including locked ones

IAM.reseed_builtin("builtin.unknown")
# {:error, :not_in_seeds}
```

It uses `create_changeset` (not `update_changeset`) on the existing row. Invalidates the
policy cache on success.

**UI**: System policy edit pages show a "Reset to seed defaults" button with a confirmation
dialog. Overwrites `enabled`, `priority`, `condition`, and `message`.

---

## Policy Cache

`EyeInTheSky.IAM.PolicyCache` is an ETS-backed GenServer.

- `all_enabled/0` — returns all `enabled: true` global policies, loaded from DB on startup or
  invalidation.
- `for_agent_type/1` — returns document-contributed candidates for an agent type, keyed in ETS
  by `{:agent_type_candidates, agent_type}`.
- **Load limit**: 5000 rows. If the limit is hit, a Logger warning is emitted.
- **Invalidation triggers**: `create_policy`, `update_policy`, `delete_policy`, `seed_builtin`,
  `reseed_builtin`, `bulk_toggle_enabled`, `attach_documents_to_agent_type`, `detach_document`.
- **Single-node only**: ETS is process-local. Multi-node deployments would need PubSub
  broadcast for cache invalidation (known gap).

Never bypass the cache by querying the DB directly in a hot path — always go through
`IAM.decide/2` or `Evaluator.decide/2`.

---

## Hook Endpoint

The IAM decide endpoint accepts the Claude Code hook payload on stdin:

```
POST /api/v1/iam/hook      (alias: /api/v1/iam/decide)
Content-Type: application/json
```

No authentication required. The payload is the raw Claude Code hook JSON (PreToolUse,
PostToolUse, Stop, or UserPromptSubmit format).

The controller pipeline:
1. Reads raw body
2. `enrich_agent_type/1` — DB lookup to resolve agent_type from session_id
3. `Normalizer.normalize/1` — converts hook payload to `IAM.Context`
4. `Evaluator.decide/2` — runs policy evaluation
5. `HookResponse.to_json/2` — formats the Decision into hook wire format
6. Logs the decision to `iam_decisions` table (async, via Task.Supervisor)

### Response format by event

**PreToolUse**:
```json
{"permissionDecision": "allow"}
{"permissionDecision": "deny", "permissionDecisionReason": "policy message here"}
```
On deny, advisory instructions (instruct policies) are concatenated into the reason.

**PostToolUse**:
```json
{"additionalContext": "advisory message"}
```
Only present if instruct policies matched. Empty body if none.

**Stop**:
```json
{}          // exit 0 — Claude can stop
            // exit 2 — blocks stop when instructions present
```

---

## Query Limits

| Query | Default limit |
|-------|--------------|
| `list_policies/0` | 500 rows |
| `list_policies/1` (filtered) | 500 rows (override with `limit:` key) |
| PolicyCache load | 5000 rows |

---

## Decision Audit Table

Every evaluate call writes to `iam_decisions`:

```sql
session_uuid       text
tool               text            -- tool name from hook payload
resource_path      text            -- full command/path (widened from varchar(255) to text)
permission         text            -- "allow" | "deny"
winning_policy_id  integer
winning_policy_name text
winning_source     text            -- EvaluationSource.label/1 string
reason             text            -- message from winning policy
instructions_snapshot jsonb        -- all instruct-matched policies for this call
inserted_at        timestamp
```

Query recent denies:

```sql
SELECT session_uuid, tool, resource_path, reason, winning_policy_name, winning_source
FROM iam_decisions
WHERE permission = 'deny'
ORDER BY inserted_at DESC
LIMIT 20;
```

---

## Simulator

`EyeInTheSky.IAM.Simulator` evaluates a context against policies without a live hook call.
Used for testing policy configurations without needing a running Claude session.

Web UI: `/iam/simulator` — lets you construct a context and see which policies match and why.

---

## User Policies vs System Policies — Comparison

| Aspect | User policy | System policy |
|--------|-------------|---------------|
| `system_key` | nil | `"builtin.*"` |
| `builtin_matcher` | Not allowed | Registered key |
| Condition predicates | `time_between`, `env_equals`, `session_state_equals` | Same, plus matcher handles deep logic |
| Modified on restart | Persists as-is | Seeded idempotently (editable fields preserved) |
| `reseed_builtin` | N/A | Force-resets all fields to seed defaults |
| Edit page | Full form | Form with locked fields; "Reset to seed defaults" button |

---

## Related

- [IAM_HOOK_INSTALL.md](IAM_HOOK_INSTALL.md) — How to wire Claude Code hooks to the IAM endpoint
- [IAM_POLICY_DOCUMENTS.md](IAM_POLICY_DOCUMENTS.md) — Policy documents design and data model
- [lib/CLAUDE.md](../lib/CLAUDE.md) — Architecture and PubSub events
