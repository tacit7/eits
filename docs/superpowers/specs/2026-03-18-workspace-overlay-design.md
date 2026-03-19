# Canvas Overlay — Design Spec

**Date:** 2026-03-18
**Status:** Approved

---

## Overview

Users can add session cards to named canvases. A canvas is a persistent, named surface that holds floating chat windows — one per session. The surface is accessible via a full-screen overlay toggled from the sidebar, visible from any page in the app without losing navigation context.

---

## Architecture

### Data Model

**`canvases` table**
| Column | Type | Notes |
|---|---|---|
| `id` | bigserial | PK |
| `name` | text | User-defined name, not null |
| `inserted_at` / `updated_at` | timestamps | |

**`canvas_sessions` table**
| Column | Type | Notes |
|---|---|---|
| `id` | bigserial | PK |
| `canvas_id` | bigint | FK → canvases.id, on_delete: :delete_all |
| `session_id` | integer | FK → sessions.id (integer PK), on_delete: :delete_all |
| `pos_x` | integer | Window X position (px), default 0 |
| `pos_y` | integer | Window Y position (px), default 0 |
| `width` | integer | Window width (px), default 320 |
| `height` | integer | Window height (px), default 260 |
| `inserted_at` / `updated_at` | timestamps | |

**Constraints:**
- `UNIQUE (canvas_id, session_id)` — a session can only appear once per canvas
- Index on `canvas_id` for fast canvas load
- `on_delete: :delete_all` on both FKs to avoid orphaned rows

**Note:** `session_id` is the integer `sessions.id` PK — **not** `sessions.uuid`. All PubSub subscriptions, message sends, and `AgentManager` calls use the integer session ID.

Window stacking order (z-index) is tracked client-side only — clicking a window brings it to front via JS without a DB round-trip. Stacking order does not persist across reloads.

### Contexts

- `EyeInTheSkyWeb.Canvases` — CRUD for canvases and canvas_sessions (list, create, delete, upsert window position/size)

### Components

- `CanvasOverlayComponent` (LiveComponent) — full-screen overlay, canvas tab switcher, chat window surface, PubSub subscriber
- `ChatWindowComponent` (LiveComponent, child of overlay) — individual floating chat window per session; drag/resize via JS hook
- `AddToCanvasDropdown` (functional component) — dropdown rendered inside session cards

### Mounting

Every page in the `:app` live_session renders inside a LiveView, making it a valid parent for LiveComponents. `CanvasOverlayComponent` is mounted once in `app.html.heex` as a sibling to the sidebar, with `id="canvas-overlay"`. The component uses `assign_new` to lazy-load canvas data on first open.

### Toggle State & Cross-Component Events

The overlay's `open` boolean and `active_canvas_id` live in `CanvasOverlayComponent`'s own assigns. Since the sidebar is a separate LiveComponent, it cannot directly update the overlay's state. The sidebar sends `phx-click="toggle_canvas"` that bubbles to the parent LiveView via `handle_event/3`, which calls `send_update(CanvasOverlayComponent, id: "canvas-overlay", action: :toggle)`. The overlay handles `update/2` for the `:toggle` action and flips its `open` assign.

Opening to a specific canvas tab (e.g., from "Add to Canvas") uses a JS `CustomEvent` dispatched on the window. A `phx-hook` on the overlay element listens for `canvas:open` events and calls `pushEvent("open_canvas", %{canvas_id: id})`, which the LiveComponent handles via `handle_event/3`. This avoids the flash/JS bridge pattern entirely.

---

## Feature Breakdown

### 1. Sidebar Entry

- Section labelled **Canvas** below existing nav items
- **"Open Canvas"** button (secondary style) — `phx-click="toggle_canvas"` handled in parent LiveView
- Below it: list of canvas names with a colored dot if any session in that canvas is currently `working`
- **"+ New canvas"** at the bottom of the list

### 2. Canvas Overlay

**Layout:**
- Full-screen fixed layer (`position: fixed; inset: 0; z-index: 60`) with `bg-base-100/80 backdrop-blur-md`
- Z-index layering: mobile nav `z-40`, sidebar grab `z-45`, overlay `z-60`, flash `z-70`, command palette `z-80`
- **Top bar:** "⬡ Canvas" label + DaisyUI `tabs tabs-boxed` canvas switcher + "✕ Close" button (ghost, xs)
- **Surface area:** remaining viewport height, `position: relative`, `overflow: hidden`

**Canvas tab switcher:**
- Active tab loads its `canvas_sessions` as chat windows; switching tabs re-manages PubSub subscriptions (see section 3)
- A "+ New" tab at the end reveals an inline name input in the top bar

### 3. PubSub — Multi-Session Subscription Lifecycle

`CanvasOverlayComponent` manages subscriptions using `Events.subscribe_session/1` and `Events.subscribe_session_status/1`. There is no `unsubscribe_session` helper in Events — unsubscribing calls `Phoenix.PubSub.unsubscribe/2` directly on the topic strings `"session:#{id}"` and `"session:#{id}:status"`. Subscribed IDs are tracked in component assigns.

**Subscription lifecycle:**
- **On tab activate:** subscribe to `session:#{id}` and `session:#{id}:status` for each `session_id` in the canvas
- **On tab switch:** unsubscribe all previous session topics, subscribe to new canvas's sessions
- **On window close (remove from canvas):** unsubscribe that session's topics

**Handled PubSub message types:**
- `{:new_dm, message}` (topic `session:#{id}`) — append to matching chat window's message list
- `{:claude_response, _session_ref, parsed}` (topic `session:#{id}`) — append assistant response to matching window
- `{:session_status, session_id, status}` (topic `session:#{id}:status`) — update status dot in matching window titlebar

All routing uses the integer `session_id`.

### 4. Floating Chat Windows

**Window anatomy:**
- **Titlebar** (`cursor-move`, `data-drag-handle`): session name, status dot (color = session status), minimize (yellow) + remove from canvas (red) macOS-style dots
- **Message list:** `chat chat-end` / `chat chat-start` DaisyUI bubbles; scrollable; complete messages
- **Composer:** `input input-xs` + `btn btn-primary btn-xs` send button

**Drag:** `ChatWindowDrag` JS hook. `mousedown` on `[data-drag-handle]` → tracks `mousemove` on `document` → updates `style.left`/`style.top` → on `mouseup`, debounced `pushEvent("window_moved", {id, x, y})` → LiveComponent persists to `canvas_sessions`

**Resize:** `resize: both; overflow: auto` on the window container. `ResizeObserver` debounces `pushEvent("window_resized", {id, w, h})` → LiveComponent persists to `canvas_sessions`

**Default size:** 320×260px. Default position staggers by 32px per window index to avoid full overlap.

**Stacking:** `mousedown` on any window sets `z-index: 10` on it and resets others to `z-index: 1`. Client-side only.

### 5. "Add to Canvas" on Session Cards

New button in `session_card.ex` alongside existing action buttons.

**Trigger:** `btn btn-secondary btn-xs` — "⬡ Add to Canvas"

**Dropdown (DaisyUI `dropdown`):**
- Lists existing canvases by name
- Separator + **"+ New canvas"** at bottom

**Selecting an existing canvas:**
1. `phx-click="add_to_canvas"` with `canvas_id` and `session_id` params (integer session ID)
2. `Canvases.add_session/2` upserts a `canvas_sessions` record (no-op if already present due to unique constraint)
3. Flash confirmation: `"Added to Design Sprint. Open canvas →"` — the link dispatches `JS.dispatch("canvas:open", to: "#canvas-overlay", detail: %{canvas_id: id})`, caught by the hook on the overlay element

**Creating a new canvas:**
- Selecting "+ New canvas" reveals an inline `input` in the dropdown
- Submitting creates canvas + canvas_session in one transaction, then dispatches `canvas:open`

### 6. Sending Messages

The composer `phx-submit` calls `handle_event("send_message", %{"body" => text}, socket)` in `CanvasOverlayComponent`. Two steps, both required:

1. `Messages.send_message(%{session_id: integer_id, sender_role: "user", recipient_role: "agent", provider: "claude", body: text})` — writes the DB record and broadcasts `session_new_message`
2. On `{:ok, _message}`, calls `AgentManager.continue_session(integer_id, text, [])` — queues the message for the agent process to pick up

This is the same two-step path used in `DmLive.handle_send_message/2`. Skipping step 2 would write the message to the DB but never trigger a Claude response.

---

## UI Standards

- All icons via `<.icon name="hero-*" />` — no inline SVGs
- DaisyUI components: `card`, `btn`, `input`, `tabs`, `dropdown`, `alert`, `chat`
- Z-index layering: mobile nav `z-40`, sidebar grab `z-45`, overlay `z-60`, flash `z-70`, command palette `z-80`

---

## Out of Scope

- Canvas sharing between users
- Streaming responses in chat windows
- Mobile layout for the overlay (desktop-only)
- Persisting chat window stacking order across reloads
- Minimizing chat windows to a taskbar

---

## Success Criteria

1. User can click "Add to Canvas" on any session card and add it to an existing or new canvas
2. Canvas overlay opens from the sidebar from any page without navigation
3. Chat windows are draggable and resizable; positions persist across page reloads
4. Multiple sessions can be open simultaneously in one canvas
5. Sending a message delivers it via `Messages.send_message/1` + `AgentManager.continue_session/3` and the response appears in the window
6. Switching canvas tabs correctly re-subscribes PubSub to the new set of sessions
