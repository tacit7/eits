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

## “Gotchas” Checklist

- If you see missing `current_scope`: fix routing/live_session + pass it to `<Layouts.app>`.
- Don’t call `<.flash_group>` outside `Layouts`.
- Don’t use `@apply` in CSS.
- Don’t add inline scripts or inline `onclick`.
- **Never convert untrusted strings to atoms** (unbounded atom table).
- **Validate state transitions in contexts, not LiveViews** (not in UI layer).
- **All DB writes through contexts with changesets** (not raw SQL from LiveView).
- Run `mix precommit` before pushing.

