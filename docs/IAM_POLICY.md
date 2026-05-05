# IAM Policies

An IAM policy is a declarative rule that controls whether a tool call is allowed, denied, or allowed with a warning. Policies match against tool calls using conditions and specialized built-in matchers (system policies only).

---

## Policy Structure

All policies have this JSON schema:

```json
{
  "name": "block_sudo",
  "description": "Block all sudo commands",
  "action": "deny",
  "system_key": "builtin.block_sudo",
  "builtin_matcher": "block_sudo",
  "conditions": []
}
```

| Field | Type | Required | Notes |
|-------|------|----------|-------|
| `name` | string | yes | Human-readable policy name |
| `description` | string | yes | Explanation of what the policy does |
| `action` | enum | yes | `"allow"`, `"deny"`, or `"instruct"` (advisory) |
| `system_key` | string | no | Reserved identifier for system policies; restricts `builtin_matcher` to system policies only |
| `builtin_matcher` | string | no | **Phase 4a only**: dispatch to a registered BuiltinMatcher module for specialized detection (system policies only) |
| `conditions` | array | yes | Optional condition expressions; all must match for the policy to apply |

---

## Conditions

Conditions are declarative, Turing-complete expressions for matching common tool-call properties:

```json
{
  "kind": "tool_name_match",
  "value": "Bash|Edit|Write"
}
```

Supported condition kinds:

| Kind | Value Format | Example | Notes |
|------|--------------|---------|-------|
| `tool_name_match` | regex | `"Bash"`, `"Bash\|Edit"` | Matches tool name |
| `resource_path_match` | regex | `"/tmp/.*"` | Matches resource path |
| `command_match` | regex | `"rm -rf"` | **User policies only** — matches command string |
| `content_match` | regex | `"password"` | **User policies only** — matches file content |

**Important**: `command_match` and `content_match` are reserved for user-authored policies. System policies cannot use these; they must use `builtin_matcher` instead.

---

## Phase 4a: Built-in Matchers

Phase 4a introduces **BuiltinMatcher**, a behaviour that allows system policies to dispatch specialized detection logic beyond simple regex matching. Builtin matchers can:

- Parse command arguments and flags
- Resolve file paths against the working directory
- Inspect git state and branch names
- Analyze SQL statements
- Access environment variables

### BuiltinMatcher Behaviour

All builtin matchers implement the `EITS.IAM.BuiltinMatcher` behaviour:

```elixir
@callback matches?(payload :: map()) :: boolean()
```

Each matcher receives the full PreToolUse payload (tool name, resource path, command, environment, working directory, etc.) and returns true/false.

### Registry

The `EITS.IAM.BuiltinMatcher.Registry` maintains a stable mapping of 40+ registered keys organized by category:

#### Core / Filesystem Safety
| Key | Module | Purpose |
|-----|--------|---------|
| `"block_sudo"` | `EITS.IAM.Builtin.BlockSudo` | Deny sudo commands |
| `"block_rm_rf"` | `EITS.IAM.Builtin.BlockRmRf` | Deny `rm -rf` patterns |
| `"protect_env_vars"` | `EITS.IAM.Builtin.ProtectEnvVars` | Deny access to sensitive env vars (API keys, tokens) |
| `"block_env_files"` | `EITS.IAM.Builtin.BlockEnvFiles` | Deny writes to `.env*` files |
| `"block_read_outside_cwd"` | `EITS.IAM.Builtin.BlockReadOutsideCwd` | Deny read access outside working directory (with URL path filtering) |
| `"block_secrets_write"` | `EITS.IAM.Builtin.BlockSecretsWrite` | Deny writes to `.pem`, `.key`, `.crt`, SSH identity files |

#### Secrets & Sanitization
| Key | Module | Purpose |
|-----|--------|---------|
| `"sanitize_jwt"` | `EITS.IAM.Builtin.SanitizeJwt` | Redact JWT tokens in logs/output |
| `"sanitize_private_key_content"` | `EITS.IAM.Builtin.SanitizePrivateKeyContent` | Redact private key content in logs/output |
| `"sanitize_bearer_tokens"` | `EITS.IAM.Builtin.SanitizeBearerTokens` | Redact bearer tokens in logs/output |

#### Git & Version Control
| Key | Module | Purpose |
|-----|--------|---------|
| `"block_push_master"` | `EITS.IAM.Builtin.BlockPushMaster` | Deny git push to master/main |
| `"block_work_on_main"` | `EITS.IAM.Builtin.BlockWorkOnMain` | Deny git worktree operations on main/master (worktree-aware branch detection) |
| `"block_force_push"` | `EITS.IAM.Builtin.BlockForcePush` | Deny `git push --force` / `git push -f` with branch allowlist |
| `"warn_git_amend"` | `EITS.IAM.Builtin.WarnGitAmend` | Warn on `git commit --amend` or `git rebase -i` (history rewrite advisory) |

#### CI/CD & Deployment
| Key | Module | Purpose |
|-----|--------|---------|
| `"block_gh_pipeline"` | `EITS.IAM.Builtin.BlockGhPipeline` | Deny `gh workflow run/enable/disable` and `gh run rerun/cancel` |

#### Cloud CLI Safety
| Key | Module | Purpose |
|-----|--------|---------|
| `"block_aws_cli"` | `EITS.IAM.Builtin.BlockAwsCli` | Block destructive AWS operations (terminate, delete, etc.) |
| `"warn_aws_cli"` | `EITS.IAM.Builtin.WarnAwsCli` | Warn on AWS operations affecting billing (advisory) |
| `"block_gcp_cli"` | `EITS.IAM.Builtin.BlockGcpCli` | Block destructive GCP operations |
| `"warn_gcp_cli"` | `EITS.IAM.Builtin.WarnGcpCli` | Warn on GCP operations affecting billing (advisory) |
| `"block_azure_cli"` | `EITS.IAM.Builtin.BlockAzureCli` | Block destructive Azure operations |
| `"warn_azure_cli"` | `EITS.IAM.Builtin.WarnAzureCli` | Warn on Azure operations affecting billing (advisory) |
| `"block_databricks_cli"` | `EITS.IAM.Builtin.BlockDatabricksCli` | Block destructive Databricks operations |
| `"warn_databricks_cli"` | `EITS.IAM.Builtin.WarnDatabricksCli` | Warn on Databricks operations (advisory) |
| `"block_heroku_cli"` | `EITS.IAM.Builtin.BlockHerokuCli` | Block destructive Heroku operations |
| `"warn_heroku_cli"` | `EITS.IAM.Builtin.WarnHerokuCli` | Warn on Heroku operations (advisory) |
| `"block_kubernetes_cli"` | `EITS.IAM.Builtin.BlockKubernetesCli` | Block destructive Kubernetes operations |
| `"warn_kubernetes_cli"` | `EITS.IAM.Builtin.WarnKubernetesCli` | Warn on Kubernetes operations (advisory) |

#### Package Management & Installation
| Key | Module | Purpose |
|-----|--------|---------|
| `"prefer_package_manager"` | `EITS.IAM.Builtin.PreferPackageManager` | Warn on direct binary/script installation (advisory) |

#### SQL & Data
| Key | Module | Purpose |
|-----|--------|---------|
| `"warn_destructive_sql"` | `EITS.IAM.Builtin.WarnDestructiveSql` | Warn on DROP, DELETE, TRUNCATE SQL (advisory) |
| `"warn_schema_alteration"` | `EITS.IAM.Builtin.WarnSchemaAlteration` | Warn on ALTER TABLE in production (advisory) |

#### Package Publishing & Dependencies
| Key | Module | Purpose |
|-----|--------|---------|
| `"warn_package_publish"` | `EITS.IAM.Builtin.WarnPackagePublish` | Warn on package publish commands (advisory) |
| `"warn_global_package_install"` | `EITS.IAM.Builtin.WarnGlobalPackageInstall` | Warn on global package installation (advisory) |

#### Background Processes & Cleanup
| Key | Module | Purpose |
|-----|--------|---------|
| `"warn_background_process"` | `EITS.IAM.Builtin.WarnBackgroundProcess` | Warn on background process operators (&) (advisory) |
| `"require_commit_before_stop"` | `EITS.IAM.Builtin.RequireCommitBeforeStop` | Warn when session ends with uncommitted changes |

---

## Dispatcher: `specialized_matches?/2`

The `EITS.IAM.Evaluator` calls `specialized_matches?/2` when a policy has a `builtin_matcher`:

```elixir
defp specialized_matches?(payload, policy) do
  case EITS.IAM.BuiltinMatcher.safe_builtin_match(
    payload,
    policy.builtin_matcher
  ) do
    true -> true
    false -> false
    {:error, _reason} -> false  # fail closed: error = no match
  end
end
```

### `safe_builtin_match/2`

Wraps all builtin matcher calls with rescue/catch to prevent panics from crashing the policy evaluator:

- **Success**: Returns `true` or `false` from the matcher module
- **Exception**: Catches all errors, logs with telemetry, returns `false` (no match)
- **Fail-closed**: If a matcher throws, the policy does NOT match; the tool call is evaluated against the next policy

This ensures that even buggy or malicious matchers cannot bypass policy evaluation.

---

## System Policies: Seeding

The `EITS.IAM.Seeds` module runs at boot time and idempotently seeds 40+ system policies into the database. Each policy:

- Has a `system_key` (e.g., `"builtin.block_sudo"`)
- Dispatches via its corresponding builtin matcher
- Is inserted/updated on every app start; no duplicates

Example:

```elixir
%{
  name: "Block sudo commands",
  description: "Prevents execution of sudo",
  action: "deny",
  system_key: "builtin.block_sudo",
  builtin_matcher: "block_sudo",
  priority: 100,
  conditions: [
    %{kind: "tool_name_match", value: "Bash"}
  ]
}
```

**Why idempotent seeding?** If a user disables or modifies a system policy, restarting the app will restore it. This ensures critical safety policies cannot be accidentally deleted.

### Notable Matcher Details

**`block_read_outside_cwd`** (fixed): Now filters out URL-like paths (e.g., `/api/v1/foo`) to prevent false positives when paths appear in tool arguments like `--message` or `--instructions`. Only candidates whose first filesystem segment exists trigger the match.

**`block_work_on_main`** (fixed): Worktree-aware branch detection. Extracts `cd` targets from compound shell commands to evaluate commits against the worktree's HEAD rather than the project root's HEAD. Prevents false positives on `cd .claude/worktrees/foo && git commit`.

**`block_secrets_write`**: Denies Write/Edit/MultiEdit operations on private key and certificate files (`.pem`, `.key`, `.pfx`, `.crt`, SSH identities). Supports an `"allowPaths"` condition for generated self-signed certs in test fixtures.

**`require_commit_before_stop`**: Runs on Stop event (not PreToolUse). Runs `git status --porcelain` against the session's `project_path` and injects a warning into the transcript if uncommitted changes are found. Supports `"checkUntracked"` (default true) and `"ignorePaths"` conditions.

---

## Policy Evaluation Flow

When Claude Code calls a tool:

1. **PreToolUse hook** → EITS IAM decide endpoint
2. **Load policies** (by action: deny first, then allow, then instruct)
3. **For each policy**:
   - Evaluate all `conditions` (AND logic)
   - If a builtin_matcher is set, call `specialized_matches?/2`
   - Both conditions AND builtin_matcher must match
4. **Return first match**:
   - Deny → block the call
   - Allow → let it through
   - Instruct → allow + advisory reason
5. **Default (no match)** → allow (fail-open)

---

## Query Limits and Safety Guards

All IAM database queries are bounded with explicit `LIMIT` clauses to prevent unbounded table scans and memory exhaustion in misconfigured environments with excessive policies.

### `list_policies/0` — Default 500 row limit

```elixir
def list_policies do
  Policy
  |> order_by([p], desc: p.priority, asc: p.id)
  |> limit(500)
  |> Repo.all()
end
```

Used by the IAM admin LiveView and policy simulator. Capped at 500 rows by default.

### `list_policies/1` — Default 500 row limit with opt-in override

```elixir
def list_policies(filters) when is_list(filters) or is_map(filters) do
  {limit, filters} =
    if is_list(filters) do
      {Keyword.get(filters, :limit, 500), Keyword.delete(filters, :limit)}
    else
      {Map.get(filters, :limit, 500), Map.delete(filters, :limit)}
    end
  # ... apply filters ...
  |> limit(^limit)
  |> Repo.all()
end
```

Filtered policy queries default to 500 rows. Callers can override by passing `limit: N` in the filters map/keyword list. This guards against misconfigured environments where the number of policies exceeds safe limits.

### Policy Cache: 5000 row load limit

The `EITS.IAM.PolicyCache` GenServer loads policies from the database with a hard `@load_limit` of 5000 rows:

```elixir
@load_limit 5_000

defp load_from_db do
  policies =
    Policy
    |> where([p], p.enabled == true)
    |> limit(@load_limit)
    |> Repo.all()

  if length(policies) >= @load_limit do
    Logger.warning(
      "IAM policy_cache: LIMIT reached (#{@load_limit}) — some policies may not be evaluated"
    )
  end

  policies
end
```

- Loads enabled policies in memory for the cache
- If the limit is hit, a warning is logged to alert operators that some policies may not be evaluated
- Prevents unbounded memory growth from excessive policy counts

**Note**: The cache limit is higher than the list_policies queries (5000 vs 500) because the cache is a single in-memory data structure, while list_policies is exposed to user-facing admin tools and should be more restrictive.

---

## Phase 6: Hook Integration & Offline Banner

Phase 6 adds tooling to ensure IAM hooks are installed and operational in local Claude Code environments.

### HooksChecker Module

The `EITS.IAM.HooksChecker` module checks whether IAM hooks are installed in the local Claude Code settings file (`~/.claude/settings.json`):

```elixir
@spec status() :: :installed | :not_installed | :not_applicable
def status do
  if Desktop.desktop_mode?() do
    check_settings_file()
  else
    :not_applicable  # web agents use remote hooks
  end
end
```

Returns:
- `:installed` — PreToolUse hook references the IAM endpoint
- `:not_installed` — PreToolUse hook is absent or settings.json unreadable
- `:not_applicable` — Not running in Tauri desktop mode; web agents use remote hooks

**Critical event**: Only PreToolUse is checked (the blocking event). PostToolUse and Stop are advisory; missing them doesn't leave the system unprotected.

### Offline Banner

IAM LiveViews call `HooksChecker.status()` on mount to decide whether to show an offline banner. The banner alerts users when:
- Running in Tauri desktop mode (local Claude Code)
- IAM hooks are not installed or settings.json is unreadable
- The local IAM endpoint cannot be reached

This prevents silent policy bypasses in offline environments.

### `/iam/hook` Route Alias

Phase 6 adds a `/iam/hook` route alias to the REST API's `/api/v1/iam/decide` endpoint. This shorter path is used by hook commands in Claude Code's `settings.json`:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "command": "curl -s http://localhost:5001/iam/hook -X POST -d '...' --fail-with-body"
      }
    ]
  }
}
```

---

## Tauri IAM Hook Installer

The Tauri desktop app (`src-tauri/src/lib.rs`) includes an automated IAM hook installer that runs on every startup.

### Installation Flow

On startup, `install_iam_hooks(&port)` idempotently writes hook commands to `~/.claude/settings.json`:

```rust
// Write ~/.claude/settings.json hooks on every startup so agents
// automatically POST tool events to the local IAM endpoint.
// Idempotent: skips events that already have the hook present.
let port = std::env::var("PORT").unwrap_or_else(|_| "5050".to_string());
install_iam_hooks(&port);
```

### Idempotency

The installer checks each event type (PreToolUse, PostToolUse, Stop) independently and only adds a hook group when none of the existing entries reference `"iam/hook"`. Safe to call on every startup — no duplicates or overwrites.

### Hook Structure

Installed hooks include:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "command": "curl -s http://localhost:5050/iam/hook -X POST -H 'Content-Type: application/json' -d @- --fail-with-body"
      }
    ]
  }
}
```

Port is resolved from the `PORT` environment variable (default 5050).

---

## Migration: `20260417230411_add_builtin_matcher_to_iam_policies`

Adds the `builtin_matcher` column:

```sql
ALTER TABLE iam_policies ADD COLUMN builtin_matcher VARCHAR(255);
CREATE INDEX ix_iam_policies_builtin_matcher ON iam_policies(builtin_matcher) 
  WHERE system_key IS NOT NULL;
```

- Nullable: system policies set it; user policies ignore it
- Indexed: only rows with `system_key` (system policies)
- Validated: schema rejects invalid builtin matcher keys

---

## User Policies vs. System Policies

| Aspect | User Policy | System Policy |
|--------|-------------|---------------|
| `system_key` | Not set | Required |
| `builtin_matcher` | Not allowed | Optional |
| `command_match` condition | Allowed | Not allowed |
| `content_match` condition | Allowed | Not allowed |
| Persistence | User-authored, mutable | Seeded at boot, idempotent |

---

## Example: Full Policy Flow

User runs `Bash` with `rm -rf /tmp/data`:

1. Hook captures tool call
2. Policies loaded; `block_rm_rf` policy checked
3. Condition `tool_name_match: "Bash"` → matches
4. Builtin matcher `block_rm_rf` called → parses args, detects `rm -rf` → returns true
5. Policy action `deny` applied → Claude Code blocked with reason
6. Decision logged to `iam_decisions` table

---

## Related

- [IAM_HOOK_INSTALL.md](IAM_HOOK_INSTALL.md) — Hook integration and verification
- [lib/CLAUDE.md](../lib/CLAUDE.md) — Architecture and PubSub events
