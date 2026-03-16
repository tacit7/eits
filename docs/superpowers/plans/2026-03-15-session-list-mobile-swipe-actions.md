# Session List Mobile Swipe Actions Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add swipe-left gesture to session list rows that reveals Fav, Rename, and Archive action buttons on mobile.

**Architecture:** A new `SwipeRow` Phoenix hook handles proportional drag via raw touch events, snapping the row open/closed. The shared `session_row/1` component gains an action panel and inline rename input. Both session list LiveViews get the rename/archive event handlers.

**Tech Stack:** Phoenix LiveView, Elixir, Tailwind CSS, vanilla JS (no extra deps). Uses `TOUCH_DEVICE` from existing `touch_gesture.js` for feature-gating.

---

## Chunk 1: SwipeRow JS Hook

**Files:**
- Create: `assets/js/hooks/swipe_row.js`
- Modify: `assets/js/app.js` (lines 40, 81–94 region)

---

### Task 1: Create the SwipeRow hook

- [ ] **Step 1: Create `assets/js/hooks/swipe_row.js`**

```js
import { TOUCH_DEVICE } from "./touch_gesture"

const MAX_REVEAL = 160  // px — Option B from design spec
const SNAP_THRESHOLD = MAX_REVEAL * 0.35  // 56px

// Track open row across all instances so only one is open at a time
let _openHook = null

function isFormEl(el) {
  return !!el.closest("input, textarea, select, [contenteditable]")
}

export const SwipeRow = {
  mounted() {
    if (!TOUCH_DEVICE) return
    this._setup()
  },

  updated() {
    // LiveView stream patches may re-render the element; re-attach listeners
    if (!TOUCH_DEVICE) return
    this._teardown()
    this._setup()
  },

  destroyed() {
    this._teardown()
    if (_openHook === this) _openHook = null
  },

  _setup() {
    this._rowEl = this.el.querySelector("[data-swipe-row]")
    if (!this._rowEl) return

    this.isOpen = false
    this._startX = 0
    this._startY = 0
    this._startTime = 0
    this._dragging = false

    this._onTouchStart = this._touchStart.bind(this)
    this._onTouchMove  = this._touchMove.bind(this)
    this._onTouchEnd   = this._touchEnd.bind(this)
    this._onSwipeOpen  = this._handleOtherOpen.bind(this)

    this.el.addEventListener("touchstart", this._onTouchStart, { passive: true })
    this.el.addEventListener("touchmove",  this._onTouchMove,  { passive: false })
    this.el.addEventListener("touchend",   this._onTouchEnd,   { passive: true })
    document.addEventListener("swiperow:open", this._onSwipeOpen)
    document.addEventListener("touchstart", this._onDocTouch = (e) => {
      if (this.isOpen && !this.el.contains(e.target)) this._snapClose()
    }, { passive: true })
  },

  _teardown() {
    if (!this._rowEl) return
    this.el.removeEventListener("touchstart", this._onTouchStart)
    this.el.removeEventListener("touchmove",  this._onTouchMove)
    this.el.removeEventListener("touchend",   this._onTouchEnd)
    document.removeEventListener("swiperow:open", this._onSwipeOpen)
    document.removeEventListener("touchstart", this._onDocTouch)
  },

  _touchStart(e) {
    if (isFormEl(e.target)) return
    if (e.touches.length !== 1) return
    this._startX = e.touches[0].clientX
    this._startY = e.touches[0].clientY
    this._startTime = Date.now()
    this._dragging = false
    this._rowEl.style.transition = "none"
  },

  _touchMove(e) {
    const dx = e.touches[0].clientX - this._startX
    const dy = e.touches[0].clientY - this._startY

    if (!this._dragging) {
      if (Math.abs(dx) > 8 && Math.abs(dx) > Math.abs(dy)) {
        this._dragging = true
        // Close any other open row
        if (_openHook && _openHook !== this) _openHook._snapClose()
      } else if (Math.abs(dy) > 10) {
        return  // vertical scroll, ignore
      }
    }

    if (this._dragging) {
      e.preventDefault()
      const base = this.isOpen ? -MAX_REVEAL : 0
      const clamped = Math.min(0, Math.max(-MAX_REVEAL, base + dx))
      this._rowEl.style.transform = `translateX(${clamped}px)`
    }
  },

  _touchEnd(e) {
    const dx = e.changedTouches[0].clientX - this._startX
    const dy = e.changedTouches[0].clientY - this._startY
    const dt = Date.now() - this._startTime

    this._rowEl.style.transition = "transform 0.25s cubic-bezier(0.25,0.46,0.45,0.94)"

    if (this._dragging) {
      if (!this.isOpen && dx < -SNAP_THRESHOLD) {
        this._snapOpen()
      } else if (this.isOpen && dx > SNAP_THRESHOLD) {
        this._snapClose()
      } else if (this.isOpen) {
        this._snapOpen()   // snap back to open
      } else {
        this._rowEl.style.transform = ""  // snap back to closed
      }
    } else if (Math.abs(dx) < 10 && Math.abs(dy) < 10 && dt < 300) {
      // Tap
      if (this.isOpen) {
        this._snapClose()
      }
      // If closed, do nothing — let phx-click on the row fire normally
    }
  },

  _snapOpen() {
    this._rowEl.style.transition = "transform 0.25s cubic-bezier(0.25,0.46,0.45,0.94)"
    this._rowEl.style.transform = `translateX(-${MAX_REVEAL}px)`
    this.isOpen = true
    _openHook = this
    document.dispatchEvent(new CustomEvent("swiperow:open", { detail: { hook: this } }))
  },

  _snapClose() {
    // Note: phx-blur on the rename input fires cancel_rename unconditionally,
    // so no isClosing flag or data-closing DOM attribute is needed here.
    this._rowEl.style.transition = "transform 0.25s cubic-bezier(0.25,0.46,0.45,0.94)"
    this._rowEl.style.transform = ""
    this.isOpen = false
    if (_openHook === this) _openHook = null
  },

  _handleOtherOpen(e) {
    if (e.detail.hook !== this && this.isOpen) this._snapClose()
  },
}
```

- [ ] **Step 2: Register SwipeRow in `assets/js/app.js`**

The current line 40 is:
```js
import {TOUCH_DEVICE, createSwipeDetector} from "./hooks/touch_gesture"
```

Add the SwipeRow import directly after it (do NOT change the touch_gesture import):

```js
import {SwipeRow} from "./hooks/swipe_row"
```

Add registration after `Hooks.FileAttach = FileAttach` (line ~94):

```js
Hooks.SwipeRow = SwipeRow
```

- [ ] **Step 3: Verify JS builds cleanly**

`mix compile` does NOT build JS assets — esbuild handles that as a Phoenix watcher. To check for JS errors, observe the esbuild watcher output in the running dev server, or run:

```bash
cd /Users/urielmaldonado/projects/eits/web/assets && npx esbuild js/app.js --bundle --outdir=../priv/static/assets 2>&1 | head -20
```

Expected: No errors. If an import is wrong, esbuild will report it here.

Then verify Elixir compiles cleanly:

```bash
cd /Users/urielmaldonado/projects/eits/web && mix compile
```

Expected: No Elixir errors.

- [ ] **Step 4: Commit**

```bash
git add assets/js/hooks/swipe_row.js assets/js/app.js
git commit -m "feat: add SwipeRow JS hook for mobile session list swipe actions"
```

---

## Chunk 2: session_card.ex UI Changes

**Files:**
- Modify: `lib/eye_in_the_sky_web_web/components/session_card.ex`

---

### Task 2: Update session_row component with action panel and rename input

The `session_row/1` function component is used by both session list LiveViews. All swipe UI goes here.

- [ ] **Step 1: Read the current file**

```bash
cat lib/eye_in_the_sky_web_web/components/session_card.ex
```

- [ ] **Step 2: Add `editing_session_id` attr to the component**

In the attr declarations block (around line 17–22), add:

```elixir
attr :editing_session_id, :any, default: nil
```

- [ ] **Step 3: Replace the `~H"""` template block inside `def session_row`**

**Do NOT replace the full `def session_row(assigns)` function.** The function has a Elixir preamble (status derivation, `assign` pipeline) before `~H"""` that must be preserved. Only replace the `~H"""...""""` block.

Replace only the `~H"""...""""` block with this new template. Key changes:

- Outer wrapper becomes `relative overflow-hidden` for clipping
- `phx-hook="SwipeRow"` on the outer wrapper (needs a stable `id`)
- Action panel positioned behind the row
- Inner row div gets `data-swipe-row` attribute for the hook to find it
- The `phx-click` and keyboard nav moves to the inner `data-swipe-row` div

Replace only the `~H"""...""""` block inside `def session_row(assigns)`. The Elixir preamble above it (status derivation, assign pipeline) stays untouched:

```heex
<div
  id={"swipe-row-#{@session.id}"}
  class="relative overflow-hidden"
  phx-hook="SwipeRow"
>
  <%!-- Action panel (mobile only, sits behind the row, revealed by swipe) --%>
  <div class="md:hidden absolute right-0 top-0 bottom-0 flex items-stretch" aria-hidden="true">
    <%!-- Fav --%>
    <button
      type="button"
      id={"swipe-fav-#{@session.id}"}
      phx-hook="BookmarkAgent"
      phx-update="ignore"
      data-agent-id={@session.agent && @session.agent.uuid}
      data-session-id={@session.uuid}
      data-agent-name={@session.name || (@session.agent && @session.agent.description) || "Agent"}
      data-agent-status={@session.status}
      class="bookmark-button w-[53px] flex flex-col items-center justify-center gap-1 bg-[#f43f5e] text-white text-[9px] font-bold uppercase tracking-wide border-none"
      aria-label="Bookmark session"
    >
      <.icon name="hero-heart" class="w-5 h-5" />
      Fav
    </button>
    <%!-- Rename --%>
    <button
      type="button"
      phx-click="rename_session"
      phx-value-session_id={@session.id}
      class="w-[53px] flex flex-col items-center justify-center gap-1 bg-[#6366f1] text-white text-[9px] font-bold uppercase tracking-wide border-none"
      aria-label="Rename session"
    >
      <.icon name="hero-pencil-square" class="w-5 h-5" />
      Rename
    </button>
    <%!-- Archive --%>
    <button
      type="button"
      phx-click="archive_session"
      phx-value-session_id={@session.id}
      class="w-[53px] flex flex-col items-center justify-center gap-1 bg-[#f59e0b] text-white text-[9px] font-bold uppercase tracking-wide border-none"
      aria-label="Archive session"
    >
      <.icon name="hero-archive-box" class="w-5 h-5" />
      Archive
    </button>
  </div>

  <%!-- Row content (slides left on swipe) --%>
  <div
    data-swipe-row
    class={"group flex items-center gap-4 py-3 px-2 -mx-2 rounded-lg cursor-pointer border-l-2 bg-inherit will-change-transform " <> @status_border}
    phx-click={if !@select_mode, do: @click_event}
    phx-value-id={@session.id}
    role="button"
    tabindex="0"
    phx-keyup={@click_event}
    phx-key="Enter"
    aria-label={"Open session: #{@session.name || "Unnamed session"} - #{@status_label}"}
  >
    <%!-- Select checkbox (archive mode only) --%>
    <%= if @select_mode do %>
      <div class="flex-shrink-0 w-6 flex justify-center">
        <input
          type="checkbox"
          checked={@selected}
          phx-click="toggle_select"
          phx-value-id={@session.id}
          class="checkbox checkbox-xs checkbox-primary"
          aria-label={"Select session #{@session.name || @session.id}"}
        />
      </div>
    <% end %>

    <%!-- Main content --%>
    <div class="flex-1 min-w-0">
      <div class="flex items-baseline gap-2">
        <%= if @editing_session_id == @session.id do %>
          <form
            phx-submit="save_session_name"
            class="flex-1 min-w-0"
          >
            <%!-- No phx-click-away: it's mouse-only and won't fire on mobile touch.
                 phx-blur on the input handles focus-loss save on all platforms. --%>
            <input type="hidden" name="session_id" value={@session.id} />
            <input
              type="text"
              name="name"
              value={@session.name || ""}
              class="input input-xs w-full text-[13px] font-medium border-primary/40 focus:border-primary bg-base-100"
              phx-keyup="cancel_rename"
              phx-key="Escape"
              phx-blur="cancel_rename"
              autofocus
              maxlength="120"
              aria-label="Edit session name"
            />
          </form>
        <% else %>
          <span class="text-[13px] font-medium text-base-content/85 truncate">
            {@session.name || "Unnamed session"}
          </span>
        <% end %>
      </div>
      <div class="flex items-center gap-1.5 mt-1 text-[11px] text-base-content/30">
        <span class="font-mono">{Sessions.format_model_info(@session)}</span>
        <span class="text-base-content/15">/</span>
        <span class="tabular-nums">{relative_time(@session.started_at)}</span>
        <%= if @project_name do %>
          <span class="text-base-content/15">/</span>
          <span class="truncate text-base-content/50">{@project_name}</span>
        <% end %>
        <%= if task_title = Map.get(@session, :current_task_title) do %>
          <span class="text-base-content/15">/</span>
          <span class="truncate text-primary/60 font-medium">{task_title}</span>
        <% end %>
      </div>
    </div>

    <%!-- Actions slot --%>
    <%= if @actions != [] do %>
      <div class="flex items-center gap-0 flex-shrink-0" phx-click="noop">
        {render_slot(@actions)}
      </div>
    <% end %>
  </div>
</div>
```

> **Rename close paths:** (1) Enter submits the form → `save_session_name`. (2) `phx-blur` fires when the input loses focus (including when user taps elsewhere or swipes) → `cancel_rename` (discard). (3) ESC → `cancel_rename`. Save only happens on explicit Enter. This eliminates any blur/swipe race condition — no `data-closing` DOM attribute or JS coordination needed. `phx-click-away` is NOT used — it is mouse-only and does not fire on mobile touch.

- [ ] **Step 4: Compile to verify no syntax errors**

```bash
cd /Users/urielmaldonado/projects/eits/web && mix compile
```

Expected: No errors.

- [ ] **Step 5: Commit**

```bash
git add lib/eye_in_the_sky_web_web/components/session_card.ex
git commit -m "feat: add swipe action panel and inline rename to session_row component"
```

---

## Note on sessions.ex

The spec lists `lib/eye_in_the_sky_web/sessions.ex` as a file to modify (add `update_session_name/2`). **No changes needed.** `Sessions.update_session(session, %{name: name})` already exists and handles this. The handlers in Chunks 3 and 4 call it directly.

---

## Chunk 3: LiveView Handlers

**Files:**
- Modify: `lib/eye_in_the_sky_web_web/live/session_live/index.ex`
- Modify: `lib/eye_in_the_sky_web_web/live/project_live/sessions.ex`

---

### Task 3: Add handlers to session_live/index.ex

The global sessions page at `/` currently has no `archive_session`, `rename_session`, `save_session_name`, or `cancel_rename` handlers.

- [ ] **Step 1: Add `editing_session_id` assign in `mount/3`**

In `session_live/index.ex` inside the `mount/3` socket assign chain, add:

```elixir
|> assign(:editing_session_id, nil)
```

Place it alongside the other assigns (after `:show_new_session_modal`).

- [ ] **Step 2: Add the four event handlers**

Add these `handle_event` clauses after the existing `handle_event("noop", ...)` clause:

```elixir
@impl true
def handle_event("rename_session", %{"session_id" => session_id}, socket) do
  # session_id arrives as a string from phx-value; parse to integer for comparison
  # with @session.id (integer) in the component template
  {:noreply, assign(socket, :editing_session_id, String.to_integer(session_id))}
end

@impl true
def handle_event("save_session_name", %{"session_id" => session_id, "name" => name}, socket) do
  name = String.trim(name)

  socket =
    if name != "" do
      case Sessions.get_session(session_id) do
        {:ok, session} ->
          Sessions.update_session(session, %{name: name})
          socket
        _ ->
          socket
      end
    else
      socket
    end

  {:noreply, assign(socket, :editing_session_id, nil)}
end

@impl true
def handle_event("cancel_rename", _params, socket) do
  {:noreply, assign(socket, :editing_session_id, nil)}
end

@impl true
def handle_event("archive_session", %{"session_id" => session_id}, socket) do
  with {:ok, session} <- Sessions.get_session(session_id),
       {:ok, _} <- Sessions.archive_session(session) do
    sessions = Sessions.list_session_overview_rows(limit: socket.assigns.page * @per_page, offset: 0)
    total = Sessions.count_session_overview_rows()

    socket =
      socket
      |> assign(:has_more, length(sessions) < total)
      |> assign(:total_sessions, total)
      |> stream(:sessions, sessions, reset: true)
      |> put_flash(:info, "Session archived")

    {:noreply, socket}
  else
    {:error, _} -> {:noreply, put_flash(socket, :error, "Failed to archive session")}
  end
end
```

- [ ] **Step 3: Pass `editing_session_id` to `session_row` in the render**

In the `render/1` function, the `<.session_row>` call currently looks like (exact text to match):

```heex
<.session_row
  session={session}
  project_name={session.project_name}
  click_event="navigate_dm"
/>
```

Replace with (adds `editing_session_id` attr):

```heex
<.session_row
  session={session}
  project_name={session.project_name}
  click_event="navigate_dm"
  editing_session_id={@editing_session_id}
/>
```

- [ ] **Step 4: Compile**

```bash
cd /Users/urielmaldonado/projects/eits/web && mix compile
```

Expected: No errors.

- [ ] **Step 5: Commit**

```bash
git add lib/eye_in_the_sky_web_web/live/session_live/index.ex
git commit -m "feat: add rename, cancel_rename, save_session_name, archive_session handlers to session_live index"
```

---

### Task 4: Add handlers to project_live/sessions.ex

`archive_session` already exists here. Need to add rename handlers and `editing_session_id`.

- [ ] **Step 1: Add `editing_session_id` assign in `mount/2`**

In the `mount/2` assign chain (around line 29–36), add:

```elixir
|> assign(:editing_session_id, nil)
```

- [ ] **Step 2: Add rename handlers**

Add after the existing `handle_event("noop", ...)` clause:

```elixir
@impl true
def handle_event("rename_session", %{"session_id" => session_id}, socket) do
  {:noreply, assign(socket, :editing_session_id, String.to_integer(session_id))}
end

@impl true
def handle_event("save_session_name", %{"session_id" => session_id, "name" => name}, socket) do
  name = String.trim(name)

  socket =
    if name != "" do
      case Sessions.get_session(session_id) do
        {:ok, session} ->
          Sessions.update_session(session, %{name: name})
          socket
        _ ->
          socket
      end
    else
      socket
    end

  {:noreply, assign(socket, :editing_session_id, nil)}
end

@impl true
def handle_event("cancel_rename", _params, socket) do
  {:noreply, assign(socket, :editing_session_id, nil)}
end
```

- [ ] **Step 3: Add `editing_session_id` attr to the `session_row` call in the render**

The `<.session_row>` call in `project_live/sessions.ex` has a long `:actions` slot block (lines 610–671). **Do NOT replace or remove it.** Only add one attribute line to the opening tag:

Find this opening (around line 610):
```heex
<.session_row
  session={agent}
  select_mode={@session_filter == "archived"}
  selected={MapSet.member?(@selected_ids, to_string(agent.id))}
>
```

Add only the new attribute before the `>`:
```heex
<.session_row
  session={agent}
  select_mode={@session_filter == "archived"}
  selected={MapSet.member?(@selected_ids, to_string(agent.id))}
  editing_session_id={@editing_session_id}
>
```

The `<:actions>` slot block that follows the `>` must remain exactly as-is.

- [ ] **Step 4: Compile**

```bash
cd /Users/urielmaldonado/projects/eits/web && mix compile
```

Expected: No errors.

- [ ] **Step 5: Commit**

```bash
git add lib/eye_in_the_sky_web_web/live/project_live/sessions.ex
git commit -m "feat: add rename handlers and editing_session_id to project_live sessions"
```

---

## Chunk 4: Verification

- [ ] **Step 1: Full compile check**

```bash
cd /Users/urielmaldonado/projects/eits/web && mix compile --warnings-as-errors
```

Expected: Clean compile. If warnings surface, fix before continuing.

- [ ] **Step 2: Manual smoke test on mobile (or browser devtools touch mode)**

1. Open `/` on mobile or Chrome DevTools with touch emulation
2. Swipe left on a session row — action panel (Fav/Rename/Archive) slides in
3. Tap Fav — row should bookmark (heart icon fills)
4. Swipe another row — previous row should close automatically
5. Tap Rename — name becomes an editable input
6. Type a new name, press Enter — name updates, input closes
7. Tap Archive on a row — row disappears, flash "Session archived"
8. Tap a row without swiping — navigates to DM page
9. Open `/projects/:id/sessions` — same behavior works there too

- [ ] **Step 3: Final commit if any fixes were needed during smoke test**

```bash
git add -p
git commit -m "fix: swipe action smoke test corrections"
```
