# Canvas Page Architecture

## Overview

The Canvas page is a dedicated LiveView interface for managing multiple collaborative work sessions simultaneously on a visual canvas. Users can organize sessions in named canvases, arrange windows with draggable positioning, and maintain real-time synchronization via PubSub events.

**Key Change (PR #56):** Canvas was promoted from an overlay component mounted in `app.html.heex` to a dedicated `CanvasLive` page with its own routes and full-page layout.

## Before & After

### Previous Architecture (Overlay Component)
- Canvas overlay was mounted directly in `app.html.heex` as a modal component
- Overlay component managed canvas state within the larger app layout
- Accessed via toggle or modal trigger on the main navigation
- Limited to overlay positioning on top of other page content

### Current Architecture (Dedicated Page)
- Canvas is now a standalone LiveView page at `/canvases` and `/canvases/:id`
- Full-page layout with dedicated canvas tabs and session windows
- Accessible via main navigation routing to `CanvasLive`
- Provides complete visual workspace without overlay constraints

## Route Structure

```elixir
# lib/eye_in_the_sky_web/router.ex
scope "/", EyeInTheSkyWeb do
  pipe_through :browser

  live "/canvases", CanvasLive, :index      # List/default canvas view
  live "/canvases/:id", CanvasLive, :show   # View specific canvas with sessions
end
```

The router defines two action atoms (`:index` and `:show`) but the `CanvasLive` module uses `handle_params/3` to branch logic based on the `:id` parameter presence rather than action-based callbacks.

## CanvasLive Module

Located at: `lib/eye_in_the_sky_web/live/canvas_live.ex`

### State Initialization

`mount/3` initializes the canvas page with:
- `:canvases` — list of all available canvases
- `:active_canvas_id` — currently selected canvas (nil until routed with ID)
- `:canvas_sessions` — sessions pinned to the active canvas
- `:subscribed_session_ids` — session IDs with active PubSub subscriptions
- `:creating_canvas` — boolean flag for new canvas form display
- `:sidebar_tab` — set to `:canvas` to activate canvas sidebar section

### Route Handling

```elixir
# handle_params/3 — activates canvas on route change
def handle_params(%{"id" => id_str}, _url, socket)
  # Parse canvas ID, validate, and activate
  # Subscribes to all sessions in that canvas
  # Sets up window position defaults (cascade layout if not set)

def handle_params(_params, _url, socket)
  # No ID — redirect to first canvas or stay on empty canvas list
```

### Event Handlers

#### Canvas Management
- **`switch_tab`** — User clicks canvas tab; routes to `/canvases/:id` via `push_patch`
- **`start_new_canvas`** — Toggles `:creating_canvas` flag to show name input form
- **`create_canvas`** — Validates name, creates canvas, appends to list, routes to new canvas

#### Window Management
- **`window_moved`** — Records x/y position delta; calls `Canvases.update_window_layout/2`
- **`window_resized`** — Records width/height delta; calls `Canvases.update_window_layout/2`
- **`remove_window`** — Removes session from canvas and unsubscribes from PubSub

### PubSub Integration

The canvas page subscribes to session event streams via `EyeInTheSky.Events`:

**In `activate_canvas/2`:**
```elixir
subscribe_all(session_ids)  # Subscribe to events for all canvas sessions
```

**Event handlers for real-time updates:**
- `{:new_dm, message}` — Message received in a canvas session
- `{:claude_response, _ref, parsed}` — Agent response received
- `{:session_status, session_id, status}` — Session status changed (working → stopped)
- `{:remove_canvas_window, cs_id}` — Remote signal to close a window (e.g., session cleanup)

When events arrive, the handler calls `send_update/3` to update the `ChatWindowComponent` for that canvas session, keeping UI synchronized without full page refresh.

## Component Integration

### ChatWindowComponent
- **Located:** `lib/eye_in_the_sky_web/components/chat_window_component.ex`
- **Role:** Renders draggable, resizable windows for each canvas session
- **Props:** `canvas_session` (struct with pos_x, pos_y, width, height, session_id)
- **Events:** Emits `window_moved`, `window_resized`, `remove_window` to parent `CanvasLive`
- **Updates:** Receives `send_update` calls from PubSub event handlers to re-render with latest message

### AgentList Integration
- **File:** `lib/eye_in_the_sky_web/components/agent_list.ex`
- **Canvas Actions:** Session cards include two dropdown options:
  - "Add to Canvas" — Opens modal to select existing canvas
  - "Add to New Canvas" — Creates canvas and adds session in one action
- **Navigation:** Both trigger `push_navigate` to `/canvases/:id` after adding session

### AllProjectsSection Integration
- **File:** `lib/eye_in_the_sky_web/components/sidebar/all_projects_section.ex`
- **Canvas Tab:** Sidebar includes a "Canvas" tab that routes to `/canvases`
- **Sidebar Tab:** When viewing canvas, `:sidebar_tab` is set to `:canvas` to highlight active section

## Canvas Handlers Module

Located at: `lib/eye_in_the_sky_web/live/agent_live/canvas_handlers.ex`

This extracted module handles canvas-related events fired from the **AgentLive** page when users interact with "Add to Canvas" buttons on session cards:

### Event Handlers

**`show_new_canvas_form`**
- User clicks "Create and add to canvas" on a session card
- Sets `:show_new_canvas_for` flag in AgentLive to display canvas name input

**`add_to_canvas`**
- User selects existing canvas from dropdown
- Calls `Canvases.add_session/2` to link session to canvas
- Routes user to `/canvases/:id` with success flash

**`add_to_new_canvas`**
- User submits new canvas form with optional name
- If no name provided, generates default: `"Canvas {unix_timestamp}"`
- Creates canvas, adds session, routes to new canvas with success flash
- Flash message: `"Added to {canvas_name}"`

## State Management & Data Flow

### Session Lifecycle in Canvas

1. **Adding to Canvas**
   - User clicks "Add to Canvas" on a session card in AgentLive
   - CanvasHandlers.handle_event validates IDs and calls `Canvases.add_session/2`
   - Canvas page receives PubSub event (if open) or user navigates to canvas

2. **Activation**
   - User navigates to `/canvases/:id` (via tab click or redirect)
   - CanvasLive.activate_canvas loads sessions for that canvas
   - Subscribes to session event streams (messages, status, etc.)
   - Sets initial window positions (cascade layout if not persisted)

3. **Real-Time Sync**
   - Events arrive via PubSub: new messages, status changes
   - CanvasLive.handle_info dispatches `send_update` to ChatWindowComponent
   - Components re-render without full page reload

4. **Removal**
   - User clicks close button on window (via ChatWindowComponent)
   - CanvasLive.handle_event removes session and unsubscribes
   - Session remains in database; only canvas link removed

### Window Position Persistence

Window layout (x, y, width, height) is stored in the `canvas_sessions` join table:
- `pos_x`, `pos_y` — Top-left corner offset (pixels)
- `width`, `height` — Window dimensions

When canvas is activated, positions are restored from database. If both are 0, a cascade layout is applied (each window offset by `24 + i*32` pixels) to avoid stack overlap.

## Navigation Flow

### Accessing Canvas

1. **From Agent List**
   - Session card dropdown → "Add to Canvas"
   - Navigates to `/canvases/:id` after adding

2. **From Sidebar**
   - Click "Canvas" tab in sidebar
   - Routes to `/canvases` (redirects to first canvas if available)

3. **Direct URL**
   - User navigates to `/canvases` or `/canvases/:id` directly

### Canvas-to-Agent Navigation

While canvas page is standalone, chat windows display session messages. Clicking a session name or message link should route back to `/agents/:id` (AgentLive) for full session context (code history, status details, etc.).

## Key Architectural Patterns

### Route Branching vs Action Atoms
- `CanvasLive` defines two routes (`:index` and `:show`) but doesn't use action-specific callbacks
- Logic is branched in `handle_params/3` based on `id` param presence
- This pattern avoids action-based render clauses and keeps state management centralized

### Extracted Handlers
- `CanvasHandlers` module extracts canvas-related event logic from AgentLive
- Keeps AgentLive focused on session list and agent card UI
- Enables canvas operations (add, create) from session context

### PubSub Subscription Lifecycle
- Subscriptions are created during `activate_canvas/2`
- All subscriptions cleared when switching canvases or leaving page
- Prevents stale event delivery and connection leak

### Component Isolation
- ChatWindowComponent is a live_component with its own event handling
- Parent (CanvasLive) owns layout and routing; children own rendering
- send_update patterns allow parent to trigger re-renders without full replacement

## Related Files

- **Routes:** `lib/eye_in_the_sky_web/router.ex` (lines 157-158)
- **LiveView:** `lib/eye_in_the_sky_web/live/canvas_live.ex` (264 lines)
- **Handlers:** `lib/eye_in_the_sky_web/live/agent_live/canvas_handlers.ex`
- **Components:**
  - `lib/eye_in_the_sky_web/components/chat_window_component.ex`
  - `lib/eye_in_the_sky_web/components/agent_list.ex` (canvas buttons)
  - `lib/eye_in_the_sky_web/components/sidebar/all_projects_section.ex` (canvas tab)
- **Schema:** `lib/eye_in_the_sky/canvases/canvas.ex` and related Ecto context
- **PubSub:** `lib/eye_in_the_sky/events.ex` (subscription logic)
