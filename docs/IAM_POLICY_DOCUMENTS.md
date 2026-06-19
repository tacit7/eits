# IAM Policy Documents

> **Status: Implemented.** This document reflects the current system state. It was originally
> written as a design spec; most spec-phase language has been left intact because the reasoning
> it captures is still useful. Treat "Decision X" sections as rationale, not open questions.

Policy documents are named, reusable collections of policies that can be attached to agent types. When the evaluator processes a hook event, it unions document-contributed candidates with the global pool and runs the standard evaluation pass — with one explicit semantic override for agent-type scoping described below.

---

## Goals

- Let operators define permission profiles (e.g. "ReadOnly", "NoDeployments") as named documents
- Attach one or more documents to an agent type string (e.g. `"code-reviewer"`, `"worker-agent"`)
- Keep existing per-policy `agent_type` filtering unchanged for global policies — documents are additive
- Source metadata preserved through evaluation so trace output, simulator, and audit logs can say where a matching policy came from

## Non-Goals

- Formal `agent_types` table — agent types remain raw strings driven by Claude Code hook payloads
- Replacing inline `agent_type` matching on individual policies
- Cross-project document scoping (all documents are global)
- Policy document versioning or audit history (future)

---

## Resolved Design Decisions

### Decision 1: Document-attached policies bypass policy-level `agent_type`

**Problem**: If Policy A has `agent_type: "root"` and belongs to document "NoShell" attached to `"code-reviewer"`, Policy A would fail the evaluator's `agent_matches?` check and the document attachment would silently do nothing.

**Decision**: When a policy is evaluated because of document attachment, the policy-level `agent_type` filter is bypassed. The document attachment is the agent-type scope. Project, resource, action, condition, and builtin matcher checks still apply normally.

**Rationale**: Operators attach a document to an agent type expecting it to apply. They should not need to audit each inner policy's `agent_type` field to understand why it did or didn't fire.

**Implementation**: The evaluator passes evaluation candidates (structs with source metadata) into matching, not bare `Policy.t()` values. `agent_matches?` is extended to receive the source and skip the check for document-sourced candidates.

### Decision 2: Source metadata preserved through evaluation — no early dedup

**Decision**: Candidates are structured maps with source tags. No dedup on bare policy structs. If the same policy appears globally and in a document, both candidates are kept and both appear in the trace.

Candidate shape at the evaluation layer:

```elixir
%{policy: %Policy{}, source: :global}
%{policy: %Policy{}, source: {:document, document_id, document_name, attached_agent_type}}
```

### Decision 3: `agent_type` strings are trimmed, not case-normalized

Agent type values are external protocol identifiers sent by Claude Code hook payloads. They are:

- Trimmed of leading/trailing whitespace in changesets (user input)
- Stored as-is after trimming
- Compared case-sensitively — must match exactly what the hook payload sends

Document names use a case-insensitive uniqueness index (`lower(name)`) but are stored with original casing.

The wildcard value `"*"` is explicitly rejected as an attachable agent type — enforced in the `AgentTypeDocument` changeset. Documents can only be attached to concrete agent type strings.

### Decision 4: Two distinct candidate types — named to prevent implementation drift

```elixir
# Returned by policies_for_agent_type/1 and PolicyCache.for_agent_type/1
@type document_policy_candidate :: %{
  policy: Policy.t(),
  document: PolicyDocument.t(),
  attached_agent_type: String.t()
}

# Used internally by the evaluator during decide/2
@type evaluation_source ::
  :global
  | {:document, document_id :: integer(), document_name :: String.t(),
     attached_agent_type :: String.t()}

@type evaluation_candidate :: %{
  policy: Policy.t(),
  source: evaluation_source()
}
```

`policies_for_agent_type/1` and `PolicyCache.for_agent_type/1` return `document_policy_candidate` lists. `Evaluator.decide/2` converts them into `evaluation_candidate` values before matching.

### Decision 5: `PolicyCache.for_agent_type/1` is v1, not a future optimization

One DB query per `decide/2` call does not scale under chatty sessions. The cache is extended in v1.

`PolicyCache.for_agent_type/1` always returns a list — never an error tuple. No attached documents is not exceptional:

```elixir
@spec for_agent_type(String.t()) :: [document_policy_candidate()]
# [] for an agent type with no attached documents
```

Invalidation: For v1, all successful document mutations call the existing `PolicyCache.invalidate/0`, which clears the full cache (global policies and document candidates). The function is named `invalidate/0` because that is what it does — clears everything.

### Decision 6: Document attachment activates its policy regardless of the global enabled flag

Disabled policies may remain attached to documents for organizational purposes. The policy-level `enabled` flag gates the global pool only — it does not affect document-attached policies. A disabled policy explicitly added to a document is still evaluated for agents attached to that document.

The document show page displays a single count: **policies** (all attached). The conflict heuristic (Decision 9) counts all attached policies regardless of their enabled state.

### Decision 7: `evaluated_count` counts evaluation candidates, not unique policies

`Decision.evaluated_count` reflects the number of evaluation candidates checked. The same policy appearing globally and via a document is counted twice. This is by design and reflects actual evaluation work.

### Decision 8: Tie-breaking when the same policy matches from multiple sources

If the same policy matches as both a global candidate and a document candidate, both appear in the trace. The full rank tuple for resolution:

```elixir
defp rank(%{policy: %Policy{priority: priority, id: id}, source: source}) do
  {-priority, id, source_rank(source)}
end

defp source_rank(:global), do: 0
defp source_rank({:document, _, _, _}), do: 1
```

Since `id` is the same for both candidates wrapping the same policy, `source_rank` is the effective tie-break: `:global` wins over `{:document, ...}`. All matched candidates remain visible in the trace.

### Decision 9: Conflict detection is a simple heuristic, not static analysis

Full overlap detection requires reasoning about wildcard actions, resource globs, project scope, conditions, builtin matchers, events, priority, and enabled state. That is out of scope for v1.

The UI shows an advisory notice when a document contains at least one `allow` policy and at least one `deny` policy where either action is `"*"` or both actions match exactly. All attached policies are counted (regardless of enabled state). This is a rough heuristic — the simulator is the source of truth.

Notice text:

> This document contains both allow and deny policies that may overlap. Deny rules take precedence. Use the simulator to verify exact behavior.

### Decision 10: Policy-level `agent_type` is shown but labeled in document UI

The document policy table shows the policy's `agent_type` field but labels it as "(ignored in document)". A note appears above the table:

> When policies run from a document, the policy-level agent type is bypassed. The document attachment controls which agent type these policies apply to.

---

## Data Model

> **Note**: SQL shown for schema clarity. Implement with Ecto migrations using `timestamps(type: :utc_datetime_usec)` or `timestamps(type: :utc_datetime_usec, updated_at: false)` for join tables.

### `iam_policy_documents`

```sql
CREATE TABLE iam_policy_documents (
  id          BIGSERIAL PRIMARY KEY,
  name        VARCHAR(255) NOT NULL CHECK (name <> ''),
  description TEXT,
  inserted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Case-insensitive uniqueness: prevents ReadOnly / readonly / READONLY coexisting
CREATE UNIQUE INDEX iam_policy_documents_name_ci_unique
  ON iam_policy_documents (lower(name));
```

### `iam_document_policies`

Join table — `inserted_at` only, no `updated_at`. These rows represent relationships; delete/reinsert is the update path.

```sql
CREATE TABLE iam_document_policies (
  id          BIGSERIAL PRIMARY KEY,
  document_id BIGINT NOT NULL REFERENCES iam_policy_documents(id) ON DELETE CASCADE,
  policy_id   BIGINT NOT NULL REFERENCES iam_policies(id) ON DELETE CASCADE,
  inserted_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX iam_document_policies_unique
  ON iam_document_policies (document_id, policy_id);
CREATE INDEX iam_document_policies_policy_id
  ON iam_document_policies (policy_id);
-- document_id lookup covered by the unique composite (first column)
```

### `iam_agent_type_documents`

Join table — `inserted_at` only, no `updated_at`.

```sql
CREATE TABLE iam_agent_type_documents (
  id          BIGSERIAL PRIMARY KEY,
  agent_type  VARCHAR(255) NOT NULL,
  document_id BIGINT NOT NULL REFERENCES iam_policy_documents(id) ON DELETE CASCADE,
  inserted_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Unique composite serves as constraint and covers agent_type-only lookups
CREATE UNIQUE INDEX iam_agent_type_documents_unique
  ON iam_agent_type_documents (agent_type, document_id);

-- Covers ON DELETE CASCADE and document_id-only scans (e.g. when cascading a document delete)
CREATE INDEX iam_agent_type_documents_document_id
  ON iam_agent_type_documents (document_id);
```

**Cascade behavior**:

- Deleting a document removes all `iam_document_policies` and `iam_agent_type_documents` rows via `ON DELETE CASCADE`. The underlying policies are not deleted.
- Deleting a policy removes it from all documents via cascade on `iam_document_policies`.
- Both paths require `PolicyCache.invalidate/0` after the DB operation. The existing policy delete path must be updated to call it.

---

## Elixir Schemas

Use the project's existing LiveView and context naming conventions. Module names here are canonical.

### `EyeInTheSky.IAM.PolicyDocument`

Explicit `has_many` + `through` rather than `many_to_many` — the join row is first-class (it carries its own timestamps, may gain `position`, `added_by`, etc. later).

```elixir
defmodule EyeInTheSky.IAM.PolicyDocument do
  use Ecto.Schema
  import Ecto.Changeset

  alias EyeInTheSky.IAM.{Policy, DocumentPolicy, AgentTypeDocument}

  schema "iam_policy_documents" do
    field :name, :string
    field :description, :string

    has_many :document_policies, DocumentPolicy,
      foreign_key: :document_id,
      on_replace: :delete

    has_many :policies, through: [:document_policies, :policy]

    has_many :agent_type_documents, AgentTypeDocument,
      foreign_key: :document_id

    timestamps(type: :utc_datetime_usec)
  end

  def create_changeset(doc \\ %__MODULE__{}, attrs) do
    doc
    |> cast(attrs, [:name, :description])
    |> update_change(:name, &String.trim/1)
    |> validate_required([:name])
    |> validate_length(:name, min: 1, max: 255)
    |> unique_constraint(:name,
      name: :iam_policy_documents_name_ci_unique,
      message: "already exists (case-insensitive)"
    )
  end

  def update_changeset(doc, attrs), do: create_changeset(doc, attrs)
end
```

### `EyeInTheSky.IAM.DocumentPolicy`

```elixir
defmodule EyeInTheSky.IAM.DocumentPolicy do
  use Ecto.Schema
  import Ecto.Changeset

  alias EyeInTheSky.IAM.{PolicyDocument, Policy}

  schema "iam_document_policies" do
    belongs_to :document, PolicyDocument
    belongs_to :policy, Policy

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def changeset(dp \\ %__MODULE__{}, attrs) do
    dp
    |> cast(attrs, [:document_id, :policy_id])
    |> validate_required([:document_id, :policy_id])
    |> foreign_key_constraint(:document_id)
    |> foreign_key_constraint(:policy_id)
    |> unique_constraint([:document_id, :policy_id],
      name: :iam_document_policies_unique,
      message: "policy already in document"
    )
  end
end
```

### `EyeInTheSky.IAM.AgentTypeDocument`

```elixir
defmodule EyeInTheSky.IAM.AgentTypeDocument do
  use Ecto.Schema
  import Ecto.Changeset

  alias EyeInTheSky.IAM.PolicyDocument

  schema "iam_agent_type_documents" do
    field :agent_type, :string
    belongs_to :document, PolicyDocument

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def changeset(atd \\ %__MODULE__{}, attrs) do
    atd
    |> cast(attrs, [:agent_type, :document_id])
    |> update_change(:agent_type, &String.trim/1)
    |> validate_required([:agent_type, :document_id])
    |> validate_length(:agent_type, min: 1, max: 255)
    |> validate_exclusion(:agent_type, ["*"], message: "cannot be wildcard")
    |> foreign_key_constraint(:document_id)
    |> unique_constraint([:agent_type, :document_id],
      name: :iam_agent_type_documents_unique,
      message: "document already attached to this agent type"
    )
  end
end
```

---

## Context Module (`EyeInTheSky.IAM`) — New Functions

```elixir
# Documents
list_policy_documents() :: [PolicyDocument.t()]
get_policy_document(id, opts \\ []) :: {:ok, PolicyDocument.t()} | {:error, :not_found}
# Show page: get_policy_document(id, preload: [:document_policies, :agent_type_documents])
# document_policies must be preloaded with their :policy association for the UI table

create_policy_document(attrs) :: {:ok, PolicyDocument.t()} | {:error, Ecto.Changeset.t()}
update_policy_document(doc, attrs) :: {:ok, PolicyDocument.t()} | {:error, Ecto.Changeset.t()}
delete_policy_document(doc) :: {:ok, PolicyDocument.t()} | {:error, Ecto.Changeset.t()}

# Policy membership
add_policy_to_document(document_id, policy_id) ::
  {:ok, DocumentPolicy.t()}
  | {:error, :document_not_found | :policy_not_found | :already_attached | Ecto.Changeset.t()}

remove_policy_from_document(document_id, policy_id) ::
  :ok | {:error, :not_found}

# Agent type assignments
list_agent_types_with_documents() :: [{agent_type :: String.t(), [PolicyDocument.t()]}]

attach_document_to_agent_type(agent_type, document_id) ::
  {:ok, AgentTypeDocument.t()}
  | {:error, :document_not_found | :already_attached | Ecto.Changeset.t()}

attach_documents_to_agent_type(agent_type, document_ids :: [integer()]) ::
  {:ok, count :: non_neg_integer()}
  | {:error, term()}
# Transactional multi-attach; already-attached documents are no-op (idempotent).
# Returns count of newly attached; invalidates cache on success only.

detach_document_from_agent_type(agent_type, document_id) ::
  :ok | {:error, :not_found}

# Evaluator lookup — always returns a list, never an error tuple
policies_for_agent_type(agent_type :: String.t()) :: [document_policy_candidate()]
```

**Membership function implementation pattern** (for `add_policy_to_document` and `attach_document_to_agent_type`):

1. Check document exists — return `{:error, :document_not_found}` if not
2. Check policy exists where applicable — return `{:error, :policy_not_found}` if not
3. Insert join row inside `Repo.transaction`
4. Map `unique_constraint` violation to `{:error, :already_attached}`
5. Call `PolicyCache.invalidate/0` after successful DB write, before returning `{:ok, ...}`

Pre-checks before the insert are acceptable for v1. Constraint violations handle the race case.

**Invalidation timing**: `PolicyCache.invalidate/0` is called only after the DB write succeeds, before returning success. A failed mutation does not invalidate the cache.

---

## Hook Payload Enrichment

Claude Code hook payloads do not include `agent_type` — only the `session_id` (UUID). The IAM controller (`POST /api/v1/iam/decide`) enriches the payload by resolving the agent type from the session record before evaluation.

**Lookup path**: `Sessions.agent_type_for_session(uuid)` → query the session, join to its agent record, join to agent_definition, select the definition's slug.

**Why**: Document-based policies scope by agent type. Without this enrichment, the evaluator would have no agent type to match against when loading document candidates, and document policies would never fire on hooks.

**Implementation**: `IAMController.enrich_agent_type/1` runs before `Normalizer.from_hook_payload/1`. It uses `Map.put_new` so any explicit `agent_type` in the payload wins (defensive for unexpected callers).

---

## Evaluation Candidates

### Building candidates in `Evaluator.decide/2`

```elixir
def decide(%Context{} = ctx, opts \\ []) do
  policies =
    case Keyword.fetch(opts, :policies) do
      {:ok, list} -> list
      :error -> PolicyCache.all_enabled()
    end

  # opts[:policies] overrides only the global pool.
  # Document candidates are still loaded from PolicyCache.for_agent_type/1
  # unless opts[:document_candidates] is provided.
  # This lets tests inject either pool independently.
  doc_candidates_raw =
    case Keyword.fetch(opts, :document_candidates) do
      {:ok, list} -> list
      :error ->
        # Normalizer converts blank agent_type to nil.
        # Guard ensures only concrete non-wildcard strings trigger the lookup.
        if is_binary(ctx.agent_type) and ctx.agent_type not in ["", "*"] do
          PolicyCache.for_agent_type(ctx.agent_type)
        else
          []
        end
    end

  global_candidates =
    Enum.map(policies, &%{policy: &1, source: :global})

  document_candidates =
    Enum.map(doc_candidates_raw, fn %{policy: p, document: doc, attached_agent_type: at} ->
      %{policy: p, source: {:document, doc.id, doc.name, at}}
    end)

  # No dedup — same policy from two sources = two trace entries (intentional)
  all_candidates = global_candidates ++ document_candidates

  matches = Enum.filter(all_candidates, &candidate_matches?(&1, ctx))

  {denies, allows, instructs} = partition_by_effect(matches)
  {permission, winner, winner_source, default?} = resolve_permission(denies, allows, :allow)
  # ... rest unchanged except winner carries source
end
```

### `candidate_matches?/2` and agent-type bypass

```elixir
defp candidate_matches?(%{policy: policy, source: source}, %Context{} = ctx) do
  trace_policy(policy, ctx, source: source) == :ok
end
```

`agent_matches?` receives source:

```elixir
# Document-sourced: bypass policy-level agent_type entirely
defp agent_matches?(_policy, _ctx, {:document, _, _, _}), do: true

# Global: existing behavior
defp agent_matches?(%Policy{agent_type: "*"}, _ctx, :global), do: true
defp agent_matches?(%Policy{agent_type: at}, %Context{agent_type: at}, :global), do: true
defp agent_matches?(_, _, :global), do: false
```

All other axes — event, action, project, resource, condition, builtin matcher — apply regardless of source.

### Rank and tie-breaking

```elixir
defp rank(%{policy: %Policy{priority: priority, id: id}, source: source}) do
  {-priority, id, source_rank(source)}
end

defp source_rank(:global), do: 0
defp source_rank({:document, _, _, _}), do: 1
```

Since `id` is the same for both candidates wrapping the same policy record, `source_rank` is the effective tie-break: `:global` wins.

### Source label helper

To avoid tuple-format leakage into LiveView and trace rendering code, provide a helper:

```elixir
defmodule EyeInTheSky.IAM.EvaluationSource do
  def label(:global), do: "global"
  def label({:document, _id, name, agent_type}), do: ~s(document "#{name}" → #{agent_type})
end
```

Use this wherever source is displayed, not raw tuple matching.

### `Decision` struct additions

```elixir
%Decision{
  permission: :deny,
  winning_policy: policy,
  winning_source: "global" | "document \"Name\" → agent_type" | nil,
  # String source label via EvaluationSource.label/1; nil when decision is a fallback
  reason: "...",
  instructions: [%{policy: p, message: msg, source: source}],
  default?: false,
  evaluated_count: 14  # count of candidates checked, not unique policy records
}
```

**Audit field**: `iam_decisions.winning_source` records the evaluation source label string for audit and trace output. See [EvaluationSource](#source-label-helper) for label format.

---

## Trace Output

Every candidate in the simulator trace includes source via `EvaluationSource.label/1`:

```
policy "Block git push"    deny    MATCHED   global
policy "Block sudo"        deny    skipped   global                               miss: resource
policy "Block write"       deny    MATCHED   document "NoDeployments" → code-reviewer
policy "Allow Read"        allow   skipped   document "ReadOnly" → code-reviewer   miss: event
```

A deny decision:

```
Denied by: "Block git push"
Source: document "NoDeployments" (attached to agent type: "code-reviewer")
```

---

## UI Pages

Follow the project's existing LiveView naming convention. Route names below are conceptual.

### Page structure

```
/iam/documents                         — list
/iam/documents/new                     — create (name + description only)
/iam/documents/:id                     — show (membership + agent type assignments)
/iam/documents/:id/edit                — edit (name + description only)
/iam/agent-types                       — index (derived from iam_agent_type_documents)
/iam/agent-types/show?agent_type=...   — detail (query param avoids routing edge cases)
```

### `/iam/documents` — List

Columns: name, description, effective policy count, attached agent types, actions (show, edit, delete).

Delete confirmation: "Deleting this document removes it from N agent types. The underlying policies are not deleted."

### `/iam/documents/new` and `/iam/documents/:id/edit`

Only name and description. Policy membership and agent type assignments live on the show page.

### `/iam/documents/:id` — Show

**Header note:**

> When policies run from a document, the policy-level agent type is bypassed. The document attachment controls which agent type these policies apply to.

**Policies in this document**

Two counts in the section header: "8 attached / 6 effective" (effective = enabled only).

Table columns: name, effect, action, agent type (labeled "agent type — ignored in document"), enabled, remove.

Search/filter. "Add policy" opens a searchable modal.

**Conflict notice** (only enabled allow + enabled deny with matching or wildcard action; disabled policies not counted):

> This document contains both allow and deny policies that may overlap. Deny rules take precedence. Use the simulator to verify exact behavior.

**Attached agent types**

List of agent type strings with remove buttons. Text input to attach a new agent type (trimmed, `"*"` rejected). Link to detail page per entry.

**Actions**: "Test in simulator" → `/iam/simulator?agent_type=X` (first attached agent type), Edit, Delete.

### `/iam/agent-types` — Index

Derived from `list_agent_types_with_documents/0`. Columns: agent type, attached document names, effective policy count. "Add agent type" opens an inline form: agent type text input + document multi-select.

### `/iam/agent-types/show?agent_type=code-reviewer` — Detail

- Agent type string (read-only display)
- Attached documents with remove buttons
- "Attach document" dropdown
- Effective policy count
- "Test in simulator" link

---

## Router Changes

```elixir
live "/iam/documents", IAMLive.PolicyDocuments, :index
live "/iam/documents/new", IAMLive.PolicyDocumentNew, :new
live "/iam/documents/:id", IAMLive.PolicyDocumentShow, :show
live "/iam/documents/:id/edit", IAMLive.PolicyDocumentEdit, :edit
live "/iam/agent-types", IAMLive.AgentTypes, :index
live "/iam/agent-types/show", IAMLive.AgentTypeShow, :show  # ?agent_type= query param
```

All within existing `:app` live_session.

---

## Rail Menu

```
IAM
  Policies          /iam/policies
  Documents         /iam/documents
  Agent Types       /iam/agent-types
  Simulator         /iam/simulator
```

---

## Simulator Changes

`Simulator.simulate/2` result gains a `document_contributions` field:

```elixir
%{
  decision: Decision.t(),
  traces: [trace()],           # each trace includes :source via EvaluationSource.label/1
  winner_id: integer() | nil,
  fallback?: boolean(),
  document_contributions: [
    %{
      document_id: integer(),
      document_name: String.t(),
      agent_type: String.t(),
      effective_policy_count: integer()
    }
  ]
}
```

The simulator UI shows a "Document contributions" section above the trace table when the agent type has attached documents. The simulator accepts `?agent_type=` query params via `handle_params` and pre-fills the form field.

---

## Migration

Single migration file covering all three tables and indexes. Use `timestamps(type: :utc_datetime_usec)` for `iam_policy_documents` and `timestamps(type: :utc_datetime_usec, updated_at: false)` for both join tables.

No data migration needed — documents start empty.

---

## Seed Documents (future path)

Not seeded in v1, but the data model supports it. Candidate profiles:

- **ReadOnly** — allow Read, Grep, Glob; deny Edit, Write, Bash
- **NoDeployments** — deny force push, kubectl/terraform apply, deploy-pattern Bash commands
- **TrustedDev** — allow everything in project; deny destructive filesystem outside cwd

---

## Open Questions (genuinely deferred)

- **Approval flows** — a document could require human approval before tool calls proceed for attached agent types. Not in scope.

---

## Related

- [IAM_POLICY.md](IAM_POLICY.md) — Core IAM system, evaluation flow, builtins
- [IAM_HOOK_INSTALL.md](IAM_HOOK_INSTALL.md) — Hook integration
