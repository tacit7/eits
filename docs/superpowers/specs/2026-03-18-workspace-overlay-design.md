# Workspace Overlay — Design Spec

**Date:** 2026-03-18
**Status:** Approved

---

## Overview

Users can add session cards to named workspaces. A workspace is a persistent, named canvas that holds floating chat windows — one per session. The canvas is accessible via a full-screen overlay toggled from the sidebar, visible from any page in the app without losing navigation context.

---

## Architecture

### Data Model

**`workspaces` table**
| Column | Type | Notes |
|---|---|---|
| `id` | bigserial | PK |
| `name` | text | User-defined name |
| `inserted_at` / `updated_at` | timestamps | |

**`workspace_sessions` table**
| Column | Type | Notes |
|---|---|---|
| `id` | bigserial | PK |
| `workspace_id` | bigint | FK → workspaces.id |
| `session_id` | text | FK → sessions.uuid (non-PK reference) |
| `pos_x` | integer | Window X position (px) |
| `pos_y` | integer | Window Y position (px) |
| `width` | integer | Window width (px) |
| `height` | integer | Window height (px) |
| `inserted_at` / `updated_at` | timestamps | |

**Migration note:** `session_id` references a non-PK column. The migration must use `references(:sessions, column: :uuid, type: :text)` and the Ecto schema must declare `foreign_key: :session_id, references: :uuid`.

Window stacking order (z-index) is tracked client-side only — clicking a window brings it to front via JS without a DB round-trip. This is intentional; stacking order does not persist across reloads.

### Contexts

- `EyeInTheSkyWeb.Workspaces` — CRUD for workspaces and workspace_sessions (list, create, delete, upsert window position/size)

### Components

- `WorkspaceOverlayComponent` (LiveComponent) — full-screen overlay, workspace tab switcher, canvas, PubSub subscriber
- `ChatWindowComponent` (LiveComponent, child of overlay) — individual floating chat window per session; drag/resize via JS hook
- `AddToWorkspaceDropdown` (functional component) — dropdown rendered inside session cards

### Mounting

Every page in the `:app` live_session renders inside a LiveView, making it a valid parent for LiveComponents. `WorkspaceOverlayComponent` is mounted once in `app.html.heex` as a sibling to the sidebar, with `id="workspace-overlay"`. The component uses `assign_new` to lazy-load workspace data on first open.

### Toggle State & Cross-Component Events

The overlay's `open` boolean and `active_workspace_id` live in `WorkspaceOverlayComponent`'s own assigns. Since the sidebar is a separate LiveComponent, it cannot directly update the overlay's state. The sidebar sends a `phx-click` that bubbles to the parent LiveView via a `handle_event/3`, which then calls `send_update(WorkspaceOverlayComponent, id: "workspace-overlay", action: :toggle)`. The overlay handles `update/2` for the `:toggle` action and flips its `open` assign.

The same `send_update` pattern is used from the session card's "Added to workspace" confirmation to open the overlay on a specific workspace tab: `send_update(WorkspaceOverlayComponent, id: "workspace-overlay", action: :open_workspace, workspace_id: id)`.

---

## Feature Breakdown

### 1. Sidebar Entry

- Section labelled **Workspace** below existing nav items
- **"Open Workspace"** button (secondary style) — `phx-click="toggle_workspace"` handled in parent LiveView, which calls `send_update` on the overlay
- Below it: list of workspace names with a colored dot indicating if any session in that workspace is currently `working`
- **"+ New workspace"** at the bottom of the list (opens inline name input)

### 2. Workspace Overlay

**Layout:**
- Full-screen fixed layer (`position: fixed; inset: 0; z-index: 60`) — above `z-50` modals is handled by scoping: the overlay renders below flash/command-palette which use `z-[70]` and `z-[80]` respectively. Existing `z-40` sidebar grab handle and mobile nav are unaffected.
- Background: `bg-base-100/80 backdrop-blur-md`
- **Top bar:** "⬡ Workspace" label + DaisyUI `tabs tabs-boxed` workspace switcher + "✕ Close" button
- **Canvas:** remaining viewport height, `position: relative`, `overflow: hidden`

**Workspace tab switcher:**
- Active tab loads its `workspace_sessions` as chat windows; switching tabs unsubscribes from previous sessions, subscribes to new ones
- A "+ New" tab at the end reveals an inline name input in the top bar

### 3. PubSub — Multi-Session Subscription Lifecycle

`WorkspaceOverlayComponent` manages subscriptions dynamically:

- **On tab activate:** call `Events.subscribe_session(id)` for each `session_id` in the workspace. Store subscribed IDs in component assigns.
- **On tab switch:** unsubscribe from all previously subscribed sessions (`Events.unsubscribe_session/1`), subscribe to the new workspace's sessions.
- **On window close (remove from workspace):** unsubscribe that specific session.

**Handled PubSub message types** (from `Events.subscribe_session/1`):
- `{:new_dm, message}` — append to the matching chat window's message list
- `{:claude_response, message}` — append assistant response to the matching chat window
- `{:session_status_changed, session}` — update the status dot color in the matching window titlebar

Messages are routed to the correct `ChatWindowComponent` by matching `message.session_id` against the open windows.

### 4. Floating Chat Windows

**Window anatomy:**
- **Titlebar** (`cursor-move`, `data-drag-handle`): session name, status dot, minimize (yellow) + remove (red) macOS-style dots
- **Message list:** `chat chat-end` / `chat chat-start` DaisyUI bubbles; scrollable; complete messages
- **Composer:** `input input-xs` + `btn btn-primary btn-xs` send button

**Drag:** `ChatWindowDrag` JS hook. `mousedown` on `[data-drag-handle]` → tracks `mousemove` on `document` → updates `style.left` / `style.top` → on `mouseup`, debounced `pushEvent("window_moved", {id, x, y})` → LiveView persists to `workspace_sessions`

**Resize:** `resize: both; overflow: auto` CSS on the window div. `ResizeObserver` debounces `pushEvent("window_resized", {id, w, h})` → LiveView persists to `workspace_sessions`

**Default size:** 320×260px. Default position staggers by 32px per window index to avoid full overlap.

**Stacking (z-index):** clicking any window dispatches a JS `mousedown` listener that sets `z-index: 10` on the clicked window and resets others to `z-index: 1`. Client-side only — does not persist.

### 5. "Add to Workspace" on Session Cards

New button in `session_card.ex` (alongside existing action buttons).

**Trigger:** `btn btn-secondary btn-xs` — "⬡ Add to Workspace"

**Dropdown (DaisyUI `dropdown`):**
- Lists existing workspaces by name
- Separator + **"+ New workspace"** at bottom

**Selecting an existing workspace:**
1. `phx-click="add_to_workspace"` with `workspace_id` and `session_id` params
2. Creates `workspace_sessions` record via `Workspaces.add_session/2`
3. Flash confirmation via `put_flash(:info, ...)` — the flash message includes a JS-dispatch link: `<a phx-click={JS.dispatch("workspace:open", detail: %{workspace_id: id})}>Open workspace →</a>`. A global JS event listener on `document` handles `workspace:open` by calling `liveSocket.execJS` to trigger `send_update` on the overlay via a hook registered on the overlay element.

**Creating a new workspace:**
- Selecting "+ New workspace" reveals an inline `input` in the dropdown
- Submitting creates workspace + workspace_session in one transaction, then triggers the same `workspace:open` JS dispatch

### 6. Sending Messages

The composer `phx-submit` calls `handle_event("send_message", %{"body" => text}, socket)` in `WorkspaceOverlayComponent`. This calls `EyeInTheSkyWeb.Messages.create_message/2` directly with `%{session_id: id, role: "user", body: text}` — the same function used by `DmLive`. No `AgentWorker` spawn, no file attachments, no queued prompts. The Claude CLI picks up the new message via its existing polling/hook mechanism.

---

## UI Standards

- All icons via `<.icon name="hero-*" />` — no inline SVGs
- DaisyUI components: `card`, `btn`, `input`, `tabs`, `dropdown`, `alert`, `chat`
- `z-index` layering: mobile nav `z-40`, sidebar grab `z-45`, overlay `z-60`, flash `z-70`, command palette `z-80`
- Tailwind only for layout/spacing not covered by DaisyUI

---

## Out of Scope

- Workspace sharing between users
- Streaming responses in chat windows
- Mobile layout for the overlay (desktop-only)
- Persisting chat window stacking order across reloads
- Minimizing chat windows to a taskbar

---

## Success Criteria

1. User can click "Add to Workspace" on any session card and add it to an existing or new workspace
2. Workspace overlay opens from the sidebar from any page without navigation
3. Chat windows are draggable and resizable; positions persist across page reloads
4. Multiple sessions can be open simultaneously in one workspace
5. Sending a message in a chat window delivers it to the session and shows the response
6. Switching workspace tabs correctly re-subscribes PubSub to the new set of sessions
