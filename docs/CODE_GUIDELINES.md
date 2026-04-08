# Eye in the Sky Web — Coding Guide

This project is a Phoenix 1.8 + LiveView + LiveSvelte + Tailwind v4 app.

This guide is the “default way we do things” so new features are consistent, testable, and safe to change.

---

## Quick Commands

- Setup: `mix setup`
- Run server: `mix phx.server`
- JS/CSS build (dev): `mix assets.build`
- JS/CSS build (prod): `mix assets.deploy`
- Test: `mix test`
- Before pushing: `mix precommit`

---

## Repo Layout (Where Code Goes)

- Domain/business logic (contexts): `lib/eye_in_the_sky_web/*`
- Web layer (controllers/components/live): `lib/eye_in_the_sky_web_web/*`
- LiveViews: `lib/eye_in_the_sky_web_web/live/*`
- Function components/layout: `lib/eye_in_the_sky_web_web/components/*`
- Frontend entrypoints:
  - JS: `assets/js/app.js`
  - CSS: `assets/css/app.css`
- Svelte components: `assets/svelte/*`
- Svelte SSR output (generated): `priv/svelte/*` (git-ignored)

Rule of thumb:
- **Contexts** talk to the DB, enforce invariants, and return domain data.
- **LiveViews** orchestrate: load data, handle events, assign state, render.
- **Components** render UI; keep them stateless when possible.

---

## Phoenix / LiveView Conventions

### Layout wrapper (required)

All LiveView templates should start with the app wrapper:

```heex
<Layouts.app flash={@flash} current_scope={@current_scope}>
  ...
</Layouts.app>
```

Notes:
- `Layouts` is already aliased by `lib/eye_in_the_sky_web_web.ex`.
- If you see “no `current_scope` assign”, the fix is **routing/session wiring**, not a random `assign/3`:
  - move the route into the correct `live_session`
  - ensure `current_scope` is assigned and passed through to `<Layouts.app>`

### Flash rendering (required)
- Phoenix v1.8 moved `<.flash_group>` to `Layouts`.
- Never call `<.flash_group>` outside `lib/eye_in_the_sky_web_web/components/layouts.ex`.

### Forms (required patterns)
- Build forms from `to_form/2` assigns.
- In templates use `<.form for={@form} ...>` and `<.input field={@form[:field]}>`.
- Always give forms stable IDs (for tests): `<.form id="project-form" ...>`.

### LiveView streams (required for collections)
Use streams for UI lists that can grow:

```elixir
socket = stream(socket, :messages, messages, reset: true)
```

```heex
<div id="messages" phx-update="stream">
  <div class="hidden only:block">No messages yet</div>
  <div :for={{id, msg} <- @streams.messages} id={id}>
    {msg.body}
  </div>
</div>
```

Do not:
- call `Enum.*` on streams
- use `phx-update="append"` / `prepend"` (deprecated)

### Side effects
LiveViews mount twice (disconnected + connected). Only do side effects when `connected?(socket)` is true:
- PubSub subscriptions
- timers
- DB writes / external calls

---

## UI / UX (Tailwind-first)

### Tailwind v4 import syntax (do not change)
Keep the Tailwind v4 directives in `assets/css/app.css`:

```css
@import "tailwindcss" source(none);
@source "../css";
@source "../js";
@source "../../lib/eye_in_the_sky_web_web";
```

### Styling rules
- Prefer Tailwind utility classes and small custom CSS rules.
- Never use `@apply`.
- Aim for polished UX:
  - consistent spacing and typography
  - hover/focus micro-interactions
  - loading/empty states

### daisyUI usage (project rule)
daisyUI is available (themes + some existing UI), but new UI should be **Tailwind-composed** and app-specific. Don’t blindly stack daisyUI component classes for new design work—use them sparingly, and keep patterns consistent with nearby UI.

### Icons (required)
Use the imported `<.icon>` component. Don’t use Heroicons modules directly.

---

## JavaScript (No Inline Scripts)

Rules:
- Only the `app.js` and `app.css` bundles are supported.
- Do not add `<script>` tags in HEEx templates.
- Do not add inline `onclick="..."` handlers in templates.
- Put JS in `assets/js/*` and import it from `assets/js/app.js`.

If a JS hook owns its DOM, the template must set `phx-update="ignore"` on the root element.

---

## LiveView Event Handling (Critical)

**Never mix vanilla JavaScript event handlers with LiveView directives** - they conflict and cause events to fail silently.

### ❌ Wrong (Causes Events to Not Fire)
```heex
<!-- onclick interferes with phx-click -->
<button phx-click="archive" onclick="event.stopPropagation()">Archive</button>

<!-- onchange interferes with phx-change -->
<input phx-change="validate" onchange="handleChange()">
```

### ✅ Correct (Use LiveView Directives)
```heex
<!-- Use phx-capture-click to prevent bubbling -->
<button phx-click="archive" phx-capture-click="true">Archive</button>

<!-- Use phx-change with LiveView hooks for custom JS -->
<input phx-change="validate" phx-hook="CustomInput">
```

### LiveView Event Directives
- `phx-capture-click="true"` - Stops event propagation (replaces `onclick="event.stopPropagation()"`)
- `phx-window-keydown` - Global keyboard events (replaces `window.addEventListener`)
- `phx-blur`, `phx-focus` - Focus events (replaces `onblur`, `onfocus`)
- `phx-hook` - For custom JavaScript behavior that needs to interact with LiveView

### Why This Matters
Vanilla JavaScript event handlers (`onclick`, `onchange`, etc.) run in the browser **before** LiveView processes the event. They can:
- Prevent LiveView events from firing
- Cause silent failures (no logs, no errors)
- Break LiveView's event system

**Rule:** If you need JavaScript behavior in a LiveView template, use `phx-hook` with a proper hook implementation in `assets/js/app.js`.

---

## LiveSvelte (Client UI Components)

### Where components live
- Svelte components: `assets/svelte/**`
- They are registered as LiveView hooks in `assets/js/app.js` using `getHooks(...)`.

### Adding a new Svelte component (checklist)
1. Create `assets/svelte/MyComponent.svelte`
2. Import it in `assets/js/app.js`
3. Register it in the `getHooks({ ... })` call
4. Use it from HEEx:

```heex
<.svelte name="MyComponent" props={%{...}} socket={@socket} />
```

### SSR output (generated)
SSR bundles output to `priv/svelte/*` and are git-ignored (`.gitignore` already includes `/priv/svelte/`).

If SSR looks “stale”, rebuild:
- `mix assets.build` (dev)
- `mix assets.deploy` (prod)

---

## Markdown Rendering (Security)

This repo uses Marked.js for rendering note markdown (see `MARKDOWN_RENDERING.md`).

Important:
- Svelte `{@html ...}` renders **raw HTML**.
- Only render trusted content, or sanitize before rendering.

If you need to render untrusted/user-supplied markdown:
- add a sanitizer (e.g., DOMPurify) and wire it through `assets/js/app.js` so it’s part of the bundle (no external scripts).

---

## HTTP Requests (Req)

Use `Req` for outbound HTTP. Avoid `:httpoison`, `:tesla`, and `:httpc`.

Guidelines:
- centralize base URLs/timeouts/retries in a small wrapper module
- don’t retry non-idempotent requests unless you’re sure it’s safe

---

## Type Signatures and Typespecs

Add `@spec` annotations to public functions in context modules for clarity and IDE/documentation support.

**Guidelines:**

### Agent Context (Agents)

All primary public functions should have `@spec` annotations:

```elixir
@spec get_agent(String.t()) :: {:ok, Agent.t()} | {:error, String.t()}
def get_agent(id) do
  # ...
end

@spec list_agents(Keyword.t()) :: [Agent.t()]
def list_agents(opts \\ []) do
  # ...
end

@spec create_agent(map()) :: {:ok, Agent.t()} | {:error, Changeset.t()}
def create_agent(attrs) do
  # ...
end
```

### Sessions Context (Sessions)

Consistent `@spec` for session operations:

```elixir
@spec get_session(integer() | String.t()) :: Session.t() | nil
def get_session(id) do
  # ...
end

@spec update_session(Session.t(), map()) :: {:ok, Session.t()} | {:error, Changeset.t()}
def update_session(session, attrs) do
  # ...
end
```

### Messages Context (Messages)

Type signatures for message operations:

```elixir
@spec add_message(Session.t(), map()) :: {:ok, Message.t()} | {:error, Changeset.t()}
def add_message(session, attrs) do
  # ...
end

@spec list_session_messages(integer()) :: [Message.t()]
def list_session_messages(session_id) do
  # ...
end
```

---

## Optional Parameter Patterns

Use `Keyword.filter/2` to simplify optional parameter handling instead of sequential `if/else` blocks.

### ❌ Before (verbose)

```elixir
def start_claude_sdk(session_id, opts \\ []) do
  args = []
  args = if Keyword.has_key?(opts, :effort), do: args ++ ["--effort-level", opts[:effort]], else: args
  args = if Keyword.has_key?(opts, :model), do: args ++ ["--model", opts[:model]], else: args
  args = if Keyword.has_key?(opts, :provider), do: args ++ ["--provider", opts[:provider]], else: args

  run_claude_cli(args)
end
```

### ✅ After (clean)

```elixir
def start_claude_sdk(session_id, opts \\ []) do
  args =
    opts
    |> Keyword.filter(fn {key, _} -> key in [:effort, :model, :provider] end)
    |> Enum.flat_map(fn {key, val} -> [flag_name(key), val] end)

  run_claude_cli(args)
end

defp flag_name(:effort), do: "--effort-level"
defp flag_name(:model), do: "--model"
defp flag_name(:provider), do: "--provider"
```

Benefits:
- **Readable**: Intent is clear (filter valid options, then map to flags)
- **Maintainable**: Adding new options doesn't require adding new if blocks
- **Safe**: Unknown options are silently filtered (no accidental passthrough)

---

## Testing (LiveView-first)

Tooling:
- Prefer `Phoenix.LiveViewTest` for LiveViews.
- Use `LazyHTML` to debug selectors (don’t assert on giant HTML strings).

Rules of thumb:
- Add stable IDs to key elements (forms, buttons, modals).
- Tests should assert outcomes (element exists, state changes, redirect) vs exact text blobs.
- Start with smoke tests (renders + key elements), then add 1 interaction per file.

---

## Context Safety Patterns

**Problem:** User input flowing through contexts can crash the server if not validated.

**Safe patterns:**

### 1. Atom Conversion (Parser Context)

**❌ Unsafe:**
```elixir
# Parser gets raw JSON from external source
def parse_message(raw_json) do
  map = Jason.decode!(raw_json)
  atom_map = for {k, v} <- map, into: %{}, do: {String.to_atom(k), v}
  # CRASH: User can pass any string as key, creating unbounded atoms
end
```

**✅ Safe:**
```elixir
def parse_message(raw_json) do
  map = Jason.decode!(raw_json)
  # Option 1: Use whitelist
  allowed_keys = [“type”, “content”, “timestamp”]
  filtered = Map.take(map, allowed_keys)

  # Option 2: Keep as strings, not atoms
  filtered
end
```

**Guideline:** Never convert untrusted strings to atoms. The atom table has no max size and can’t be garbage collected.

---

### 2. Task Context Boundary (Safe Attribute Updates)

**Problem:** Task attributes (`title`, `description`, `state_id`) come from LiveViews and may contain invalid values.

**Safe pattern:**
```elixir
# Tasks context enforces validation at the boundary
def update_task(task, attrs) do
  task
  |> Task.changeset(attrs)  # Changeset validates
  |> Repo.update()
end

# LiveView can’t bypass validation (no raw DB updates)
def handle_event(“update_title”, %{“title” => new_title}, socket) do
  Tasks.update_task(socket.assigns.task, %{title: new_title})
  # Changeset rejects invalid state_id, unknown keys, etc.
end
```

**Guideline:** All DB changes go through contexts with `changeset/2` for validation. Never bypass with raw SQL or direct struct updates.

---

### 3. Kanban LiveView State Boundary

**Problem:** User can send arbitrary `state_id` values from LiveView, potentially setting invalid states.

**Safe pattern:**
```elixir
# Validate state_id in the context, not the LiveView
def move_task(task_id, new_state_id) do
  # Check state_id is valid (1-4, not arbitrary)
  valid_states = [1, 2, 3, 4]

  case new_state_id in valid_states do
    true -> Tasks.update_task(task_id, %{state_id: new_state_id})
    false -> {:error, “invalid state”}
  end
end
```

**Guideline:** Context validates state transitions, not LiveView. LiveView is UI; context is business logic.

---

### 4. Parser Safety (Codex/Claude Output)

**Problem:** Claude output may include malformed JSON or unexpected data types.

**Safe pattern:**
```elixir
def parse_agent_response(raw_response) do
  case Jason.decode(raw_response) do
    {:ok, %{“messages” => msgs} = data} when is_list(msgs) ->
      # Only accept expected structure
      {:ok, data}

    {:ok, _unexpected} ->
      {:error, “unexpected response format”}

    {:error, reason} ->
      {:error, “invalid json: #{reason}”}
  end
end
```

**Guideline:** Always validate structure and types from external sources. Don’t assume JSON keys/types are correct.

---

### 5. QueryBuilder Field Name Validation

**Problem:** Dynamic SQL field names (from user input or configuration) can be exploited via SQL injection if not validated.

**Safe pattern:**
```elixir
# QueryBuilder.maybe_where/3 validates field names before building queries
def maybe_where(query, field_name, value) do
  # Whitelist allowed field names
  allowed_fields = ~w[title description state_id created_at last_activity_at]

  if field_name in allowed_fields do
    where(query, [{^field_name, value}])
  else
    # Reject invalid field names
    {:error, “invalid field: #{field_name}”}
  end
end

# Usage: Only pass trusted field names to dynamic queries
query = Task |> maybe_where(“title”, “bug fix”) |> Repo.all()
```

**Guideline:** Validate field names against an explicit whitelist before interpolating into SQL. Never trust user input for column names.

---

---

## Component Patterns

### Session Card Component

**Purpose:** Reusable card component for displaying session summary across multiple pages (agent_live/index, project sessions, overview).

**Location:** `lib/eye_in_the_sky_web_web/components/session_card.ex`

**Features:**
- **Title/Name:** Session name (falls back to description if name unavailable)
- **Status indicator:** Colored left border accent matching agent status (working=blue, idle=gray, waiting=yellow)
- **Agent name:** Shows active agent assigned to session
- **Last activity:** Displays last_activity_at timestamp (ISO8601 format, client-side timezone rendering)
- **Model:** Shows Claude model version used in session
- **Mobile responsive:** Hides status indicator on mobile to prevent layout clipping

**Props:**
```elixir
<.session_card
  session={@session}
  on_click={JS.navigate(...)}
  class=”optional-tailwind-classes”
/>
```

**Mobile considerations:**
- Status bullet hidden on mobile (status conveyed via border only)
- No chevron icon (mobile layout doesn't need collapse indicators)
- Full-width card for touch-friendly interaction

**Reusability patterns:**
- Used in agent_live/index (global sessions list)
- Used in project_live/sessions (project-scoped sessions)
- Used in overview (session summary cards)
- Consistent styling across all contexts

---

## Module Architecture

### Provider Strategy

**ProviderStrategy** (`lib/eye_in_the_sky/claude/provider_strategy.ex`): Handles provider-polymorphic dispatch for Claude vs Codex. Extracted to allow clean separation of provider logic.

Provider implementations:
- `ProviderStrategy.Claude` — Claude SDK stream dispatch and avatar/label rendering
- `ProviderStrategy.Codex` — Codex streaming pipeline via `CodexStreamAssembler`

Use `ProviderStrategy` when branching on `provider` field. Do not inline `if provider == "claude"` checks in LiveViews.

---

### Context Extractions (Tasks)

Contexts extracted from the monolithic `Tasks` context:

| Module | Path | Responsibility |
|--------|------|----------------|
| `WorkflowStates` | `lib/eye_in_the_sky_web/workflow_states.ex` | Kanban state definitions and transitions |
| `TaskTags` | `lib/eye_in_the_sky_web/task_tags.ex` | Tag CRUD and task-tag join table operations |
| `ChecklistItems` | `lib/eye_in_the_sky_web/checklist_items.ex` | Checklist item CRUD scoped to tasks |

These replace direct `Tasks.*` calls for tag/checklist/state operations in new code.

---

### SQL Extraction to Context Functions

**Pattern:** When query logic appears inline in a module (e.g., `CmdDispatcher`), extract it to a context function for reusability and testability.

**Examples:**
- `Messages.list_inbound_dms/2` — Extracts DM query logic with proper sorting and pagination
- `Teams.list_broadcast_targets/1` — Encapsulates team broadcast join logic

**When to extract:**
- Query is used in multiple places (DRY principle)
- Query is complex enough to warrant unit testing
- Query needs to be reused from different contexts (e.g., CmdDispatcher, LiveView, REST API)

**Benefits:**
- **Reusability:** One canonical implementation, not scattered duplicates
- **Testability:** Query behavior isolated and independently testable
- **Separation of concerns:** Query logic lives in context, not in dispatcher/controller code

**Example pattern:**
```elixir
# ❌ Avoid: Inline Ecto.Query in module
defmodule CmdDispatcher do
  def dispatch(cmd, session_id) do
    # Query embedded here
    dms = Repo.all(
      from m in Message,
      where: m.recipient_id == ^session_id,
      order_by: [desc: m.inserted_at, desc: m.id]
    )
    # ... use dms
  end
end

# ✅ Prefer: Extract to context
defmodule Messages do
  def list_inbound_dms(session_id, opts \\ []) do
    Repo.all(
      from m in Message,
      where: m.recipient_id == ^session_id,
      order_by: [desc: m.inserted_at, desc: m.id],  # secondary sort for stability
      limit: Keyword.get(opts, :limit, 50)
    )
  end
end

# Then in CmdDispatcher:
defmodule CmdDispatcher do
  def dispatch(cmd, session_id) do
    dms = Messages.list_inbound_dms(session_id)
    # ...
  end
end
```

**Secondary sort stability:** Always include a secondary sort column (e.g., `m.id`) when primary sort has potential collisions (e.g., timestamps). This ensures deterministic query results for testing.

---

### Chat Presenter

**ChatPresenter** (`lib/eye_in_the_sky_web_web/live/chat_presenter.ex`): Extracted chat presentation logic from `ChatLive`. Handles message formatting, typing indicator state, and ambient message filtering.

- Ambient channel messages no longer trigger agent responses — only `@direct` and `@all` mentions do
- Message numbering is per-channel and sequential (with backfill migration)

---

### JobsHelpers

**JobsHelpers** (`lib/eye_in_the_sky_web_web/live/shared/jobs_helpers.ex`): Unified job creation logic, replacing duplicate implementations in `OverviewLive.Jobs` and `ProjectLive.Jobs`.

Key functions:
- `create_with_claude/2` — spawns an agent to work on a job using selected model + effort level
- `save_job/2` — persists a job with validated attributes

**When to use:**
- Call `JobsHelpers.create_with_claude/2` from any LiveView that needs to spawn an agent for a job
- Do not duplicate the spawn logic inline in individual LiveViews

---

### Agent Management Modules

**AgentManager** (`lib/eye_in_the_sky_web/agents/agent_manager.ex`): Primary module for agent lifecycle management and spawning.

**Related modules:**
- **InstructionBuilder** (`lib/eye_in_the_sky_web/agents/instruction_builder.ex`): Constructs Claude SDK initialization instructions (model, effort, context, tools)
- **RuntimeContext** (`lib/eye_in_the_sky_web/agents/runtime_context.ex`): Captures agent runtime state (project path, session UUID, provider identity)
- **Git.Worktrees** (`lib/eye_in_the_sky_web/git/worktrees.ex`): Manages git worktree creation, reuse, and dirty state checking

**Agent State Lifecycle:**
- `:pending` — Initial state on :queued or :retry_queued admission (agent spawning)
- `:running` — Transitioned on SDK :started event (CLI process running)
- `:failed` — Set on dispatch error or spawn failure

**Worktree Behavior:**
- Worktrees reuse existing paths on repeated `prepare_session_worktree/2` calls
- Dirty state check filters untracked files (`git status --porcelain` with `??` filter) — untracked files are irrelevant since worktrees branch from HEAD
- Promotes agent from pending to running on successful SDK start via `promote_agent_if_pending/1` (synchronous for test sandbox safety)

---

## Model Configuration

### Supported Models and Effort Levels

**Opus models:**
- `opus` — Claude 3.5 Opus
- `opus[1m]` — Claude 4.6 Opus (1M context window)

**Sonnet models:**
- `sonnet` — Claude 3.5 Sonnet
- `sonnet[1m]` — Claude 4.5 Sonnet (1M context window)

**Effort levels:**
- `low` — Quick execution, minimal retries
- `normal` — Balanced approach (default)
- `high` — More thorough, multiple attempts
- `max` — Exhaustive effort, maximum retries

**Model display helper:**
Use `ViewHelpers.model_display_name/1` to render human-readable model names in UI:

```elixir
# In components
<%= ViewHelpers.model_display_name(“opus[1m]”) %>
# Renders: “Opus 4.6 (1M)”
```

**Budget parsing (canonical implementation):**
Use `ViewHelpers.parse_budget/1` as the single source of truth for parsing budget strings. This replaces duplicate implementations previously scattered across `ChatLive` and `AgentLive.Index`.

```elixir
# In any module
budget_value = ViewHelpers.parse_budget(“p95”)
# Returns: {:ok, 0.95} or {:error, reason}
```

**Why canonical:** Budget parsing logic is shared across multiple LiveViews and contexts. Maintaining a single implementation in `ViewHelpers` prevents inconsistencies and reduces code duplication. Always import and use this function rather than reimplementing budget logic locally.

**Available forms with model + effort selection:**
- DM page (session selector dropdown)
- New Agent drawer
- New Session modal
- Overview Jobs page
- Project Jobs page

---

## Note Creation

### Quick Note Modal

**Purpose:** Create a note with inline title/body textarea without page navigation.

**Location:** `lib/eye_in_the_sky_web_web/live/*/notes.ex` (overview_live/notes, project_live/notes)

**Features:**
- Title input field
- Body textarea
- Star toggle (optional)
- Modal submit creates note and reloads list

**Parent type resolution:**
- Overview page notes parent to `system/0`
- Project page notes parent to current project

### New Note CodeMirror Editor

**Purpose:** Dedicated page for writing markdown notes with syntax highlighting and save shortcuts.

**Features:**
- Title input field
- CodeMirror 6 markdown editor
- Cmd+S keyboard shortcut to save
- Cancel button to discard

**JavaScript hook:** `InlineNoteCreatorHook` (`assets/js/hooks/inline_note_creator.js`)

**Both buttons available on:**
- `/notes` (overview)
- `/projects/:id/notes` (project-scoped)

---

## UI Component Patterns

### Action Dropdown Menu (Session Row / Kanban Card)

Session rows and kanban cards use a `...` dropdown menu for destructive/secondary actions (rename, delete, archive) instead of inline icon buttons.

**Pattern:**
- The row/card itself is a clickable navigation target
- Secondary actions live in a `...` button that opens a dropdown
- The dropdown must call `phx-capture-click` or `JS.stop_propagation()` so clicking a menu item does **not** also trigger row navigation

**Click propagation guard (rename form):**

When an inline rename form is open inside a clickable row, stop click propagation on the form to prevent the row's navigation handler from firing:

```heex
<form
  phx-submit=”rename_session”
  phx-capture-click=”noop”
>
  <input phx-change=”update_rename_input” ... />
</form>
```

Using `phx-capture-click=”noop”` (or `JS.stop_propagation()`) ensures clicks inside the rename form don't bubble up to the row's `phx-click` handler.

### stream_insert Re-render Behavior

When using `stream_insert` to update a session row (e.g., after rename or status change), LiveView re-renders the entire stream item. This means:

- Any open state (dropdowns, inline forms) in that stream item will close on re-render
- Design flows to complete (submit or cancel) before a stream update arrives
- Use `stream_insert(socket, :sessions, updated_session)` to push updates; do NOT reset the full stream on single-item updates

---

## Kanban Card Actions (Trello-style Dropdown)

Kanban task cards use a `...` overflow menu for actions (copy, delete, move) instead of always-visible icon buttons.

**UX pattern:**
- Menu button appears on card hover (desktop) or is always visible on mobile
- Opening the menu stops click propagation so the card click (navigate to task) doesn't fire
- Consistent with the session row dropdown pattern above

---

## “Gotchas” Checklist

- If you see missing `current_scope`: fix routing/live_session + pass it to `<Layouts.app>`.
- Don’t call `<.flash_group>` outside `Layouts`.
- Don’t use `@apply` in CSS.
- Don’t add inline scripts or inline `onclick`.
- **Never convert untrusted strings to atoms** (unbounded atom table).
- **Validate state transitions in contexts, not LiveViews** (not in UI layer).
- **All DB writes through contexts with changesets** (not raw SQL from LiveView).
- Run `mix precommit` before pushing.

---

## Chat Upload Helpers Extraction

**Module:** `ChatLive.UploadHelpers` (`lib/eye_in_the_sky_web_web/live/chat_live/upload_helpers.ex`)

Extracted from `ChatLive` to isolate file upload concerns. Handles the full upload lifecycle:

- `cleanup_uploads/1` — Cancels and purges pending upload entries from the socket
- `process_accepted_entries/2` — Consumes accepted upload entries and returns attachment structs
- `process_rejected_entries/1` — Collects entries rejected by the accept filter with error reasons
- `presign_attachment/3` — Generates presigned URLs for S3/storage backend attachment uploads

**When to use:**
- Always call `UploadHelpers.cleanup_uploads/1` in the `:on_error` path to avoid stale upload state
- Use `process_accepted_entries/2` after `allow_upload` consumes entries — do not access `socket.assigns.uploads` directly
- Presigning happens via `presign_attachment/3`, not inline in `handle_event`

**Rule:** Upload lifecycle logic lives in `UploadHelpers`, not scattered across `ChatLive` event handlers.

---

## Kanban Accessibility — Column Checkbox Attribute

Kanban select-all checkboxes use `data-column-index` (not `data-column-handle`) to identify which column the checkbox belongs to.

**Why this matters:**
- `data-column-handle` is the drag-and-drop handle attribute — repurposing it for checkbox identity caused selection and accessibility bugs
- `data-column-index` is a dedicated, semantically correct attribute for column identification

**Pattern:**

```heex
<!-- ✅ Correct -->
<input type="checkbox" data-column-index={@column_index} phx-click="select_all" />

<!-- ❌ Wrong — data-column-handle is reserved for drag handles -->
<input type="checkbox" data-column-handle={@column_index} phx-click="select_all" />
```

**Rule:** Never reuse drag-and-drop attributes for non-drag purposes. Use dedicated `data-*` attributes for each concern.

---

## DateTime Helpers Consolidation

`format_relative_time/1` in `ViewHelpers` handles both `DateTime` and `NaiveDateTime` via pattern matching — no separate functions needed.

```elixir
# Both work:
format_relative_time(%DateTime{} = dt)
format_relative_time(%NaiveDateTime{} = ndt)
```

**Implementation pattern:**

```elixir
def format_relative_time(%DateTime{} = dt) do
  dt |> DateTime.to_naive() |> format_relative_time()
end

def format_relative_time(%NaiveDateTime{} = ndt) do
  # ... relative formatting logic
end
```

**Rule:** When a helper needs to accept multiple datetime types, use pattern-matched heads — do not add a separate `format_relative_time_naive/1`. Callers shouldn't have to know which type they have.

---

## Agent Task Status — Valid Enum Values

`Task.Status` does **not** include `:error`. Use `:failed` for failed task states.

**Valid statuses:**
- `:pending`
- `:running`
- `:completed`
- `:failed`

**Common mistake:**

```elixir
# ❌ Wrong — :error is not a valid Task.Status
task |> Task.changeset(%{status: :error}) |> Repo.update()

# ✅ Correct
task |> Task.changeset(%{status: :failed}) |> Repo.update()
```

**Rule:** Always use `:failed` when a task reaches an error terminal state. Using `:error` will fail changeset validation silently or raise on enum cast.

---

## Task Timestamp and UUID Injection (EITS-CMD)

When `create_task` and `update_task` directives are processed via EITS-CMD, timestamps and UUIDs are injected by the directive handler — not generated in the caller.

**Injected fields:**
- `inserted_at` / `updated_at` — set from directive processing time
- `uuid` — generated by the EITS-CMD processor if not provided

**Why this matters:**
- Directives may be batched or replayed; the processor owns canonical timestamps
- Do not set `inserted_at` manually in task creation code that goes through `CmdDispatcher`
- UUID is stable across retries — the directive processor ensures idempotency

**Pattern:**

```elixir
# ❌ Don't manually set timestamps for EITS-CMD-driven task creation
Tasks.create_task(%{title: "Fix bug", inserted_at: DateTime.utc_now()})

# ✅ Let the directive handler inject timestamps
# CmdDispatcher.handle("create_task", %{title: "Fix bug"})
# → injects inserted_at, updated_at, uuid automatically
```

**Rule:** Task creation via `EITS-CMD: task begin` or `create_task` directives must not set timestamps or UUIDs externally. The processor is authoritative.

---

## Message Validation — Palette Commands via LiveView Socket

Command palette actions that previously used `fetch()` to POST to `/api/v1` must use LiveView socket events instead.

**Why:**
- `fetch()` from client JS bypasses LiveView's session/auth context
- Input validation should happen in the LiveView handler, not client-side
- Per-user rate limiting and permission checks live in the socket's assigns

**Pattern:**

```javascript
// ❌ Wrong — fetch bypasses LiveView session
fetch("/api/v1/palette/run", {
  method: "POST",
  body: JSON.stringify({ command: input })
})

// ✅ Correct — push event through LiveView socket
this.pushEvent("palette_command", { command: input })
```

```elixir
# LiveView handler validates input before executing
def handle_event("palette_command", %{"command" => command}, socket) do
  case validate_palette_command(command) do
    {:ok, cmd} -> execute_palette_command(cmd, socket)
    {:error, reason} -> {:noreply, put_flash(socket, :error, reason)}
  end
end
```

**Rule:** All palette command execution goes through `pushEvent` + LiveView `handle_event`. No direct HTTP fetch from palette JS.

---

## Color System — Semantic Tailwind Classes

Replace hardcoded `oklch(...)` and `hsl(...)` color values with semantic Tailwind utility classes.

**Why:**
- Hardcoded `oklch`/`hsl` values break theme switching (dark mode, custom themes)
- Semantic classes (e.g., `text-primary`, `bg-base-200`, `border-base-300`) adapt automatically to the active daisyUI/Tailwind theme
- Reduces diff noise when colors are adjusted globally

**Migration pattern:**

```heex
<!-- ❌ Hardcoded oklch -->
<div style="color: oklch(0.7 0.15 250); background: hsl(220 14% 10%)">

<!-- ✅ Semantic Tailwind -->
<div class="text-primary bg-base-100">
```

**Common mappings:**
- `oklch(...)` accent colors → `text-primary`, `text-secondary`, `text-accent`
- `hsl(220 14% ...)` dark backgrounds → `bg-base-100`, `bg-base-200`, `bg-base-300`
- Border colors → `border-base-300`, `border-primary`

**Rule:** No hardcoded color functions in class attributes or inline styles. Use semantic Tailwind/daisyUI classes. If a color has no semantic equivalent, add a CSS custom property via the theme, not inline.

---

## Command Palette — Agent Management and Session Flags

> Commits 672f73e, d4c298a, 80f294d.

### Comprehensive agent management commands

The command palette includes a full set of agent lifecycle commands. When adding new agent actions, register them in the `CommandRegistry` under the `"Agent Management"` category:

```javascript
{
  id: "agent-stop",
  label: "Stop Agent",
  icon: "hero-stop",
  category: "Agent Management",
  when: (state) => state.activeAgent !== null,
  action: (state) => state.pushEvent("palette_command", { command: "stop_agent", agent_id: state.activeAgent.id })
}
```

**Rule:** All agent management palette commands push events via LiveView socket (`pushEvent`), not direct `fetch()` calls. See "Message Validation — Palette Commands via LiveView Socket" above.

### Server-side session flags from CLI flags

Session flags passed via CLI (`--effort-level`, `--model`, `--worktree`, etc.) are now captured server-side and stored on the session record at spawn time. The palette can read these flags from `session.flags` without re-parsing CLI args on the client.

**When adding new CLI flags for spawned agents:**
1. Add the flag to `Claude.CLI.build_args/2` (or `Codex.CLI` equivalent)
2. Parse it in `Sessions.extract_flags/1` and merge into `session.flags`
3. The palette's session submenu will pick up the flag automatically

**Do not** re-parse CLI flag strings on the client side; read from the session record's `flags` map.

---

## Tagged Tuple Returns for Context Lookups

Context `get_*` functions return `{:ok, record}` or `{:error, :not_found}` instead of `record | nil`. This makes error handling explicit at call sites and eliminates silent nil propagation.

**Why:** Bare `nil` returns force callers to add `if` guards and make it easy to forget a nil check, leading to `(FunctionClauseError) no function clause matching in ...` crashes downstream. Tagged tuples make the caller handle both paths via `case` or `with`, and the compiler/dialyzer can verify exhaustive matching.

**Affected functions:**
- `Accounts.get_user/1`
- `Projects.get_project/1`
- `Tasks.get_task/1`
- `Notes.get_note/1`
- `Teams.get_team/1`, `Teams.get_team_by_name/1`
- `Prompts.get_prompt/1`
- `ChecklistItems.get_checklist_item/1`

### Before / After

```elixir
# Before: nil return
def get_user(id) do
  Repo.get(User, id)
end

# After: tagged tuple
def get_user(id) do
  case Repo.get(User, id) do
    nil -> {:error, :not_found}
    user -> {:ok, user}
  end
end
```

### Caller Changes

```elixir
# Before: nil check
user = Accounts.get_user(id)
if user do
  # use user
else
  # handle missing
end

# After: pattern match
case Accounts.get_user(id) do
  {:ok, user} -> # use user
  {:error, :not_found} -> # handle missing
end
```

### LiveView Event Handlers

```elixir
def handle_event("select_project", %{"id" => id}, socket) do
  case Projects.get_project(id) do
    {:ok, project} ->
      {:noreply, assign(socket, :project, project)}

    {:error, :not_found} ->
      {:noreply, put_flash(socket, :error, "Project not found")}
  end
end
```

### API Controllers

```elixir
def show(conn, %{"id" => id}) do
  case Tasks.get_task(id) do
    {:ok, task} ->
      json(conn, %{data: task})

    {:error, :not_found} ->
      conn |> put_status(:not_found) |> json(%{error: "not found"})
  end
end
```

### With Chains

Tagged tuples compose cleanly in `with` blocks:

```elixir
with {:ok, user} <- Accounts.get_user(user_id),
     {:ok, project} <- Projects.get_project(project_id),
     {:ok, task} <- Tasks.create_task(%{user_id: user.id, project_id: project.id}) do
  {:ok, task}
else
  {:error, :not_found} -> {:error, "resource not found"}
  {:error, changeset} -> {:error, changeset}
end
```

### Bang Variants

For internal code paths where the record must exist (preloaded associations, known IDs), bang variants like `get_project!/1` still raise on missing records. Use the tagged tuple version at boundaries (user input, API params, event handlers).

**Rule:** New context `get_*` functions must return `{:ok, record} | {:error, :not_found}`. Reserve `get_*!/1` for internal paths where absence is a bug, not a user error.

> Commits: 625655a, 96ce027, 2827d63, 0949e18, ee3e586

### Deduplicated SQL fragments for task title queries

Task title search fragments are defined once in the `Tasks` context and reused across the command palette's task search, the kanban filter, and the REST API. Do not inline `ILIKE` or `ts_query` fragments in palette-specific code.

```elixir
# ✅ Use the shared fragment
Tasks.title_search_query(base_query, search_term)

# ❌ Don't re-implement inline
from t in Task, where: ilike(t.title, ^"%#{term}%")
```

The canonical implementation lives in `Tasks.title_search_query/2`. Adding a second `ILIKE` path causes desynced behavior when the search strategy changes (e.g., switching to prefix `tsquery`).

---

## CodeMirror User Settings (Tab Size, Font Size, Vim Mode)

CodeMirror editor settings are user-configurable and persisted in `localStorage`.

**Configurable settings:**
- **Tab size** — number of spaces per tab (default: 2)
- **Font size** — editor font size in px (default: 14)
- **Vim mode** — enables vim keybindings (default: false)

**Storage keys:**
```javascript
localStorage.getItem("codemirror_tab_size")   // "2" | "4" | "8"
localStorage.getItem("codemirror_font_size")  // "12" | "14" | "16" | "18"
localStorage.getItem("codemirror_vim_mode")   // "true" | "false"
```

**Hook integration:**
Settings are read in the `CodeMirrorHook` mounted callback and applied to the editor instance. Changes from the settings UI push to `localStorage` and call `view.dispatch(reconfigure(...))` to apply live.

**Rule:** Do not hardcode tab size, font size, or vim mode in the CodeMirror extension config. Always read from `localStorage` with a sensible default. Settings UI toggles must write to `localStorage` before dispatching the reconfiguration.

