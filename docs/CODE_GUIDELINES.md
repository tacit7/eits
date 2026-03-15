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

## “Gotchas” Checklist

- If you see missing `current_scope`: fix routing/live_session + pass it to `<Layouts.app>`.
- Don’t call `<.flash_group>` outside `Layouts`.
- Don’t use `@apply` in CSS.
- Don’t add inline scripts or inline `onclick`.
- **Never convert untrusted strings to atoms** (unbounded atom table).
- **Validate state transitions in contexts, not LiveViews** (not in UI layer).
- **All DB writes through contexts with changesets** (not raw SQL from LiveView).
- Run `mix precommit` before pushing.

