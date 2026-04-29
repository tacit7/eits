# EITS IAM System Improvement Notes

## Purpose

This document summarizes recommended improvements to the EITS IAM system, based on the proposed runtime flow and comparison with [FailproofAI](https://github.com/exospherehost/failproofai).

The goal is not to clone FailproofAI. The goal is to use it as a reference for hook-time policy enforcement while making EITS stronger as a project-aware, session-aware, assistant-aware agent supervision system.

---

## Current Proposed Runtime Flow

The proposed EITS IAM flow is directionally strong:

```text
Claude Code hook event
  -> POST /api/v1/iam/decide
  -> Normalizer
  -> IAM.Context
  -> Evaluator
  -> Decision
  -> HookResponse
  -> Claude Code-compatible response
```

This is the correct architecture spine.

The main idea is sound: normalize external hook payloads into a stable internal shape, evaluate policies through a traceable engine, and convert the result back into the JSON shape Claude Code expects.

---

## High-Level Verdict

The architecture is good, but the scope needs discipline.

EITS IAM should focus first on reliable, understandable hook-time enforcement:

```text
allow / deny / instruct / require_approval
```

Do not let the IAM system become a general-purpose prompt rewriting, redaction, workflow automation, approval, audit, and agent behavior modification blob. That is how clean systems become haunted filing cabinets.

---

## What EITS Should Keep

### 1. Normalizer Layer

Keep the `iam/normalizer.ex` layer.

Its job should be to transform Claude Code hook payloads into a stable internal `IAM.Context` struct.

This protects the rest of the system from Claude Code payload changes.

Recommended fields:

```elixir
%IAM.Context{
  event: :pre_tool_use | :post_tool_use | :stop | :user_prompt_submit,
  action: String.t(),
  agent_type: String.t(),
  project_id: integer() | nil,
  project_path: String.t() | nil,
  session_id: integer() | nil,
  assistant_id: integer() | nil,
  user_id: integer() | nil,
  workspace_id: integer() | nil,
  cwd: String.t() | nil,
  git_branch: String.t() | nil,
  resource_path_raw: String.t() | nil,
  resource_path_normalized: String.t() | nil,
  resource_path_relative: String.t() | nil,
  resource_inside_project?: boolean() | nil,
  raw_tool_input: map(),
  raw_payload: map()
}
```

Some fields can be nullable for now, but the struct should leave room for the future.

---

### 2. Evaluator Layer

Keep `iam/evaluator.ex`.

The evaluator should:

1. Load enabled policies from `PolicyCache`.
2. Match policies against the normalized context.
3. Return a structured decision.
4. Include policy traces for simulator/debugging.

Recommended return shape:

```elixir
%IAM.Decision{
  effect: :allow | :deny | :require_approval | :instruct | :no_match,
  reason: String.t() | nil,
  instructions_for_agent: [String.t()],
  instructions_for_operator: [String.t()],
  matched_policies: [IAM.Policy.t()],
  traces: [IAM.PolicyTrace.t()]
}
```

The trace data matters. Without it, users will not understand why a policy fired. Then they will blame the app, because blaming tools is humanity's most reliable design pattern.

---

### 3. HookResponse Layer

Keep `iam/hook_response.ex`.

Its only job should be translating internal IAM decisions into Claude Code hook response JSON.

Do not let policy evaluation logic leak into this layer.

Example responsibility boundary:

```text
Evaluator decides:
  deny Bash rm -rf

HookResponse formats:
  permissionDecision: "deny"
  reason: "Destructive recursive delete is blocked."
```

---

### 4. Built-In Matcher Registry

Keep `BuiltinMatcher.Registry`.

This is one of the strongest parts of the design.

Complex checks should live in Elixir modules, not JSON blobs.

Good built-in matcher examples:

```text
block_rm_rf
block_sudo
block_env_file_read
block_read_outside_project
block_write_outside_project
block_force_push
block_push_to_protected_branch
warn_destructive_sql
sanitize_api_keys
detect_secret_exfiltration
```

Recommended behaviour:

```elixir
defmodule EyeInTheSky.IAM.BuiltinMatcher do
  @callback matches?(IAM.Context.t(), IAM.Policy.t()) :: boolean()
  @callback instruction_message(IAM.Context.t(), IAM.Policy.t()) :: String.t() | nil
end
```

---

### 5. PolicyCache

Keep `PolicyCache`, but make cache invalidation boring and safe.

Recommended behavior:

```text
1. All policy writes go through EyeInTheSky.IAM.
2. The database transaction commits.
3. After commit, an event is broadcast through EyeInTheSky.Events.
4. PolicyCache reloads affected policy data.
5. Evaluator reads from PolicyCache.
6. Simulator can optionally bypass cache for debugging.
```

Important rule:

```text
Do not broadcast cache invalidation before the database commit.
```

Otherwise the cache may reload stale policy data. That bug is not clever. It is just annoying in a trench coat.

---

## Major Improvements Needed

## 1. Add `require_approval` as a First-Class Decision

Current proposed effects:

```text
deny / allow / instruct
```

Recommended effects:

```text
allow / deny / require_approval / instruct / no_match
```

Even if approval is not implemented in MVP, model it now.

Why:

- Approval is core to agent supervision.
- Adding it later will reshape evaluator logic.
- Some operations are not simply safe or unsafe.
- Users will expect approval for operations like `git push`, dependency installs, destructive migrations, and production-affecting commands.

Recommended resolution order:

```text
1. Deny wins.
2. Require approval wins over allow.
3. Highest-priority allow wins.
4. No match falls back to default behavior.
5. Instruct policies accumulate separately.
```

For MVP, `require_approval` can degrade to deny:

```text
This action requires approval, but approval workflow is not enabled yet.
```

That is better than pretending every risky operation is either safe or forbidden.

---

## 2. Add Session and Assistant Scope Early

The proposed context includes:

```text
agent_type
action
project_id/path
resource_path
prompt or tool_response
event
```

Add:

```text
session_id
assistant_id
user_id
workspace_id
cwd
git_branch
```

Why this matters:

### `session_id`

Enables temporary/session-specific exceptions.

Example:

```text
Allow this session to run migrations for the next 15 minutes.
```

### `assistant_id`

Enables capability profiles.

Example:

```text
Reader assistants cannot write files.
Repo Operator assistants can run tests and git commands.
```

### `git_branch`

Enables practical safety rules.

Example:

```text
Deny git push on main.
Require approval for git push on release/*.
Allow git push on feature/*.
```

### `cwd`

Needed for safe path resolution and command interpretation.

---

## 3. Normalize and Canonicalize Resource Paths

This is critical.

If EITS supports resource path globbing, it must normalize paths before matching.

Dangerous examples:

```bash
cat ../secrets/.env
cat ./lib/../.env
cat /absolute/path/to/project/.env
cat symlink_to_secret
```

The normalizer should produce:

```elixir
resource_path_raw
resource_path_normalized
resource_path_relative_to_project
resource_inside_project?
resource_realpath
```

Minimum MVP rule:

```text
If a resource path cannot be safely resolved relative to the project root, treat it as high-risk.
```

Recommended policy defaults:

```text
Deny reads outside project.
Deny writes outside project.
Deny reads of .env and secret files.
Deny symlink traversal outside project.
```

This matters especially because EITS is a Tauri/local-first app. The system can inspect the local filesystem. Use that advantage.

---

## 4. Clarify Priority and Specificity Rules

The proposed design says:

```text
Deny always wins. Otherwise highest-priority allow wins.
```

That is mostly right, but incomplete.

Recommended rules:

```text
1. Deny always wins.
2. More specific path/resource policies should beat broader policies within the same effect.
3. Numeric priority resolves ties.
4. Numeric priority should not override deny safety.
```

Example:

```text
Allow Edit on lib/**
Deny Edit on lib/generated/**
```

The deny should win because it is more restrictive and more specific.

Avoid a system where users can accidentally bypass a safety rule by creating a broad allow policy with a bigger number. That is not power-user flexibility. That is a trap wearing a settings page.

---

## 5. Separate Agent Instructions From Operator Instructions

The current design says instruct policies accumulate as advisory text.

That needs sharper semantics.

Use separate fields:

```elixir
instructions_for_agent: [String.t()]
instructions_for_operator: [String.t()]
reason: String.t()
```

Example:

```text
reason:
  "Direct push to main is blocked."

instructions_for_agent:
  "Create a feature branch and open a pull request instead."

instructions_for_operator:
  "This policy fired because protected_branch_push matched branch main."
```

Do not throw all instructions into one string pile.

String piles are where architecture goes to decompose quietly.

---

## 6. Keep UserPromptSubmit Out of MVP

The proposed flow includes:

```text
UserPromptSubmit instruct
suppressUserPrompt
replaced userPrompt
secret-redaction path
```

This should be deferred.

Reason:

- PreToolUse IAM is permission enforcement.
- UserPromptSubmit redaction is prompt rewriting / data loss prevention.
- These are related, but not the same subsystem.
- Combining them too early bloats IAM.

Recommended MVP events:

```text
PreToolUse
PostToolUse
Stop
```

Defer:

```text
UserPromptSubmit
prompt replacement
secret redaction
suppressUserPrompt
```

You can leave the event atom in the type system, but do not build user-facing UX around it yet.

---

## 7. Simplify Conditions for MVP

The proposed predicates include:

```text
time_between
env_equals
session_state_equals
```

Recommended MVP predicates:

```text
event
agent_type
action/tool
project_id
resource glob
builtin matcher
enabled
effect
priority
instructions
```

Defer:

```text
time predicates
env predicates
session state predicates
nested condition groups
complex boolean logic
```

`env_equals` is especially risky because it creates invisible behavior. Debugging policy behavior based on environment variables is a great way to punish your future self for sins you have not committed yet.

---

## Recommended MVP Scope

Build this first:

```text
PreToolUse allow/deny
PostToolUse stop/continue handling
Stop handling
PolicyCache
System policies
User policies
Built-in matcher registry
Simulator with traces
Basic CRUD
Path normalization
Session and assistant fields in context
Future-compatible require_approval decision type
```

Do not build these yet:

```text
UserPromptSubmit redaction
prompt rewriting
approval inbox
complex condition predicates
arbitrary custom policy code
repo-local policy import/export
full capability profile UI
provider abstraction for Codex/Gemini
```

---

## Suggested Default System Policies

Ship useful baseline policies.

### File Safety

```text
Deny reads of .env files.
Deny reads of common secret files.
Deny reads outside project root.
Deny writes outside project root.
Deny writes to IAM policy files unless explicitly allowed.
Deny modification of generated/vendor/dependency directories unless explicitly allowed.
```

### Shell Safety

```text
Deny rm -rf style destructive deletes.
Deny sudo.
Deny chmod/chown over broad paths.
Deny curl | sh.
Deny shell commands that attempt to read secrets.
Require approval for package installs.
Require approval for database migrations.
```

### Git Safety

```text
Deny force push.
Deny push to main/master.
Require approval for push to release branches.
Allow normal commits on feature branches.
```

### Database Safety

```text
Warn or require approval for destructive SQL.
Deny DROP DATABASE.
Require approval for production database URLs.
```

### Network Safety

```text
Require approval for network exfiltration-like commands.
Deny posting secret-looking values to external URLs.
```

Network policies can wait until EITS exposes network-capable tools more explicitly.

---

## Policy Storage Recommendation

Use Postgres as the source of truth for MVP.

Recommended table direction:

```text
iam_policies
  id
  name
  description
  enabled
  effect
  priority
  event
  agent_type
  action
  project_id
  project_path_glob
  assistant_id
  session_id
  resource_glob
  builtin_matcher
  condition_json
  instructions
  reason
  system_key
  editable_fields
  inserted_at
  updated_at
```

Notes:

- `system_key` identifies seeded/system policies.
- `editable_fields` controls what users may change.
- User policies have `system_key = nil`.
- Controllers and LiveViews should not write directly to Repo.
- All writes should go through `EyeInTheSky.IAM`.

---

## UI Recommendations

### Do Not Lead With Raw IAM CRUD

A giant IAM form will confuse users.

Start with practical policy templates:

```text
Reader
Editor
Test Runner
Repo Operator
Orchestrator
Custom
```

Each template should translate into policies.

Example:

```text
Reader:
  Can read project files.
  Cannot edit files.
  Cannot run shell commands.
  Cannot use git write operations.
```

Example:

```text
Repo Operator:
  Can edit files.
  Can run tests.
  Can commit.
  Requires approval for push.
  Requires approval for dependency installs.
```

### Policy List UI

Show:

```text
Policy name
Effect
Scope
Tool/action
Project
Assistant/session
Status
Last updated
```

Use badges for:

```text
System
User
Enabled
Disabled
Deny
Allow
Approval
Instruct
```

### Policy Detail UI

Show:

```text
Summary
Scope
Conditions
Effect
Instructions
Matched examples
Trace preview
Editable fields
```

### Simulator UI

This is required.

Simulator should show:

```text
Input hook payload
Normalized IAM.Context
Matched policies
Skipped policies with reasons
Final decision
Claude Code response JSON
```

Without this, users will not trust the system.

---

## Comparison With FailproofAI

FailproofAI is useful as a reference, but EITS should not copy it directly.

### FailproofAI Strengths

FailproofAI is strong at:

```text
Local hook policy enforcement
Built-in policy catalog
Custom JavaScript policies
Project/local/global file config
Agent monitor
Simple allow/deny/instruct model
No-cloud local execution
```

### EITS Strengths

EITS can be stronger at:

```text
Project-aware governance
Session-aware policies
Assistant capability profiles
Operator approvals
Audit trails
Native app workflow
Team/workspace-aware policy model later
Integration with EITS tasks, sessions, agents, and projects
```

### Main Product Difference

FailproofAI is closer to:

```text
Local reliability and policy sidecar for coding agents.
```

EITS IAM should be:

```text
Project-aware agent governance inside an operator control plane.
```

That is the real difference.

Do not compete by cloning FailproofAI one-to-one. Borrow the proven hook-policy mechanics, then make EITS deeper because it knows the project, session, assistant, task, operator, and eventually workspace context.

---

## What To Borrow From FailproofAI

Borrow these ideas:

```text
Built-in baseline policies
Simple allow / deny / instruct mental model
Policy traces
Agent monitor-like visibility
Project-local convention files later
Local-first/no-cloud default
```

Especially borrow the idea that developers like repo-local conventions.

Eventually EITS can support:

```text
.eits/policies/*.json
.eits/agents/*.json
.eits/skills/*.md
```

But do not make repo files authoritative in MVP.

---

## What Not To Copy From FailproofAI Yet

Avoid copying these directly:

```text
Arbitrary JavaScript custom policies
File-based config as the primary source of truth
Generic multi-agent support too early
Fail-open policy behavior for critical safety policies
Complex config merging
```

For EITS, arbitrary user-authored policy code should be deferred until there is a real sandboxing story.

A Phoenix app running arbitrary policy code is a loaded footgun wearing a tiny hat.

---

## Suggested Implementation Order

## Phase 1: Core Enforcement

```text
Create IAM.Context struct.
Implement Normalizer for PreToolUse.
Implement Policy schema.
Implement PolicyCache.
Implement Evaluator.
Implement HookResponse.
Add basic system policies.
Add policy traces.
Add simulator.
```

## Phase 2: Safer Matching

```text
Add path normalization.
Add cwd and git branch extraction.
Add session_id and assistant_id to context.
Add resource_inside_project? checks.
Add protected branch matcher.
Add secret file matcher.
```

## Phase 3: Operator UX

```text
Build policy list.
Build policy create/edit forms.
Add system policy locks.
Add policy templates.
Improve simulator traces.
Add audit log.
```

## Phase 4: Approval Workflow

```text
Add require_approval effect.
Create approval_requests table.
Add approval inbox.
Add timeout behavior.
Make HookResponse understand pending approval.
Decide sync vs async approval behavior.
```

## Phase 5: Portability

```text
Add import/export.
Support .eits/policies later.
Add policy packs.
Add assistant capability profiles.
```

---

## Final Recommended Architecture

```text
Claude Code Hook
  -> Shell hook script
  -> /api/v1/iam/decide
  -> IAM.Normalizer
  -> IAM.Context
  -> IAM.PolicyCache
  -> IAM.Evaluator
  -> IAM.Resolver
  -> IAM.Decision
  -> IAM.HookResponse
  -> Claude Code
```

Supporting components:

```text
EyeInTheSky.IAM
  Owns all policy writes and reads.

EyeInTheSky.Events
  Owns PubSub broadcasts and cache invalidation events.

EyeInTheSky.IAM.PolicyCache
  Stores enabled policy data for runtime evaluation.

EyeInTheSky.IAM.BuiltinMatcher.Registry
  Dispatches complex policy checks to Elixir modules.

EyeInTheSkyWeb.IAM.PolicyLive
  Operator-facing policy CRUD.

EyeInTheSkyWeb.IAM.SimulatorLive
  Dry-runs hook payloads through the same evaluator.
```

---

## Final Recommendation

Keep the architecture. Reduce the scope.

Build the enforcement loop first. Make it boring, traceable, and hard to bypass.

The strongest MVP is:

```text
PreToolUse enforcement
Path-safe policy matching
Built-in deny/allow rules
System/user policy separation
Policy cache
Simulator traces
Claude Code-compatible responses
```

Everything else can wait.

Especially defer:

```text
UserPromptSubmit redaction
arbitrary custom policies
full approval inbox
complex predicates
repo-local policy sync
```

EITS IAM should become a practical agent supervision layer, not a tiny AWS IAM tribute band running inside a Phoenix app.
