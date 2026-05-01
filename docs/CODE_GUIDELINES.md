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

### Icon Sizing Convention (size-N)
Use Tailwind’s `size-N` shorthand for icons. Replace paired `w-N h-N` patterns with single `size-N` class:

```heex
<!-- ❌ Avoid paired widths/heights -->
<.icon name="hero-chevron-right" class="w-4 h-4" />

<!-- ✅ Use size-N shorthand -->
<.icon name="hero-chevron-right" class="size-4" />
```

Supported sizes: `size-3`, `size-3.5`, `size-4`, `size-5`, `size-6` (and any Tailwind spacing value).

**Rule:** Use `size-N` for all square dimensions. Never mix `w-N` and `h-N` when sizing icons.

### Typography Token Sizes
Three new named typography tokens replace hardcoded px values:

| Token | Size | Use Case |
|-------|------|----------|
| `text-mini` | 11px | Top-bar pills, detail labels |
| `text-micro` | 10px | Mono compact output, tool results |
| `text-nano` | 9px | Badge counts, kbd hints, section headers |

Use these instead of `text-[11px]`, `text-[10px]`, `text-[9px]`:

```heex
<!-- ❌ Hardcoded pixel values -->
<span class="text-[11px]">Label</span>

<!-- ✅ Use named tokens -->
<span class="text-mini">Label</span>
```

**Rule:** Replace all hardcoded small text sizes with the named tokens. The mapping is defined in `assets/css/app.css` via `@theme` directives.

### Focus Ring Utility
Use the `.focus-ring` utility for keyboard focus styling instead of repeating `focus-visible` patterns:

```heex
<!-- ❌ Repeated focus-visible pattern -->
<button class="focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary focus-visible:ring-offset-1">
  Action
</button>

<!-- ✅ Use .focus-ring utility -->
<button class="focus-ring">Action</button>
```

Defined in `assets/css/app.css`. Includes `ring-offset-1` on no-suffix variant; `ring-inset` variants retain modifier flexibility.

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

## Exception Handling Best Practices

**Problem:** Bare `rescue` clauses hide unexpected errors and make debugging difficult.

**Pattern (commit b535769e):** Always rescue specific exception types. Narrow bare `rescue _` to expected exceptions only.

**Specific exception types by layer:**

| Layer | Exception Type | Reason |
|-------|---|---|
| Terminal/PTY | `ErlangError` | Raised by `:erlexec.stop/1` when process is dead |
| System commands | `ErlangError` | Raised by `System.cmd/3` on exec failure |
| Database | `DBConnection.ConnectionError` \| `Postgrex.Error` | Connection issues or query syntax errors |
| File I/O | `File.Error` | Missing files, permission denied |

**Before (Antipattern):**
```elixir
# ❌ Bare rescue hides real errors (typos, unexpected exceptions)
try do
  :erlexec.stop(pid)
rescue
  _ -> :ok  # Could be ArgumentError (typo), Badmatch, etc.
end
```

**After (Safe):**
```elixir
# ✅ Specific rescue for expected error
try do
  :erlexec.stop(pid)
rescue
  ErlangError -> :ok  # Process was already dead, which is fine
end

# When multiple exceptions are possible, list all of them
try do
  Postgrex.query(conn, sql, params)
rescue
  DBConnection.ConnectionError ->
    Logger.warning("DB connection lost")
    {:error, :connection_lost}
  Postgrex.Error ->
    Logger.warning("Query failed")
    {:error, :query_failed}
end
```

**Examples from codebase (commit b535769e):**
- `pty_server.ex` — rescue `ErlangError` when calling `:erlexec.stop/1` on a dead process
- `block_work_on_main.ex` — rescue `ErlangError` from `System.cmd/3` failure + log warning
- `block_push_master.ex` — rescue `ErlangError` from `System.cmd/3` failure + log warning
- `project_identity.ex` — rescue `DBConnection.ConnectionError | Postgrex.Error` with logging

**Rule:** Never use bare `rescue _`. Always specify the exception type(s) you expect. Add a `Logger.warning/1` for unexpected failures to enable debugging.

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

## Canonical UI Components (Tier 1)

The following components are the canonical, app-wide implementations. Use these whenever the use case fits; do not create duplicates or project-specific variants.

| Component | Module | Purpose |
|-----------|--------|---------|
| `<.status_dot>` | `CoreComponents` | Colored status indicator dot (small circle) |
| `<.status_badge>` | `CoreComponents` | Status badge with label and color (larger than dot) |
| `<.search_bar>` | `CoreComponents` | Text input with magnifying glass icon, clear button |
| `<.spinner>` | `CoreComponents` | Loading spinner (size: `sm`, `md`, `lg`) |
| `<.skeleton_row>` | `CoreComponents` | Placeholder skeleton for list items (loading state) |
| `<.kbd>` | `CoreComponents` | Keyboard key display (`<Cmd>`, `<Shift>`, etc.) |
| `<.tab_pills>` | `CoreComponents` | Pill-style tab navigation (horizontal list) |
| `<.side_drawer>` | `CoreComponents` | Right-side slide-over panel with backdrop |
| `<.icon_button>` | `CoreComponents` | Icon-only button with optional tooltip and hover reveal |
| `<.form_actions>` | `CoreComponents` | Submit/Cancel footer for forms |
| `<.empty_state>` | `CoreComponents` | Centered empty state with icon, title, description |

**Adoption pattern:** When building UI, check if a Tier 1 component matches before designing custom markup. Tier 1 components handle accessibility, theming, and mobile responsiveness consistently.

### Status Dot & Status Badge

Use `<.status_dot>` for small inline status indicators (in lists, chips):

```heex
<!-- Status indicator with color based on status -->
<.status_dot status="working" class="mr-2" />

<!-- Inside a row -->
<div class="flex items-center gap-2">
  <.status_dot status="idle" />
  <span><%= @session.name %></span>
</div>
```

Use `<.status_badge>` for larger status displays with label:

```heex
<.status_badge status="completed" label="Done" />
```

Valid statuses: `"working"`, `"idle"`, `"waiting"`, `"failed"`, `"completed"`. Colors adapt to theme automatically.

### Search Bar Component

Standardized search input with icon and clear button:

```heex
<.search_bar
  id="task-search"
  placeholder="Search tasks..."
  phx-change="search_change"
  value={@search_query}
/>
```

Attributes: `id`, `placeholder`, `value`, `phx-change`, `phx-keydown`, `class` (additional Tailwind classes).

### Spinner Component

Loading indicator with configurable size:

```heex
<div class="flex items-center justify-center gap-2">
  <.spinner size="md" />
  <span>Loading...</span>
</div>
```

Sizes: `"sm"` (16px), `"md"` (24px), `"lg"` (32px). Default is `"md"`.

### Skeleton Row Component

Placeholder for list items during loading:

```heex
<div phx-update="ignore">
  <.skeleton_row />
  <.skeleton_row />
  <.skeleton_row />
</div>
```

Use `phx-update="ignore"` on the container to prevent LiveView from morphing the skeleton state.

### Keyboard Key Display (KBD)

Display keyboard combinations in help text:

```heex
<span>Press <.kbd key="Cmd" /> + <.kbd key="K" /> to open the palette</span>
```

Renders styled `<kbd>` element with proper border and background.

### Tab Pills Navigation

Horizontal tab list with pill-style appearance:

```heex
<.tab_pills
  options={[
    {label: "All", value: "all", active: @filter == "all"},
    {label: "Active", value: "active", active: @filter == "active"},
    {label: "Done", value: "done", active: @filter == "done"}
  ]}
  on_change="filter_change"
/>
```

Each option is a tuple: `{label: string, value: term, active: boolean}`. Calls `handle_event("filter_change", %{"value" => value}, socket)` when a tab is clicked.

### Side Drawer Component

Right-side slide-over panel with backdrop, commonly used for task details, forms, filters:

```heex
<.side_drawer
  id="task-detail-drawer"
  on_close={JS.push("close_drawer")}
  surface={false}
  max_width="md"
>
  <h2>Task Details</h2>
  <!-- drawer content -->
</.side_drawer>
```

**Attributes:**
- `on_close` — LiveView event or JS command to fire when backdrop or close button clicked
- `surface={true}` — add surface/container background color (used in filters, jobs form)
- `max_width` — max-width class: `"xs"`, `"sm"`, `"md"` (default), `"lg"`, `"2xl"`
- `:rest` — passed through (e.g., `phx-hook="DrawerSwipeClose"` for mobile swipe-to-close)

The drawer automatically includes a backdrop that's clickable to close. Use `phx-hook` for advanced interactions like swipe detection.

### Icon Button Component

Icon-only button with optional tooltip and hover reveal:

```heex
<!-- Simple icon button -->
<.icon_button icon="hero-pencil" phx-click="edit" />

<!-- With tooltip -->
<.icon_button
  icon="hero-information-circle"
  tooltip="Click for more info"
  phx-click="show_info"
/>

<!-- With hover reveal (hidden until parent hover) -->
<div class="group">
  <span>Item</span>
  <.icon_button
    icon="hero-trash"
    hover_group="group"
    phx-click="delete"
  />
</div>
```

**Attributes:**
- `icon` — Heroicon name (required)
- `tooltip` — Optional tooltip text (wrapped in DaisyUI tooltip component)
- `hover_group` — CSS class name for hover reveal (e.g., `"group"`, `"group/row"`)
- `phx-click` — LiveView event
- `class` — Additional Tailwind classes

When `hover_group` is provided, the button uses `opacity-0 group-hover:opacity-100` to hide until parent hover.

### Form Actions Footer

Standard submit/cancel footer for forms:

```heex
<.form_actions
  submit_label="Save"
  cancel_label="Cancel"
  loading={@loading}
  on_cancel={JS.push("cancel")}
/>
```

Places buttons in a sticky footer with proper spacing. Applies `disabled` attribute when `loading={true}`.

### Empty State Component

Centered empty state with optional icon, title, and subtitle:

```heex
<.empty_state
  title="No tasks yet"
  description="Create your first task to get started"
/>

<!-- With custom icon -->
<.empty_state
  title="No results"
  description="Try a different search term"
>
  <:icon_slot>
    <.icon name="hero-magnifying-glass" class="size-8" />
  </:icon_slot>
</.empty_state>

<!-- With subtitle slot -->
<.empty_state title="Session archived">
  <:subtitle_slot>
    <p class="text-sm text-base-500">
      This session is no longer active but you can <a href="#" class="link">view the history</a>.
    </p>
  </:subtitle_slot>
</.empty_state>
```

**Slots:**
- `:icon_slot` — Optional custom icon (default is generic empty icon)
- `:subtitle_slot` — Optional extra content below the description

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

### Rail Sub-Components

**Pattern (commit 3b0ca35c):** The sidebar `Rail` component was refactored from a monolithic 967-line file into focused sub-components. Each panel owns its section's content, filtering logic, and action buttons.

**Extracted sub-components:**

| Module | Path | Responsibility |
|--------|------|----------------|
| `Rail.FilePanel` | `lib/eye_in_the_sky_web_web/components/rail/file_panel.ex` | File tree rendering, expand/collapse state, path display |
| `Rail.Loader` | `lib/eye_in_the_sky_web_web/components/rail/loader.ex` | Agents list: filtering, sorting, search integration |
| `Rail.ProjectActions` | `lib/eye_in_the_sky_web_web/components/rail/project_actions.ex` | Project section header, create/manage buttons |
| `Rail.SectionActions` | `lib/eye_in_the_sky_web_web/components/rail/section_actions.ex` | Section-level actions: collapse, sort options |
| `Rail.FileActions` | `lib/eye_in_the_sky_web_web/components/rail/file_actions.ex` | File-level actions: open, rename, delete dropdowns |
| `Rail.FilterActions` | `lib/eye_in_the_sky_web_web/components/rail/filter_actions.ex` | Filter/search controls and display state |

**Why this pattern:**
- **Focused components:** Each sub-component handles one panel's lifecycle (mount, filtering, sorting, rendering)
- **Reusability:** Panel logic can be tested and reused independently
- **Maintainability:** Changes to file tree rendering don't affect agent filtering logic
- **Separation of concerns:** Action buttons, filtering, and content rendering are separated

**Usage in main Rail component:**

```elixir
# Main Rail orchestrates sub-components
def render(assigns) do
  ~H"""
  <.file_panel project={@project} ... />
  <.loader agents={@agents} selected_id={@selected_id} ... />
  <.project_actions project={@project} ... />
  """
end
```

**Result:** Monolithic 967-line `Rail.ex` → 466 lines + 621 lines distributed across sub-modules.

---

### DM Message Component Consolidation

**Pattern (commit 10d75ff3):** When a message-rendering component is duplicated across 2+ contexts with size variations, extract it into a shared component with `compact` and `extra_id` attrs instead of maintaining parallel copies.

**Location:** `lib/eye_in_the_sky_web_web/components/dm_message_components.ex`

`message_body/1` and `tool_result_body/1` accept:
- `compact` (boolean) — switches to condensed sizing for canvas chat windows
- `extra_id` (string) — disambiguates DOM IDs when the same message renders in multiple places

**Consumers:**
- DM page (`MessagesTab`) — default (non-compact) layout
- Canvas chat (`ChatWindowComponent`) — passes `compact={true}` for tighter window sizing

Removed duplicates: `chat_message_body` and `chat_tool_result_body` from `ChatWindowComponent`; private copies from `MessagesTab`.

**When to apply:** Component is reused across 2+ contexts, and the only meaningful difference is size/density. Do not branch on layout via `if @page == :dm` inside the component — use a neutral `compact` flag.

---

### Form Actions Adoption Pattern

Replace inline submit/cancel button pairs with the canonical `<.form_actions>` component. This ensures consistent spacing, theming, and loading state handling across all forms.

**Before (inline buttons):**
```heex
<.form for={@form} phx-submit="save">
  <.input field={@form[:title]} />
  
  <div class="flex gap-2 mt-4">
    <.button type="submit" loading={@saving}>Save</.button>
    <.button type="button" secondary phx-click="cancel">Cancel</.button>
  </div>
</.form>
```

**After (using form_actions):**
```heex
<.form for={@form} phx-submit="save">
  <.input field={@form[:title]} />
  
  <.form_actions
    submit_label="Save"
    cancel_label="Cancel"
    loading={@saving}
    on_cancel={JS.push("cancel")}
  />
</.form>
```

**Benefits:**
- Consistent button styling and spacing across all forms
- Built-in loading state handling (disables submit, shows spinner)
- Proper footer positioning (sticky if needed)
- Keyboard shortcut integration (Escape to cancel)

**Rule:** All forms in new code must use `<.form_actions>` for their submit/cancel buttons. Do not create inline button layouts.

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

### Context Extractions (Messages)

The `Messages` context was refactored into sub-modules for clarity and testability (commit 6ee2d5b6):

| Module | Path | Responsibility |
|--------|------|----------------|
| `Messages.Listings` | `lib/eye_in_the_sky/messages/listings.ex` | Query builders for message listing, filtering, pagination |
| `Messages.Search` | `lib/eye_in_the_sky/messages/search.ex` | Full-text search via PgSearch, prefix-aware tsquery |

The main `Messages` module now documents sub-module locations in its module doc:

```elixir
@moduledoc """
The Messages context for managing agent-user messaging.

Query/listing helpers live in `Messages.Listings`.
Full-text search lives in `Messages.Search`.
"""
```

**API Controllers** were also split for clarity (commit 6ee2d5b6):
- `ChannelController` — channel CRUD operations
- `ChannelMessageController` — message send/edit/delete for channels
- `MessageSearchController` — full-text search endpoint

**Why this pattern:**
- **Query isolation:** Listing logic (`from`, `where`, `order_by`, preload) lives in one module, searchable and testable
- **Search specialization:** Complex search logic (tsquery, rank, highlighting) is separate from standard CRUD
- **API clarity:** Each controller owns one domain (channels, messages, search), not a single monolithic `MessagingController`
- **Reusability:** Listing queries are shared between REST API, LiveView, and CLI commands

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

### Scheduler and Context Separation

**Problem:** Scheduler modules (e.g., `AgentStatusScheduler`) that contain direct `Repo` calls or inline `Ecto.Query` logic leak implementation details into job orchestration code. This makes schedulers harder to test, harder to reuse, and tightly coupled to schema internals.

**Solution:** Move all query logic to context functions. Schedulers should only orchestrate (decide *when* and *what* to run), never *how* data is fetched or mutated.

**Example:**

```elixir
# ❌ Before: Direct Repo/schema queries in scheduler
defmodule AgentStatusScheduler do
  def check_agents do
    agents = Repo.all(
      from a in Agent,
      where: a.status == "working",
      where: a.last_heartbeat_at < ago(5, "minute")
    )

    Enum.each(agents, fn agent ->
      agent |> Ecto.Changeset.change(%{status: "idle"}) |> Repo.update()
    end)
  end
end

# ✅ After: Delegate to context functions
defmodule AgentStatusScheduler do
  def check_agents do
    Agents.list_agents_pending_status_check()
    |> Enum.each(&Agents.archive_agent(&1, "heartbeat_timeout"))
  end
end
```

**Context functions created in this refactor (commit 9a0bc21):**

| Function | Context | Purpose |
|----------|---------|---------|
| `Agents.list_agents_pending_status_check/0` | Agents | Agents needing status review |
| `Agents.archive_agent/2` | Agents | Archive agent with reason |
| `Sessions.list_idle_sessions_older_than/1` | Sessions | Idle sessions past threshold |
| `Tasks.active_task_count_for_session/1` | Tasks | Active task count for a session |

**Removed:** `Agents.update_agent_status/2` (deprecated no-op).

**Benefits:**
- **Separation of concerns:** Schedulers orchestrate; contexts own data access
- **Testability:** Context functions are independently testable without running the scheduler
- **Reusability:** Same queries available to LiveViews, REST API, and other callers

---

### Chat Presenter

**ChatPresenter** (`lib/eye_in_the_sky_web_web/live/chat_presenter.ex`): Extracted chat presentation logic from `ChatLive`. Handles message formatting, typing indicator state, and ambient message filtering.

- Ambient channel messages no longer trigger agent responses — only `@direct` and `@all` mentions do
- Message numbering is per-channel and sequential (with backfill migration)

### Codex.ToolMapper Extraction

**ToolMapper** (`lib/eye_in_the_sky/codex/tool_mapper.ex`): Extracted from `Codex.SDK` to encapsulate tool description mapping logic. Enables reuse and isolated testing of tool description transformation.

**Pattern (commit 499b70b6):**

```elixir
# Before: Tool mapping logic embedded in Codex.SDK
defmodule Codex.SDK do
  def start_session(context) do
    tools = Enum.map(context.tools, fn tool ->
      %{
        name: tool.name,
        description: "#{tool.description}\n\nUsage: #{tool.usage}",
        input_schema: tool.schema
      }
    end)
    # ... rest of session start
  end
end

# After: Extract to ToolMapper
defmodule Codex.ToolMapper do
  def map_tool_descriptions(tools) do
    Enum.map(tools, fn tool ->
      %{
        name: tool.name,
        description: "#{tool.description}\n\nUsage: #{tool.usage}",
        input_schema: tool.schema
      }
    end)
  end
end

# Codex.SDK now delegates
defmodule Codex.SDK do
  def start_session(context) do
    tools = ToolMapper.map_tool_descriptions(context.tools)
    # ... rest of session start
  end
end
```

**Why this pattern:**
- **Single Responsibility:** ToolMapper owns the tool-to-description transformation logic
- **Testability:** Tool mapping behavior can be unit-tested independently without starting a full Codex session
- **Reusability:** Multiple SDK implementations (stream, resumption, initialization) can reuse the same tool mapping
- **Clarity:** The mapping strategy is explicit, not buried in SDK initialization code

**When to use:** Extract domain logic (data transformation, mapping, validation) from orchestration modules (SDK, dispatcher, worker) when the logic is:
1. Used in multiple places (DRY)
2. Complex enough to warrant isolated tests
3. Logically separate from orchestration concerns

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

### Active Models in Agent Forms

Users can select from a list of configured active models when creating agents or selecting a model for DM messages.

**Pattern (commit 830e2db3):**

**Backend (context module):**
```elixir
# In Agents context
def get_active_models do
  config_file = Application.get_env(:eye_in_the_sky, :config_file)
  {:ok, config} = YamlConfig.load(config_file)
  config.active_models  # Returns list of model strings: ["opus[1m]", "sonnet"]
end
```

**LiveView assignment:**
```elixir
def mount(_params, _session, socket) do
  active_models = Agents.get_active_models()
  {:ok, assign(socket, active_models: active_models)}
end
```

**Template (form with model selector):**
```heex
<.input
  field={@form[:model]}
  type="select"
  label="Model"
  options={Enum.map(@active_models, &{ViewHelpers.model_display_name(&1), &1})}
/>
```

**Affects:**
- New Agent form (`agent_live/index.ex`) — model selector dropdown
- DM page model selector (`chat_live/index.ex`) — model picker for DM composition
- Any form that needs to constrain model selection to configured/active models

**Why this pattern:**
- Models are sourced from config, not hardcoded in the UI
- Users see only the models their instance supports
- Adding new models to config automatically surfaces them in the UI (no code change)

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

## Canvas Submenu UI Pattern (DaisyUI Dropdown-Hover)

Submenu UI appears to the right of a parent menu item on hover, using DaisyUI's `dropdown-hover` class with `menu-dropdown` and `dropdown-content` styling.

**Pattern (commits 2c68ae39, a80c2f40, d6a541e5):**

```heex
<ul class="menu menu-dropdown">
  <li>
    <details class="dropdown-hover">
      <summary class="flex items-center justify-between">
        Canvas
        <.icon name="hero-chevron-right" class="w-4 h-4" />
      </summary>
      <ul class="dropdown-content menu menu-compact">
        <li><a phx-click="navigate_canvas">Create Board</a></li>
        <li><a phx-click="navigate_canvas_gallery">Gallery</a></li>
        <li><a phx-click="navigate_canvas_templates">Templates</a></li>
      </ul>
    </details>
  </li>
</ul>
```

**Styling (CSS):**
- `.dropdown-hover` — triggers on parent hover (no click needed)
- `.dropdown-content` — positioned absolutely to the right
- `.menu-dropdown` — applies menu styling to submenu container
- Submenu appears to the right of parent item (not below)

**Why this pattern:**
- Seamless hover experience without JavaScript event handlers
- DaisyUI handles positioning and z-stacking automatically
- Keyboard accessible via `<details>` semantics
- Mobile: Submenu is tappable (opens on first tap, closes on second)

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

## Query and Preload Patterns

### Preload List Extraction

When preload lists are repeated across multiple query functions in a context, extract them to module constants or private helper functions. This improves maintainability and ensures consistent association loading across the module.

**Why:** 
- Repeated preload lists make the code harder to maintain (DRY principle). Changing requirements means updating multiple locations.
- Constants serve as documentation for what associations are loaded where.
- Using a constant forces consistency across all queries that need the same associations.

**Pattern:**

#### Using a Module Constant

When the same preload list appears in 3+ query functions, define it as a module constant:

```elixir
defmodule EyeInTheSky.Tasks do
  @full_task_preloads [:state, :tags, :sessions, :checklist_items]

  def list_tasks_for_agent(agent_id) do
    Task
    |> where([t], t.agent_id == ^agent_id)
    |> preload(^@full_task_preloads)
    |> Repo.all()
  end

  def get_task(id) do
    case Task
         |> preload(^@full_task_preloads)
         |> Repo.get(id) do
      nil -> {:error, :not_found}
      task -> {:ok, task}
    end
  end

  def get_task!(id) do
    Task
    |> preload(^@full_task_preloads)
    |> Repo.get!(id)
  end
end
```

#### Using a Private Helper Function

When preloads are more complex or need conditional logic, use a private helper:

```elixir
defmodule EyeInTheSky.Sessions do
  def list_sessions_with_agent(opts \\ []) do
    Session
    |> with_agent_preload()
    |> order_by([s], desc: s.started_at)
    |> Repo.all()
  end

  def get_sessions_for_project(project_id) do
    Session
    |> where([s], s.project_id == ^project_id)
    |> with_agent_preload()
    |> Repo.all()
  end

  # Preload helpers
  defp with_agent_preload(query) do
    preload(query, agent: :agent_definition)
  end
end
```

**When to use constants vs helpers:**
- **Constants:** Simple, static preload lists used in 3+ places. Good for searchability and documentation.
- **Helpers:** Complex preloads, conditional logic, or nested associations. Cleaner than inline `preload/2` chains.

**Example: `ApiPresenter.present_session_detail/2`**

The presenter function uses preloaded associations without extracting them again:

```elixir
def present_session_detail(session, opts \\ []) do
  # Assumes session was already loaded with tasks, notes, commits
  tasks = Keyword.get(opts, :tasks, [])
  recent_notes = Keyword.get(opts, :recent_notes, [])
  
  %{
    id: session.id,
    tasks: Enum.map(tasks, &present_session_task/1),
    recent_notes: Enum.map(recent_notes, &present_session_note/1)
  }
end
```

The calling context (e.g., `Sessions.get_session_with_details/1`) handles the preload, not the presenter.

**Rule:** Extract repeated preload lists to constants or helpers. Don't inline identical preload logic in multiple query functions.

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

---

## API Controllers and FallbackController Pattern

### Error Handling via action_fallback

All API controllers wire `action_fallback EyeInTheSkyWeb.Api.V1.FallbackController` to handle error tuples consistently without boilerplate response wrapping:

```elixir
defmodule EyeInTheSkyWeb.Api.V1.TaskController do
  use EyeInTheSkyWeb, :controller

  action_fallback EyeInTheSkyWeb.Api.V1.FallbackController

  def show(conn, %{"id" => id}) do
    case Tasks.get_task(id) do
      {:ok, task} -> json(conn, %{task: task})
      error -> error  # FallbackController handles the tuple
    end
  end
end
```

**FallbackController handles these tuple shapes:**
- `{:error, :not_found}` → 404
- `{:error, %Ecto.Changeset{}}` → 422 with validation details
- `{:error, "string_reason"}` → 422 with reason text
- `{:error, :atom}` → 500 (or specific HTTP status atom)
- `{:error, :status_atom, "reason"}` → explicit HTTP status + reason

**Benefits:**
- Controllers return error tuples directly; no manual status/JSON wrapping
- Consistent error response shape across all endpoints
- Changeset validation errors automatically translated

**Rule:** All API controllers must wire `action_fallback`. Never use `put_status/2` + `json/2` for error handling inline. Return the error tuple and let FallbackController format it.

---

## Batch Updates: Repo.update_all over Raw SQL

When updating multiple database rows based on a list (e.g., task reordering), prefer `Repo.update_all` in a transaction over raw SQL with parameterized placeholders.

**Why:** Raw SQL with dynamic `$N` parameter indexing is fragile and prone to off-by-one errors. For small-to-medium batches (kanban columns, small lists), per-row `Repo.update_all` queries are fine and much safer.

**Pattern (commit 3edb7807):**

```elixir
# ❌ Fragile: Raw SQL with dynamic placeholder indexing
defp reorder_tasks(ordered_uuids) when is_list(ordered_uuids) do
  now = DateTime.utc_now()

  {placeholders, extra_params} =
    ordered_uuids
    |> Enum.with_index(1)
    |> Enum.reduce({[], []}, fn {uuid, pos}, {phs, params} ->
      base = 2 + length(params)
      {phs ++ ["($#{base}, $#{base + 1})"], params ++ [uuid, pos]}
    end)

  sql = """
  UPDATE tasks
  SET position = v.pos,
      updated_at = $1
  FROM (VALUES #{Enum.join(placeholders, ", ")}) AS v(uuid_val, pos)
  WHERE tasks.uuid = v.uuid_val::uuid
  """

  Ecto.Adapters.SQL.query!(Repo, sql, [now | extra_params])
  :ok
end
```

**✅ Safe: Repo.update_all in a transaction**

```elixir
defp reorder_tasks(ordered_uuids) when is_list(ordered_uuids) do
  now = DateTime.utc_now()

  Repo.transaction(fn ->
    ordered_uuids
    |> Enum.with_index(1)
    |> Enum.each(fn {uuid, pos} ->
      Repo.update_all(
        from(t in "tasks", where: t.uuid == ^uuid),
        set: [position: pos, updated_at: now]
      )
    end)
  end)

  :ok
end
```

**Benefits:**
- No dynamic parameter indexing — eliminates off-by-one risk
- Ecto handles parameterization safely via `^uuid`
- Transaction ensures atomicity of all position changes
- Per-row updates are acceptable for small lists (kanban columns are typically < 50 items)

**Rule:** For batch updates of small-to-medium lists, use `Repo.update_all` in a transaction. Reserve raw SQL only for complex queries that can't be expressed in Ecto.

---

## Shared Helpers — Check Before Implementing

**Problem:** Utilities like `parse_int`, `provider_icon`, and `build_bulk_flash` get re-implemented in multiple modules, leading to diverging behavior when requirements change.

**Solution:** Define the helper once in a shared module, annotate it with `@doc "Do not reimplement"`, and check the registry before writing anything similar.

**Canonical Helpers (Commits 983aecdf, 055158cf):**

| Need | Function | Module | Purpose |
|------|----------|--------|---------|
| Provider logo path | `DmHelpers.provider_icon/1` | `components/dm_helpers.ex` | Returns SVG path: `"/images/claude.svg"`, `"/images/openai.svg"`, etc. |
| Provider dark-mode CSS | `DmHelpers.provider_icon_class/1` | `components/dm_helpers.ex` | Returns CSS class for dark-mode inversion: `"dark:invert"` for OpenAI, `""` for others |
| Bulk operation flash | `BulkHelpers.build_bulk_flash/3` | `live/shared/bulk_helpers.ex` | Generates flash message from succeeded/total count and options (verb, entity, destination) |
| String → integer | `ControllerHelpers.parse_int/1` or `/2` | `helpers/controller_helpers.ex` | Parses string to int or returns `nil` / default |
| Session terminated? | `Sessions.terminated_statuses/0` | `eye_in_the_sky/sessions.ex` | Returns list of final statuses: `~w(completed failed)` |

**Build Bulk Flash Pattern (Commit 055158cf):**

Canonical bulk-operation flash message builder. Deduplicates the cond-based pattern from tasks.ex and sessions/actions.ex.

```elixir
# Usage: Returns {:level, message} where level is :info or :error
{flash_level, flash_msg} = BulkHelpers.build_bulk_flash(succeeded, total, opts)

# Examples:
BulkHelpers.build_bulk_flash(3, 3, verb: "Archived", entity: "task")
# => {:info, "Archived 3 tasks"}

BulkHelpers.build_bulk_flash(2, 3, verb: "Moved", entity: "task", destination: "Done")
# => {:info, "Moved 2 tasks to Done; 1 failed"}

BulkHelpers.build_bulk_flash(0, 5, verb: "Archived", entity: "session")
# => {:error, "Could not archive 5 sessions"}
```

**Options:**
- `:verb` (required) — past-tense action: `"Moved"`, `"Archived"`, `"Deleted"`
- `:entity` (required) — singular noun: `"task"`, `"session"`
- `:destination` (optional) — target label for move operations (e.g., state name `"Done"`)

**Before (Antipattern):**
```elixir
# ❌ Duplicated cond logic in tasks.ex
failed = length(results) - moved
cond do
  moved > 0 and failed > 0 ->
    {:info, "Moved #{moved} task#{if moved != 1, do: "s"} to #{state_name}; #{failed} failed"}
  moved > 0 ->
    {:info, "Moved #{moved} task#{if moved != 1, do: "s"} to #{state_name}"}
  true ->
    {:error, "Could not move #{failed} task#{if failed != 1, do: "s"}"}
end

# ❌ Similar duplication in sessions/actions.ex
failed = length(results) - archived
cond do
  archived > 0 and failed > 0 ->
    {:info, "Archived #{archived} #{pluralize_session(archived)}; #{failed} could not be archived"}
  # ... more repeated conditions
end
```

**After (Using BulkHelpers):**
```elixir
# ✅ Single canonical call
{flash_level, flash_msg} = BulkHelpers.build_bulk_flash(moved, length(results),
  verb: "Moved",
  entity: "task",
  destination: state_name
)

{flash_level, flash_msg} = BulkHelpers.build_bulk_flash(archived, length(results),
  verb: "Archived",
  entity: "session"
)
```

**Rule:** Before writing any utility function, grep the codebase and check the registry above. If it exists, use it. If you need a new helper, add it to the appropriate shared module, annotate it with `@doc "Do not reimplement"`, and update this table.

---

## Shared Parameter Parsing Helpers

**Problem:** Multiple controllers or contexts repeat the same parameter parsing logic (e.g., `Integer.parse/1` with error handling).

**Solution:** Define the helper once in a shared module and reuse it across all callers. There are two locations depending on the layer:
- **Controller/LiveView layer:** `ControllerHelpers.parse_int/1` — located in `lib/eye_in_the_sky_web/helpers/controller_helpers.ex`
- **Context/GenServer layer:** `ToolHelpers.parse_int/1` — located in `lib/eye_in_the_sky/utils/tool_helpers.ex`

**Pattern (commits b535769e, e7cee36f):**

```elixir
# ✅ Single definition in ControllerHelpers
defmodule EyeInTheSkyWeb.ControllerHelpers do
  def parse_int(raw) when is_integer(raw), do: raw

  def parse_int(raw) when is_binary(raw) do
    case Integer.parse(raw) do
      {n, ""} -> n
      _ -> nil
    end
  end
  
  # Moved from SessionController and TaskController (no more duplication)
  def resolve_agent_int_id(raw) do
    parse_int(raw) || raise ArgumentError, "invalid agent ID"
  end
end

# ✅ Same pattern in ToolHelpers for context layer
defmodule EyeInTheSky.Utils.ToolHelpers do
  def parse_int(raw) when is_integer(raw), do: raw

  def parse_int(raw) when is_binary(raw) do
    case Integer.parse(raw) do
      {n, ""} -> n
      _ -> nil
    end
  end
end

# ❌ Don't define local duplicates
defmodule TaskController do
  # WRONG: Re-implements parse_int locally
  defp parse_int_param(n, _msg) when is_integer(n), do: {:ok, n}

  defp parse_int_param(raw, msg) when is_binary(raw) do
    case Integer.parse(raw) do
      {n, ""} -> {:ok, n}
      _ -> {:error, :bad_request, msg}
    end
  end
end

# ✅ Use the shared helper
defmodule TaskController do
  import EyeInTheSkyWeb.ControllerHelpers

  defp parse_task_id_int(raw) do
    case parse_int(raw) do
      nil -> {:error, :bad_request, "invalid task_id"}
      n -> {:ok, n}
    end
  end
end
```

**Consolidated locations (commit b535769e):**
- Replaced 11 files using raw `Integer.parse/1` with calls to `ControllerHelpers.parse_int/1` (LiveView/controller layer) or `ToolHelpers.parse_int/1` (context/GenServer layer)
- Removed `resolve_session_int_id` duplication — now calls `parse_int` internally
- Moved `resolve_agent_int_id` to `ControllerHelpers` (commit e7cee36f) to eliminate duplicate definitions in SessionController and TaskController

**When to extract:**
- The same parsing logic appears in 2+ modules
- It's a fundamental type conversion (int, uuid, slug)
- It needs consistent error handling across the app

**Rule:** Shared parameter parsing lives in `ControllerHelpers` (web layer) or `ToolHelpers` (context layer). Never duplicate `parse_int` or similar functions. Check the registry before writing a new parser.

---

## State Derivation Helper Modules

**Problem:** LiveView event handlers mix state mutation with complex state calculation (indeterminate checkboxes, off-screen counts, select-all toggles), making handlers large and hard to test.

**Solution:** Extract all state derivation logic into a dedicated helper module with pure functions.

**Pattern (commit 58d7bca8):**

```elixir
# ✅ Pure derivation module
defmodule EyeInTheSkyWeb.ProjectLive.Sessions.Selection do
  @doc "Compute set of parent IDs with some — but not all — children selected."
  def compute_indeterminate_ids(selected_ids, agents) do
    agents
    |> Enum.reject(&is_nil(&1.parent_session_id))
    |> Enum.group_by(&normalize_id(&1.parent_session_id))
    |> Enum.reduce(MapSet.new(), fn {parent_id, children}, acc ->
      child_ids = MapSet.new(children, &normalize_id(&1.id))
      selected_count = MapSet.size(MapSet.intersection(selected_ids, child_ids))

      if selected_count > 0 and selected_count < MapSet.size(child_ids) do
        MapSet.put(acc, parent_id)
      else
        acc
      end
    end)
  end

  @doc "Select all visible rows; toggle if all are already selected."
  def select_all_visible(selected_ids, agents) do
    visible_ids = ids_from_agents(agents)
    all_visible_selected? = MapSet.subset?(visible_ids, selected_ids)

    if all_visible_selected? do
      MapSet.difference(selected_ids, visible_ids)
    else
      MapSet.union(selected_ids, visible_ids)
    end
  end

  @doc "Clear selection state: used after bulk operations or mode exit."
  def clear_selection(socket) do
    socket
    |> assign(:select_mode, false)
    |> assign(:selected_ids, MapSet.new())
    |> assign(:indeterminate_ids, MapSet.new())
    |> assign(:off_screen_selected_count, 0)
  end
end

# ✅ LiveView event handler delegates to the helper
defmodule EyeInTheSkyWeb.ProjectLive.Sessions do
  def handle_event("select_all", _params, socket) do
    new_selected = Selection.select_all_visible(socket.assigns.selected_ids, socket.assigns.agents)
    indeterminate = Selection.compute_indeterminate_ids(new_selected, socket.assigns.agents)

    socket =
      socket
      |> assign(:selected_ids, new_selected)
      |> assign(:indeterminate_ids, indeterminate)
      |> reinsert_visible_rows()

    {:noreply, socket}
  end
end
```

**Why this pattern:**
- **Testability:** Pure functions are easy to unit test (input → output, no socket magic)
- **Reusability:** The derivation logic can be called from multiple event handlers
- **Clarity:** Complex state logic is isolated and documented in one place
- **Maintainability:** Changes to state rules don't scatter across event handlers

**Rule:** Extract state derivation (MapSet operations, filtering, computation) into dedicated modules when 3+ assigns depend on the same calculation.

---

## LiveView Stream Helpers

**Problem:** When the same stream operation (e.g., re-inserting visible rows) appears twice in different event handlers, it gets duplicated as a reduce loop.

**Solution:** Extract the operation into a private helper function.

**Pattern (commit 3243b7ad):**

```elixir
# ❌ Duplicate reduce loops in event handlers
def handle_event("toggle_selection", %{"id" => id}, socket) do
  new_selected = Selection.toggle_id(socket.assigns.selected_ids, id)

  # DRY violation: this reduce loop appears in 2+ handlers
  visible_agents = Enum.take(socket.assigns.agents, socket.assigns.visible_count)
  socket =
    Enum.reduce(visible_agents, socket, fn agent, acc ->
      stream_insert(acc, :session_list, agent)
    end)

  {:noreply, socket}
end

# ✅ Extract helper
defp reinsert_visible_rows(socket) do
  Enum.take(socket.assigns.agents, socket.assigns.visible_count)
  |> Enum.reduce(socket, fn agent, acc ->
    stream_insert(acc, :session_list, agent)
  end)
end

def handle_event("toggle_selection", %{"id" => id}, socket) do
  new_selected = Selection.toggle_id(socket.assigns.selected_ids, id)
  {:noreply, reinsert_visible_rows(assign(socket, :selected_ids, new_selected))}
end

def handle_event("select_range", _params, socket) do
  # ... compute new selection
  {:noreply, reinsert_visible_rows(assign(socket, :selected_ids, new_selected))}
end
```

**When to extract:**
- The stream operation appears in 2+ event handlers
- It wraps the same data (visible_agents, visible_count)
- It's called after any assign change that affects row rendering

**Why this matters:**
- Streams re-render entire items on `stream_insert`, not partial updates
- After assign changes (select_mode, selected_ids), all visible rows need re-insertion to reflect the new state
- Helper makes it clear that this is a deliberate re-render, not a typo

**Rule:** Extract repeated stream operations to private helpers. Name them after the operation (`reinsert_visible_rows`, `remove_off_screen_agent`, etc.).

---

## Module Extraction from Large Contexts

When a context module grows large with distinct responsibilities, extract domain logic into sub-modules. Each sub-module focuses on a single concern (data transformation, parsing, building, validation) and is tested independently.

### Pattern

**Before:** Logic is embedded in the main context.
```elixir
# lib/eye_in_the_sky/agent_definitions.ex — 200+ lines, mixed concerns
defmodule AgentDefinitions do
  def load_definition(path) do
    # Parsing logic
    # Schema validation logic
    # Definition extraction logic
    # ... all tangled together
  end
end
```

**After:** Extract each concern into a sub-module.
```elixir
# lib/eye_in_the_sky/agent_definitions.ex — focuses on public API
defmodule AgentDefinitions do
  alias AgentDefinitions.FrontmatterParser

  def load_definition(path) do
    content = File.read!(path)
    FrontmatterParser.parse(content)
  end
end

# lib/eye_in_the_sky/agent_definitions/frontmatter_parser.ex — single concern
defmodule AgentDefinitions.FrontmatterParser do
  def parse(content) do
    # Parsing logic only
  end
end
```

### Examples in Codebase

| Parent | Sub-module | Responsibility | Commit |
|--------|-----------|-----------------|--------|
| `AgentManager` | `AgentManager.RecordBuilder` | UUID/project/worktree resolution, agent + session record creation | — |
| `AgentDefinitions` | `AgentDefinitions.FrontmatterParser` | Parse frontmatter YAML from definition files | — |
| `Codex.SDK` | `Codex.ToolMapper` | Map tool descriptions for Codex API requests | 499b70b6 |
| `ProjectLive.Sessions` | `ProjectLive.Sessions.Selection` | Pure state derivation (indeterminate IDs, select-all toggles) | 58d7bca8 |
| `Messages` | `Messages.Listings` | Query builders for message listing, filtering, pagination | 6ee2d5b6 |
| `Messages` | `Messages.Search` | Full-text search via PgSearch, prefix-aware tsquery | 6ee2d5b6 |
| `Rail` | `Rail.FilePanel`, `Rail.Loader`, `Rail.ProjectActions`, etc. | Sidebar sub-components: file tree, agents, project actions, filters | 3b0ca35c |
| `ProjectLive.Tasks` | `TasksBulkActions` (component) | Bulk task actions and flash message generation | 304d5885 |

### Recent Large Extractions

**Commit 304d5885 (Tasks refactoring):**
- Extracted `Tasks.ex` from 578→365 lines, extracted action logic to `ProjectLive.TasksBulkActions` component and `TasksHelpers`
- Extracted `AgentWorker.ex` from 639→501 lines, split into sub-modules (`queue_manager.ex`, `reconciliation.ex`)
- Result: Focused modules, easier to test, clear separation of concerns

**Commit 6ee2d5b6 (Messages refactoring):**
- Extracted `Messages.ex` from 599→247 lines (Listings and Search sub-modules)
- Split `MessagingController` from 610→208 lines (channels, messages, search controllers)
- Result: Canonical query location, searchable logic, reusable across REST API and LiveView

**Commit 3b0ca35c (Rail refactoring):**
- Extracted `Rail.ex` from 967→466 lines (6 sub-components: FilePanel, Loader, ProjectActions, SectionActions, FileActions, FilterActions)
- Result: Focused panel components, testable filtering/sorting logic, cleaner state management

### When to Extract

- Logic is 50+ lines and logically separate from orchestration
- Logic is reused or would be reused from multiple callers
- Logic has different test requirements (unit vs integration)
- Module would benefit from sub-namespace organization
- Multiple concerns are tangled (filtering, sorting, rendering, actions)

**Rule:** Extract to sub-modules to keep contexts under 200-300 lines and each module focused on one job. Sub-modules are named `Parent.SubModule` and live in `lib/parent/sub_module.ex`. Components extracted to UI live as `.ex` files in the `components/` directory with matching hierarchy (e.g., `Rail.FilePanel` → `components/rail/file_panel.ex`).

---

## JavaScript MutationObserver Pattern for DOM State

### SessionsDropdownGuard Example

Use `MutationObserver` to track DOM patches and restore stateful UI (e.g., focus, open dropdowns) when LiveView replaces stream items.

**Problem:** When `stream_insert` replaces a DOM row, any open dropdowns or focused elements close because the old DOM is removed. Standard hook callbacks (`beforeUpdate`, `updated`) don't fire on stream patches since the hook element's attributes don't change.

**Solution:** Combine three layers to survive a stream patch:

1. **focusin/focusout listeners** track which row has focus.
2. **isConnected check** on focusout detects whether the element was removed (stream patch) or deliberately blurred.
3. **MutationObserver** watches for new rows and re-focuses the button in the replacement element.

**Implementation:**
```javascript
export const SessionsDropdownGuard = {
  mounted() {
    this._focusedItemId = null;

    this._onFocusIn = (e) => {
      const item = e.target.closest("[id^='si-']");
      this._focusedItemId = item?.id ?? null;
    };

    this._onFocusOut = (e) => {
      // If still connected, user deliberately blurred; clear state.
      // If disconnected (removed by stream), keep ID for re-focus.
      if (e.target.isConnected) {
        this._focusedItemId = null;
      }
    };

    this.el.addEventListener("focusin", this._onFocusIn);
    this.el.addEventListener("focusout", this._onFocusOut);

    // Re-focus button in replacement element after stream patch
    this._observer = new MutationObserver(() => {
      if (!this._focusedItemId) return;
      const item = document.getElementById(this._focusedItemId);
      this._focusedItemId = null;
      if (!item || item.contains(document.activeElement)) return;
      const btn = item.querySelector(".dropdown [tabindex='0']");
      if (btn) btn.focus();
    });

    // childList only — no need to watch attribute changes
    this._observer.observe(this.el, { childList: true });
  },

  destroyed() {
    this._observer?.disconnect();
    this.el.removeEventListener("focusin", this._onFocusIn);
    this.el.removeEventListener("focusout", this._onFocusOut);
  },
};
```

### Why MutationObserver Works Here

- **Runs after the DOM batch completes:** The observer fires as a microtask *after* the stream patch inserts the new element
- **Tracks only structural changes:** `childList: true` watches for child additions/removals, not attribute changes (cheaper and more precise)
- **Pairs with LiveView lifecycle:** Works around the gap in hook callbacks when attributes are unchanged

**When to use this pattern:**
- UI state (focus, open dropdowns, expanded sections) must survive stream patches
- The old and new DOM elements have stable IDs you can reference
- Standard hook callbacks don't fire on the patch (attributes are unchanged)

**Rule:** Use MutationObserver + focus tracking for state that must survive stream patches. Do not use to work around missing `beforeUpdate` — if the hook element's attributes change, the standard callbacks will fire.

