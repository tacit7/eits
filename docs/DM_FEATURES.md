# DM Page Features

The DM page (`/dm`) is the central hub for agent communication, task management, and real-time collaboration.

**LiveView:** `lib/eye_in_the_sky_web_web/live/dm_live.ex`
**Component:** `lib/eye_in_the_sky_web_web/components/dm_page.ex`

---

## Usage Dashboard

**Display:** Top of the DM page, shows current session and token usage.

**Metrics:**
- Current model (e.g., `claude-sonnet-4-5`)
- Effort level (haiku, sonnet, opus)
- Total tokens used in session
- Messages count

**Updates:**
- Real-time via PubSub subscription to `session:<id>:status`
- Emitted on each message send
- Includes `total_tokens_for_session` field on message objects

**Implementation:**
- `Messages.get_session_message_tokens/1` aggregates token counts
- Dashboard re-renders on `:message_added` broadcast

---

## Agent Queue Management

**Display:** List of active/idle agents with queue status.

**Features:**
- Shows agent name, status (working, idle, waiting)
- Displays queue position (e.g., "Position 3/5 in queue")
- Color-coded status badges
- Click to focus agent for detailed view

**Queue state:**
- Maintained in `Agents` context
- Updated via PubSub broadcast on `"agents"` topic
- Queue position calculated from task tags and agent availability

**Updates:**
- Real-time agent status changes
- Agent spawned, terminated, working, idle events
- Queue position updates when tasks complete

---

## DmLive Mount Structure

**Refactored (2026-03-17):** Mount chain flattened from 3-level delegation to single `with` chain.

**Before:**
```
mount/3 → mount_session/3 → mount_session_with_agent/3
```

**After:**
```
mount/3 (single with chain)
```

**Benefits:**
- Reduced cognitive load (no delegation hops)
- Easier to trace state setup
- Simplified error handling

---

## Overlay State Management

**State pattern:** Single `:active_overlay` atom instead of 5 boolean assigns.

**Previous approach (boolean assigns):**
```elixir
@assign show_effort_menu: false
@assign show_model_menu: false
@assign show_new_task_drawer: false
@assign show_task_detail_drawer: false
@assign show_create_checkpoint: false
```

**Current approach (atom):**
```elixir
@assign active_overlay: nil  # or :effort_menu | :model_menu | :task_drawer | :task_detail | :checkpoint
```

**Overlay components controlled by active_overlay:**
1. **Effort menu** — opened with `:effort_menu`
2. **Model menu** — opened with `:model_menu`
3. **New task drawer** — opened with `:task_drawer`
4. **Task detail drawer** — opened with `:task_detail`
5. **Create checkpoint** — opened with `:checkpoint`

**Render logic:**
```elixir
<.open_task_detail open={@active_overlay == :task_detail} />
<.toggle_task_detail_drawer @click={handle_overlay(:task_detail)} />
```

**Event handlers:**
- `open_task_detail/1` — opens task detail overlay
- `toggle_task_detail_drawer/1` — toggles task drawer visibility
- `delete_task/2` — deletes task from detail view

---

## Chat Interface

**Display:** Message stream with document-style rendering, semantic color theming, and transcript hierarchy.

**Features:**
- Chronological message view (newest at bottom)
- Document-style message layout (left-aligned user cards, left-aligned agent responses with visual anchor)
- Timestamps: hover-only at 9px via group-hover (desktop only, always visible on mobile)
- Syntax highlighting for code blocks
- Markdown rendering (via Marked.js)
- Mention support (@agent mentions)

**Message styling (commits 885514b3, f75e576d, 904915bc, 7b4f8e59, 652c90f3):**

**Semantic color tokens** (`app.css`):
- `--surface-card` — User bubble background
- `--guide-line` — Agent message left border (derived from `--color-primary`)
- `--agent-bg` — Agent message background wash (derived from `--color-primary`)
- `--surface-code` — Code block backgrounds
- `--border-subtle` / `--border-strong` — UI borders and dividers
- Light/dark mode overrides for consistent contrast

**User messages:**
- Right-aligned bubble with `--surface-card` background (semantic card color)
- `rounded-lg` corners, max-w-[78%] width constraint
- `3px` padding, `items-end` alignment (right-side anchor)
- **DM indicator**: primary/20 border on user DM bubbles

**Agent messages:**
- Left-aligned card with **2px left guide-line** (`--guide-line` color, theme-aware)
- **2.5% opacity background wash** (`--agent-bg`) for visual subordination
- Full-width layout so structured content (lists, code) fills the area
- Text full contrast (not /90)

**Agent model/cost inline:** Rendered as dot-separated plain text (9px monospace, opacity-30) below agent message body (commit 8a8d576e)
- Format: `claude-opus-4-6 · $0.0045` (single line, no pills)
- Replaces prior per-metric badge pills with unified text rendering

**Tool events** (tool_result, tool_use) (commits 904915bc, 7b4f8e59):
- Render **inside agent bubble** (not loose)
- Skip the left guide-line
- Use tighter padding for subordination
- Compact mode: collapse by default, expand on click
- Copy-on-hover icon

**Inter-turn divider (commit f770e19b):**
- `my-5 mx-3` spacing between turns
- Metadata footer with provider avatar, model, cost
- Provider-aware avatar (Claude or Codex icon)

**Turn spacing and sender grouping (commit 8a8d576e):**
- **mt-5**: Applied when sender role changes (user → agent, agent → user)
- **mt-1**: Applied for consecutive messages from the same sender
- **mt-1**: Applied for tool events (tool_use, tool_result)
- **Removed**: Previous space-y-3 container spacing; per-item margins now control rhythm
- Provides clearer visual separation between turns while keeping same-sender messages compact

**Message types:**
- User messages (input)
- Agent messages (responses, analysis)
- System messages (task started, completed, etc.)
- Tool use logs and results (collapsible, details-closed by default)

**Streaming:**
- Messages streamed from agent worker via PubSub
- Live update as agent sends chunks
- Stream shows provider avatar (Claude or Codex) with thinking/tool indicators
- Live-stream bubble with status indicator

**Streaming bubble placement fix (commit 0cc7fc3f):**

The streaming bubble in `messages_tab.ex` was previously nested inside both the `@syncing` and `@empty` conditional branches, making it invisible in two valid streaming states:

- **`syncing=true`** — page is loading (skeleton visible); an agent can already be streaming a response
- **`empty=true`** — session has no prior messages; first agent response starts streaming immediately

The bubble and scroll anchor were moved to be inside `messages-container` but **outside** the `@syncing`/`@empty` tree. Live stream content is now always visible regardless of page load state or message history.

**File:** `lib/eye_in_the_sky_web/components/dm_page/messages_tab.ex`

---

## Channel Marks as Read on Open

**Commit:** `be35e9a4`

When a user switches to a channel in the chat interface, the channel is automatically marked as read in the database.

**Behavior:**
- Calling `load_channel_assigns/5` when opening a channel triggers `Channels.mark_as_read/2`
- Unread badge clears immediately without waiting for a PubSub update
- Active channel's unread count is zeroed before being passed to socket assigns and Rail component updates
- Ensures the UI badge reflects read status immediately on channel switch

**Implementation:**
- `lib/eye_in_the_sky_web/live/chat_live.ex` — Calls `Channels.mark_as_read/2` in `load_channel_assigns/5` when `connected?/1` is true
- Updates `unread_counts` map to zero out the active channel before sending to Rail sidebar via `send_update/2`
- Guards against unconnected mounts (dead render) and missing channel/session IDs

---

## Suppress Channel Notification DM for @mentioned and @all Sessions

**Commit:** `e1346ed9`

Channel notification DMs are suppressed for sessions that receive direct or broadcast message prompts from `ChannelFanout`, preventing duplicate delivery in the same turn.

**Behavior:**
- **@all mentions:** All members receive a broadcast MSG prompt from `ChannelFanout.fanout_all/2` — skip all channel notification DMs
- **@{session_id} mentions:** Those specific sessions receive a direct MSG prompt from `ChannelFanout.fanout_all/2` — skip their notification DMs
- **Ambient-only members:** Still receive the channel notification DM (they get an ambient MSG prompt, not a direct/broadcast)
- Regex scans message body for `@all\b` pattern and `@(\d+)` mentions to identify suppressed sessions

**Problem Solved:**
- Before: `notify_channel_members/3` DMed all members AND `ChannelFanout` sent MSG prompts to the same sessions
- After: Duplicate delivery eliminated; agents no longer receive the same message twice in the same turn

**Implementation:**
- `lib/eye_in_the_sky_web/controllers/api/v1/channel_message_controller.ex` — `notify_channel_members/3` now:
  - Detects `@all` pattern and skips all DM notifications if matched
  - Scans for `@(\d+)` session IDs and builds a `MapSet` of mentioned IDs
  - Filters notification recipients to exclude mentioned sessions
  - Wrapped in `AsyncTask.start/1` so ambient notifications still process asynchronously

---

## New Agent Drawer

**Trigger:** "New Agent" button in sidebar or task list.

**Form fields:**
- Agent name (auto-filled from agent template or manual)
- Description (task description or project context)
- Model selection (haiku, sonnet, opus)
- Effort level (quick, balanced, thorough)
- Project selection (dropdown, pre-populated if in project context)

**Behavior:**
1. User fills form
2. Click "Create Agent"
3. Agent spawned via `/api/v1/agents` endpoint
4. User redirected to new agent's DM
5. Agent begins work in background

**Integration:**
- Uses `sc:spawn` skill internally (or manual agent spawn)
- Passes description to agent for context

---

## New Task Drawer

**Trigger:** "New Task" button in sidebar or project view.

**Form fields:**
- Task title
- Task description
- Project (dropdown)
- State (To Do, In Progress, In Review, Done)
- Priority (1-5)
- Due date (optional)

**Behavior:**
1. User fills form
2. Click "Create Task"
3. Task created via `/api/v1/tasks` endpoint
4. Task appears in project kanban and overview
5. Optionally spawn agent to work on task

**Workflow:**
- Create → assign to agent → monitor progress in DM
- Or manually track task status via state transitions

---

## Agent State Lifecycle Display

**States:**
- **Working** — agent is actively processing (e.g., running tools, generating response)
- **Idle** — agent waiting for input (default after completion)
- **Waiting** — agent queued, waiting for GPU/resource availability
- **Completed** — agent finished work (terminal state)
- **Failed** — agent encountered error (terminal state)

**Visual indicators:**
- Colored badge (green=working, gray=idle, yellow=waiting, red=failed)
- Pulse animation while working
- Timestamp of last status change

**State transitions:**
- Working → Idle (task completed)
- Idle → Waiting (user spawns new task, queue full)
- Waiting → Working (resource available)
- Any state → Failed (error occurred)
- Any state → Completed (explicit session end)

**PubSub broadcasts:**
- Topic: `agents` (agent list updates)
- Topic: `session:<id>:status` (single session status)
- Event: `{:agent_updated, agent}` (state change)

---

## Message Broadcasting via Postgres LISTEN/NOTIFY

**Replacement of Broadcaster:** Commit 3017f438 replaced the 2-second polling `Broadcaster` with `NotifyListener`, a Postgres-based LISTEN/NOTIFY system that broadcasts messages in real-time without polling overhead.

**Architecture:**
1. **Database trigger:** A Postgres trigger fires `pg_notify('messages_inserted', message_id)` on every `messages` INSERT
2. **NotifyListener GenServer:** Subscribes to the `messages_inserted` channel via `Postgrex.Notifications`
3. **Message load and broadcast:** On notification, loads the message by ID from the database and broadcasts via `Events.session_new_message/2`

**Configuration:**
- Enabled by default; disable in test with `config :eye_in_the_sky, EyeInTheSky.Messages.NotifyListener, enabled: false`
- Uses dedicated Postgrex connection (separate from the Repo pool) to avoid blocking the main connection pool

**Broadcasts:**
- `session_new_message(session_id, message)` — for session messages
- `channel_message(channel_id, message)` — for channel messages (if applicable)

---

## BulkImporter Optimizations

**Commits:** `55e2e5f5`, `8d04610f`, `e7c228a9`

The `BulkImporter` module handles session file replay (Claude and Codex) with performance and atomicity improvements.

**Optimizations:**
1. **Batch inserts:** Uses `Repo.insert_all/3` instead of per-row `create_message/1` calls, reducing DB round-trips from O(N) to O(1)
2. **Transaction isolation:** Wraps the entire import batch in `Repo.transaction/1` for atomicity (with per-row error rescue on updates)
3. **Conflict resolution:** On-conflict clause with `conflict_target: :source_uuid` and `on_conflict: :nothing` handles race conditions gracefully

**Processing pipeline:**
- **Separate into actions:** Messages are categorized into three groups:
  - Updates: Link existing unlinked rows (slow path, few rows)
  - Inserts: Create new messages (fast path via `insert_all`)
  - Skips: Fast-path matches or duplicate DMs (no DB work)
- **Execute updates:** Per-row `update_message/2` with error rescue to avoid cascading failures
- **Return count:** Sum of insert_count + update_count + skip_count

**Dedup index (commit e7c228a9):**
- Partial composite index on `(session_id, sender_role, inserted_at) WHERE source_uuid IS NULL`
- Accelerates `find_unlinked_import_candidate/3` lookups for messages created before `source_uuid` was available
- Does NOT include `body` in the key (removed in e7c228a9 to avoid Postgres 8191-byte page limit)

**Result:** Large session replays are now efficient and atomic, with fast dedup paths for live DMs (60s window) and file imports (24h window)

---

## BulkImporter Health Telemetry

**Commit:** `ae0c666a`

Import failures are surfaced via telemetry metrics and the `IndexHealth` health check system.

**Telemetry events:**
- `[:eye_in_the_sky, :bulk_importer, :import]` — emitted on every import with metadata:
  - `status: :ok | :error` — success or failure
  - `reason` — error reason if status is :error
  - `session_id` — the session being imported
  - `provider` — "claude" or "codex"

**IndexHealth module:**
- Tracks recent import failures and stores them in the ETS health check table
- Provides visibility into whether the dedup index is functioning correctly
- Failures indicate potential issues with `source_uuid` conflicts or database constraints

**Files:**
- `lib/eye_in_the_sky/messages/bulk_importer.ex` — telemetry emission
- `lib/eye_in_the_sky/messages/index_health.ex` — health check tracking

---

## Real-Time Updates & Message Streaming

**PubSub subscriptions:**
- `agents` — monitor all agent state changes
- `session:<current_session_id>:status` — monitor current session
- `messages:<session_id>` — incoming messages from agent

**Message broadcasting and append flow (commit 54b88121):**

Instead of debouncing and reloading all N messages on every PubSub event, the DM page now appends individual messages:
- `{:new_message, msg}` and `{:new_dm, msg}` PubSub handlers call `MessageHandlers.append_message_from_pubsub/2`
- `append_message_from_pubsub/2` deduplicates by message id (handles same message arriving via both `force_reload_messages` and PubSub)
- Preloads `:attachments` before appending (prevents crash in `message_attachments` template when `attachments != []` guard fails)
- Cancels any pending debounced reload timer to prevent a stale `:do_message_reload` from clobbering the append
- `{:new_message}` also clears `:stream_content` so the live-stream bubble collapses when the agent reply is persisted
- `{:new_dm}` does not clear it (inbound DM from another session should not dismiss an in-progress stream)

**Grouped message streaming (commit 2e49205f):**

The DM page streams the *output* of `MessageGrouper.group_events/1` (clusters + message rows) rather than raw Message structs:
- `MessageGrouper` module groups consecutive tool messages into clusters and renders standalone messages separately
- Stream item shape: `{:message, msg, prev_role}` or `{:cluster, [events], meta}`
- Stream ids use `"msg-row-<id>"` and `"cluster-row-<id>"` to avoid collision with component-internal ids (`dm-message-<id>`, `cluster-<id>`)
- `TabHelpers.init_stream(:grouped_messages, ...)` in `load_messages_only` and `load_tab_data("messages")`
- `MessageHandlers.append_message_from_pubsub/2` calls `MessageGrouper.diff_tail/2` and `stream_insert` only the changed rows (typically 1)
- `MessagesTab` LC drops `@messages` attr; template uses `phx-update="stream"` container with `@streams.grouped_messages`
- Empty state keyed on boolean `@empty` attr computed inline

**MessageGrouper: Body-Format Tool Message Detection (commit 11a8d715):**

Tool calls are normally identified by `stream_type` metadata (`"tool_use"`, `"tool_result"`). However, older or certain provider formats embed tool calls directly in the message body as plain text:
- **Session reader format:** `> \`ToolName\` args...` (backtick-wrapped, leading `>`)
- **Tool: format:** `Tool: ToolName\n{json}` (literal "Tool:" prefix)

Messages with body-format tool calls were falling through as individual message items instead of being clustered alongside stream_type tool events.

**Fix:** Added `body_is_tool_message?/1` predicate to detect these patterns via regex:

```elixir
defp body_is_tool_message?(body) do
  trimmed = String.trim(body)
  Regex.match?(~r/^> `[^`]+`/, trimmed) or Regex.match?(~r/^Tool: [^\n]+/, trimmed)
end
```

Updated clustering logic to use both checks:
```elixir
is_tool = stream_type in @tool_types or body_is_tool_message?(msg.body)
```

**Result:** Body-format tool calls are now clustered with stream_type tools, producing consistent grouping regardless of how the tool call was serialized.

**File:** `lib/eye_in_the_sky_web/live/dm_live/message_grouper.ex`

**Last stream tail cache (commit 010cc8df):**

To avoid re-grouping the full tail on every PubSub append:
- `append_message_from_pubsub/2` reads `@last_stream_tail` from socket assigns instead of re-grouping the old tail from scratch
- `diff_from_cached_tail/2` computes the new tail and returns only changed rows in one pass
- `load_messages_only` and `load_tab_data` reset `@last_stream_tail` after each stream reset so the cache stays coherent with stream state
- `diff_tail/2` delegates to `diff_from_cached_tail/2` internally

**Message handler:**
```elixir
def handle_info({:new_message, message}, socket) do
  # Append via MessageGrouper.diff_tail → stream_insert (O(1) changed rows)
  # Update token count display
  # Auto-scroll to newest message (ResizeObserver in AutoScroll hook)
  {:noreply, append_and_update(socket, message)}
end
```

---

## File Upload & Attachments

**Feature:** Drag-and-drop file upload in chat input, with support for both browser and Tauri native file drops.

**Supported file types:**
- Text files (markdown, code, logs)
- Images (PNG, JPG, for analysis)
- PDFs (for document review)

**Upload flow (commits e9747de7, df34880a):**

1. **Browser drag-drop:** User drags file into composer; Phoenix LiveView file upload consumes entry
2. **Tauri native drop:** Tauri window receives native file paths via drag event; `consume_tauri_files/1` handles OS paths
3. **File processing:** Both paths call `UploadHelpers.consume_uploaded_files/1` and `UploadHelpers.consume_tauri_files/1`
4. **Message body construction:** `UploadHelpers.build_message_body/2` appends file list to message text
5. **Attachment persistence:** `UploadHelpers.persist_upload_attachments/2` saves file metadata to `FileAttachments` table after message creation

**UploadHelpers module:**

New module (`lib/eye_in_the_sky_web/live/dm_live/upload_helpers.ex`) centralizes file handling logic:

- `consume_uploaded_files/1` — Processes browser file uploads from Phoenix LiveView's `:files` channel
  - Copies temp files to persistent upload directory
  - Returns file metadata: storage_path, filename, content_type, size_bytes
  
- `consume_tauri_files/1` — Processes native file drops from Tauri
  - Reads file stats from absolute OS paths (socket.assigns[:tauri_dropped_files])
  - Copies files to same upload destination as browser uploads
  - Returns identical file metadata shape for downstream consistency
  - Logs warnings for stat/copy failures without crashing the message send
  
- `build_message_body/2` — Appends file list to message text
  - Format: "Original message\n\nAttached files:\n- <path> (<filename>)"
  - Enables agent to reference uploaded files by path
  
- `persist_upload_attachments/2` — Saves file metadata to database
  - Creates `FileAttachments` records linked to message_id
  - Stores storage_path, original_filename, content_type, size_bytes

**Upload destination:**
- Base path: `priv/static/uploads/dm/`
- Organized by date: `priv/static/uploads/dm/YYYY-MM-DD/`
- Filename: UUID + original extension (e.g., `a3f8c1e2-b4d7.pdf`)

**Message send flow (updated in message_handlers.ex):**

```elixir
# Consume both browser and Tauri uploads
browser_files = UploadHelpers.consume_uploaded_files(socket)
tauri_files = UploadHelpers.consume_tauri_files(socket)
uploaded_files = browser_files ++ tauri_files

# Build full message body with attachments
full_body = UploadHelpers.build_message_body(body, uploaded_files)

# On success, persist attachment metadata
UploadHelpers.persist_upload_attachments(uploaded_files, message.id)

# Clear Tauri dropped files after processing
assign(:tauri_dropped_files, [])
```

**Limitations:**
- File size capped at 20 MB
- Only types listed above supported
- Tauri drops require active Tauri window (desktop only)

---

## Editor Split-View Mode

**Commit:** `13a2e57c`

The DM page supports three editor layout modes for flexible file editing alongside the conversation.

**Layout modes:**
- **Hidden** — No editor panel (default; `data-editor-mode="hidden"`)
- **Single** — Editor replaces main chat content (`data-editor-mode="single"`)
- **Split** — Editor and chat side-by-side with draggable divider (`data-editor-mode="split"`)

**State persistence:**
- Mode preference stored in `localStorage` under `editor-mode` key
- Editor panel width stored in `localStorage` under `editor-width` key
- Mobile (<768px) viewport forces single layout regardless of saved preference

**Route capability:**
- Split mode is only available on DM page (controlled by `data-allow-split` attribute on `#app-shell`)
- Toolbar includes a `hero-view-columns` button to toggle split mode (only visible when `data-allow-split="true"`)

**Architecture:**
- Mode state lives on `<html>` element (root layout, never morphdom-patched by LiveView)
- `EditorLayout` JS hook handles:
  - Mode resolution and application from localStorage
  - Draggable splitter interaction with pointer events
  - Lifecycle cleanup on navigation (pointermove/pointerup/pointercancel tracking)
  - MutationObserver on file panel to react to tab open/close events
  - Keyboard resize: ArrowLeft/Right adjust panel width by 20px steps

**Splitter accessibility:**
- `role="separator"` and `aria-orientation="vertical"` for semantic meaning
- `tabindex="0"` makes splitter keyboard-accessible
- `aria-valuenow/min/max` synced by hook to reflect current/min/max width
- Pointer and keyboard cancellation handlers prevent body lock on abrupt termination

**File panel:**
- Always renders (with empty state when no tabs) so the DOM element exists for split mode
- `data-has-tabs` attribute reflects tab state; hook observes mutations to react
- File tabs display in editor header with close buttons

**Files:**
- `assets/js/hooks/editor_layout.js` — Layout mode management and splitter interaction
- `assets/css/app.css` — Split-view layout styles
- `lib/eye_in_the_sky_web/components/rail.ex` — Rail sidebar integration

---

## Composer Autocomplete: @ File and @@ Agent

**Commit:** `0d5b7890`

The DM composer supports inline autocomplete for file paths and agent names, enabling quick references in messages.

### @ File Autocomplete

**Trigger:** Type `@` followed by a path prefix to list files from the project root.

**Behavior:**
- Server-side file listing triggered via `list_files` pushEvent from JS
- Results show files relative to project root, with sorting by name
- Selecting a file inserts its path into the message

**Root Resolution:**
- `FileAutocomplete.list_files/1` resolves the project root from the current workspace scope
- Traversal guard prevents access outside the project root
- Returns sorted file list, filtered by prefix match

**insert_text vs. path separation:**
- Prevents home-root path corruption by separating the insert text (what appears in the message) from the file system path (traversal target)

**Implementation:**
- `lib/eye_in_the_sky_web/live/dm_live/file_autocomplete.ex` — Server-side file listing and root resolution
- `assets/js/hooks/slash_command_popup.js` — Debounce + stale-reply guard (`fileRequestSeq`)
- Tests: 20 Elixir tests in `file_autocomplete_test.exs`, 18 JS tests in `slash_command_popup_file.test.js`

### @@ Agent Autocomplete (and # Shortcut)

**Trigger:** Type `@@` or `#` to autocomplete agent names from the current workspace.

**Behavior:**
- Client-side autocomplete (no server call)
- Filters agent list by typed prefix
- Selecting an agent inserts `@@slug` (with `@@` trigger) or `#slug` (with `#` trigger)
- `@@` and `#` are equivalent shortcuts; use whichever is more natural in context
- Remapped from original `@` trigger to avoid conflict with file autocomplete

**Agent Slug Population:**
- Uses `Agents.list_agents_for_autocomplete/0` to preload `:project` relationship
- Calls `populate_project_name/1` to set meaningful slugs based on project context
- Excludes archived agents, capped at 200 rows, sorted by most recent first
- Ensures slugs are not nil (which would fall back to description or `agent-<id>`)

**Implementation:**
- `assets/js/hooks/slash_command_popup.js` — Detects `#` regex, routes to `slashFilter('agent')`, passes `triggerChar` to renderer
- `assets/js/hooks/slash_renderer.js` — Displays correct prefix (`#` or `@`) on agent rows based on trigger
- `lib/eye_in_the_sky/agents.ex` — `list_agents_for_autocomplete/0` provides lightweight query with project preload
- Works without server-side queries; uses agents already loaded on the page

---

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| `Cmd/Ctrl + Enter` | Send message |
| `Escape` | Close drawer (new agent/task) |
| `Cmd/Ctrl + K` | Search agents/tasks |
| `Cmd/Ctrl + N` | New agent |
| `Cmd/Ctrl + T` | New task |
| `ArrowLeft / ArrowRight` (on splitter) | Resize editor panel by 20px |
| `@` | Trigger file autocomplete in composer |
| `@@` or `#` | Trigger agent autocomplete in composer |

---

## Mobile Layout

**Responsive:**
- Hidden sidebar on mobile (swipe to open)
- Full-width chat on small screens
- Drawer slides in from bottom (mobile nav priority)
- Touch-friendly buttons (48px minimum)

**Agent list:**
- Scrollable list on desktop
- Collapsible on mobile
- Badges show status quickly

---

## Mobile Optimizations (DM Page)

**Desktop/Mobile layout split (commits d6c5ae2e, ef000cd3):**
- **Desktop:** Top bar with breadcrumb, message search, and tab pills (`md:flex`)
- **Mobile:** DM page header card visible (`md:block`) with mobile-optimized controls
- **Header card:** Displays only on mobile; hidden on desktop (md:block)
- **Tab pills and search:** Desktop views in top bar; mobile views in card header (md:hidden)

**Mobile header card (visible md:block):**
- Simplified header with session name
- Removed unlimited placeholder and token counter display
- Includes tab pills for navigation (Messages, Info, Agents, etc.)
- Message search box for filtering
- Action menu for session UUID copy and timer controls

**Tab navigation (mobile):**
- Moved secondary features to a tab-based overflow menu
- Supports tab activation via keyboard (Enter key)
- Activates item when exactly one result is visible

**Periodic sync loop:**
- Automatically loads new messages when agent is running
- Stops when agent completes or is no longer active
- Prevents memory leaks from accumulation of periodic timers
- Handler checks agent status before scheduling next poll

**Color rendering (dark mode):**
- Fixed dark mode code block rendering in dm-markdown
- Proper contrast for syntax highlighting
- Maintains readability in low-light conditions

---

## Mobile Navigation (FAB)

**Floating Action Button (FAB):**
- Located in bottom-right corner on mobile
- Navigates to DM page on tap
- Uses anchor element for reliable navigation
- Visible on all pages except DM page itself
- Fixed positioning, doesn't interfere with scrolling

---

## DM Page Tab Naming

**Commit:** `e8f5fef3`

The primary tab on the DM page was renamed from "Messages" to "Chat" for improved UX clarity.

**Tabs:**
- **Chat** (formerly "Messages") — Main conversation view with streamed messages, tool calls, and inline formatting
- **Tasks** — Task management and status tracking
- **Commits** — Git commit history and summaries
- **Notes** — Agent-created notes and documentation
- **Agents** — Active agent list and queue status
- **Settings** — Session configuration and preferences (Claude/OpenAI flags, auth, defaults)
- **Info** — Session metadata and session controls

**Change rationale:** "Chat" better describes the conversation interface and aligns with common terminology for messaging/conversation UI across platforms.

**File:** `lib/eye_in_the_sky_web/components/dm_page.ex` (@tabs definition)

---

## Message Queue Bug Fixes

**Commits:** `1a09115`, `9e8d312`

Three bugs in the DM message queue admission flow were identified and fixed:

### 1. Orphaned Message Cleanup on Rejection

When queue admission fails (queue full or worker error), the DB message record created before admission was left behind as a pending message with no response. The fix deletes the orphaned DB message on any rejection path, so the UI never shows a phantom "sent" message.

**File:** `lib/eye_in_the_sky_web/live/dm_live/message_handlers.ex`

### 2. Message List Reload After Rejection

After deleting the orphaned message on rejection, the LiveView assigns were not refreshed. The message list is now reloaded on rejection paths so the deleted message disappears from the UI immediately.

**File:** `lib/eye_in_the_sky_web/live/dm_live/message_handlers.ex`

### 3. Deterministic Deduplication at Dequeue Time

`process_next_job` in AgentManager re-evaluates `has_messages` at dequeue time rather than trusting the value captured at enqueue time. This prevents queued jobs from starting a fresh provider session when messages have arrived in the interim, ensuring the correct provider session is resumed.

**File:** `lib/eye_in_the_sky/agents/agent_manager.ex`

### Worker Death Guard

`send_message` now guards the `GenServer.call` against worker death between lookup and call. Instead of raising an exit that could crash the LiveView process, it returns `{:error, :worker_not_found}`.

**File:** `lib/eye_in_the_sky/claude/agent_worker.ex`

### Regression Tests

Dedicated tests cover the fixed paths (commit `9e8d312`):
- `process_next_job` re-evaluates `has_messages` at dequeue time
- `send_message` returns error (not crash) when worker dies between lookup and `GenServer.call`

**Test file:** `test/eye_in_the_sky/claude/agent_worker_test.exs`

---

## Multimodal Content Blocks

**Commits:** `baa1bf9`, `9391dd8`, `b90e4c4`, `85edb0e`, `0bac1bf`

### ContentBlock Foundation

The `EyeInTheSky.Claude.ContentBlock` module provides structured types for multimodal messages:

| Struct | Fields | Constructor |
|--------|--------|-------------|
| `ContentBlock.Text` | `text` | `new_text/1` |
| `ContentBlock.Image` | `data`, `mime_type` | `new_image/2` |
| `ContentBlock.Document` | `source` | `new_document/2` |

Type guards (`text?/1`, `image?/1`, `document?/1`) allow pipeline stages to dispatch on block type.

**File:** `lib/eye_in_the_sky/claude/content_block.ex`

### Provider-Aware Pipeline

Each provider strategy implements `format_content/1` to convert `ContentBlock` structs into its wire format:

- **Claude (Anthropic):** Formats blocks into the Anthropic messages API content array format
- **Codex (OpenAI):** Formats blocks into the OpenAI chat completions content array format

Content blocks flow through the pipeline as:
1. `RuntimeContext` carries `content_blocks` from the upload consumer
2. `AgentWorker` passes blocks into `Job.new/3`
3. Provider strategy formats blocks via `format_content/1` into SDK opts

**Files:**
- `lib/eye_in_the_sky/claude/provider_strategy.ex` (behavior callbacks)
- `lib/eye_in_the_sky/claude/provider_strategy/claude.ex` (Anthropic wire format)
- `lib/eye_in_the_sky/claude/provider_strategy/codex.ex` (OpenAI wire format)
- `lib/eye_in_the_sky/agents/runtime_context.ex`
- `lib/eye_in_the_sky/claude/job.ex`

### CLI Stdin Input Mode

When `content_blocks` are present in opts, the CLI module adds `--input-format stream-json` to `build_args`. The `content_blocks_json/1` function serializes blocks into a JSON user message that is piped to Claude CLI stdin. This is the delivery mechanism for multimodal content to the Claude process.

**File:** `lib/eye_in_the_sky/claude/cli.ex`

### Image Preprocessing

`EyeInTheSky.Media.ImageProcessor` preprocesses uploaded images before they enter the content block pipeline. Uses ImageMagick (`convert`) when available; passes through as-is otherwise.

**Limits:**
| Parameter | Value |
|-----------|-------|
| Hard limit per image | 6 MB |
| API target after processing | 5 MB |
| Max dimension (multi-image) | 1200 px |
| Max dimension (single image) | 2000 px |
| Quality stepping | 85 → 75 → 65 → 55 → 45 → 35 |

**Processing steps:**
1. Decode base64 image data
2. Auto-orient using EXIF data (normalize rotation)
3. Strip all EXIF metadata
4. Resize to max dimension if over limit
5. Step down JPEG quality until under 5 MB target
6. Re-encode to base64 and return updated `ContentBlock.Image`

PNG images with transparency are not converted to JPEG. If ImageMagick is unavailable or base64 data is invalid, the block passes through unchanged.

**File:** `lib/eye_in_the_sky/media/image_processor.ex`

### Test Coverage

- `ContentBlock` struct construction and type guards
- `Job` content block propagation
- Provider `format_content/1` for both Claude and Codex wire formats
- CLI `build_args` with `--input-format stream-json` flag
- `ImageProcessor` resize and compression behavior

**Test files:**
- `test/eye_in_the_sky/claude/content_block_test.exs`
- `test/eye_in_the_sky/claude/job_test.exs`
- `test/eye_in_the_sky/claude/provider_strategy_test.exs`
- `test/eye_in_the_sky/claude/cli_build_args_test.exs`
- `test/eye_in_the_sky/media/image_processor_test.exs`

---

## Message Deduplication

**Primary dedup key:** `source_uuid` (commit 58e557e9)

The `Deduplicator` module and `BulkImporter` guard against duplicate delivery using a distributed `source_uuid` field that travels with every message through the import pipeline.

**Architecture:**
- Every message gets a `source_uuid` when created (e.g., from agent metadata or generated via `Ecto.UUID.generate()`)
- When importing session files, messages are linked by `source_uuid` to prevent creating duplicates
- `Repo.insert_all` with `on_conflict: :nothing` and `conflict_target: :source_uuid` handles race conditions atomically

**Deduplication window split:**

**DM dedup windows (commit 2dfddb77, extended commit d3b11f8f):**
- **Live DM path:** 60-second window for `dm_already_recorded?/3`
  - Prevents re-ingesting a DM that was forwarded to the local CLI and bounced back
  - Uses `Messages.find_recent_dm/3` with a tight time window
  - Applies to messages from `record_incoming_reply/4`
  
- **File import path:** 86400-second (24-hour) window when `importing_from_file?: true`
  - Used by Claude and Codex `SessionImporter` to safely replay session history
  - Extended in commit d3b11f8f to also apply to `agent_reply_already_recorded?`
  - When a user opens an idle session (agent finished > 30s ago), the mount Task sync calls `BulkImporter`, which needs the 24h window to find matching responses committed under a different `source_uuid`
  - `record_incoming_reply` only saves final responses (not tool-call messages), so a 24h exact-body match within one session has negligible false-positive risk

**Body-match fallback removed (commit 58e557e9):**
- Previously, messages without a `source_uuid` would fall back to body matching for dedup
- Now, only `source_uuid` is used for primary dedup; body matching is not a fallback
- `find_unlinked_import_candidate/3` (renamed from `find_unlinked_message/3`) is used only by `BulkImporter` to retroactively link pre-existing rows that were created before a `source_uuid` was available

**Callsites:**
- **DM receive:** `Messages.record_incoming_reply/4` sets `source_uuid` on agent responses
- **File import:** `BulkImporter.import_messages/3` uses source UUIDs from session files; passes `import_opts` to `agent_reply_already_recorded?` to apply 24h window
- **Dedup index:** Partial composite index on `(session_id, sender_role, inserted_at) WHERE source_uuid IS NULL` accelerates the unlinked-message lookup for older data

**Use case:** End-to-end tracking via `source_uuid` makes message deduplication reliable across spawned agents, file replays, and CLI tools—retries are safe.

---

## Tool Result Message UI

**Commits:** `76d6d61e`, `677a0c78`, `e192700e`

Tool result messages in the DM chat have special UI treatment to reduce visual clutter.

**Display rules:**
- **Output closed by default**: `<details>` element renders without the `open` attribute, so tool output is collapsed
- **Empty output skipped**: When body is blank/whitespace, the widget is not rendered at all (commit `e192700e`)
- **Max-width constraint**: Tool widgets limited to 70% of container width for mobile/desktop readability
- **No timestamp**: Tool event messages don't show hover timestamps

**UI behavior:**
1. User sees a compact "Code Block" header with toggle arrow (when body is non-empty)
2. Click header to expand and reveal tool output
3. Expanded output shows full code or command result
4. Collapse hides output again without dismissing the message

**Implementation:** `lib/eye_in_the_sky_web/components/dm_page/messages_tab.ex`

---

## Tool Cluster Rendering: Flat Mode & HTML Structure

**Commits:** `14c0c6fa`, `b3cbddc7`, `035bc79d`

Tool clusters (groups of consecutive tool calls and results) support a flat rendering mode where all content is immediately visible without nested toggle controls.

### Flat Rendering Mode (commit 14c0c6fa)

**Problem:** Tool clusters wrap individual tool widgets inside collapsible `<details>` elements. When a user clicks the cluster `<details>` to expand, each tool widget remains collapsed, requiring a second click on each tool to see its output. This creates friction.

**Solution:** Add `flat=true` attribute to tool rendering components. When flat:
- No `<details>` wrapper on individual tools
- Tool body content always visible (no toggle)
- Single click on cluster header reveals all tool calls and outputs at once

**Affected components:**
- `tool_card_shell/1` — When `flat=true`, renders as a plain div instead of `<details>`; body is always visible in a bordered section
- `tool_widget/1` — Passes `flat={@flat}` to `tool_card_shell`
- `tool_result_body/1` — Passes `flat={@flat}` to `tool_card_shell`
- `message_body/1` — Accepts `flat` attr and passes to nested tool components

**Cluster usage:**
```heex
<.message_body message={event} compact={true} flat={true} />
```

When rendering tool events inside a cluster, `flat=true` is set so expanding the cluster header immediately reveals all tools without additional clicking.

### Tool Cluster HTML Structure Fix (commit b3cbddc7)

**Problem:** The `<summary>` element must be a direct child of `<details>` per HTML spec. The cluster code was wrapping the summary inside an intermediate `<div>`, causing the browser to render a fallback "Details" toggle alongside the custom summary — producing a double header.

**Before:**
```heex
<details>
  <div class="border rounded">
    <summary>Custom header</summary>
    <div>Content</div>
  </div>
</details>
```
This triggers browser fallback rendering.

**After:**
```heex
<details class="border rounded">
  <summary>Custom header</summary>
  <div>Content</div>
</details>
```
The border/bg/rounded styles moved from the inner div to the `<details>` element itself. `<summary>` is now a direct child.

**Result:** Only one header renders; no fallback "Details" toggle.

**File:** `lib/eye_in_the_sky_web/components/dm_page/messages_tab.ex`

### Colored Badges for Tool Calls (commit 035bc79d)

**Display:** Tool calls now render with Claudette-style colored status badges in compact mode (used inside clusters).

**Colors:** Each tool type (Read, Write, Edit, Bash, etc.) gets a semantic color badge:
- **Read**: Blue (information)
- **Write**: Green (success)
- **Edit**: Orange (warning)
- **Bash**: Red (error)
- **Browse**: Purple (custom)

**Rendering:**
- **Compact mode** (inside clusters): Colored text badge + inline detail
- **Expanded mode** (standalone): Full tool widget header with icon and label

**Implementation:** Commit 035bc79d refactors `tool_widget.ex` to apply color via `DmHelpers.provider_icon/1` and tool-specific badge logic.

### Tool Cluster Indent Removal (commit 25ba3689)

**Problem:** Tool cluster headers and summaries had a hardcoded left padding of `pl-[33px]`, adding extra whitespace to both the cluster card and the cluster summary line inside the expandable `<details>` element.

**Fix:** Removed `pl-[33px]` from:
- Tool cluster header element
- Tool cluster summary element

**Result:** Tool clusters render without the extra left indent, creating a more compact and aligned appearance with the surrounding message layout.

**File:** `lib/eye_in_the_sky_web/components/dm_page/messages_tab.ex`

**Files:**
- `lib/eye_in_the_sky_web/components/dm_page/messages_tab.ex` — cluster rendering with `flat=true`
- `lib/eye_in_the_sky_web/components/dm_message_components/tool_widget.ex` — tool card shell, flat mode, colored badges
- `lib/eye_in_the_sky_web/components/dm_helpers.ex` — badge color helpers

---

## DM Message Bubble Format with Sender Chip

**Commits:** `4e0b0f12`, `677a0c78`, `16b3a213`, `6edecd7e`, `0c999311`

Agent DMs now use a structured format with a sender chip that shows agent name and session ID.

**Message format:**

New format (bracketed header):
```
[DM from agent: <agent_name>]
<message body>

Reply: eits dm --to <session_id> --message ""
```

Legacy format (still supported):
```
DM from:<agent_name> (session:<uuid>) <message body>
```

**DM parsing and stripping:**
- `strip_dm_prefix/1`: Removes the DM header and reply footer, returning just the body content
  - Handles both new bracketed format and legacy "DM from:" format
  - Regex updated (commit 6edecd7e) to use `(.*)` capture to handle header-only DMs where the message body is empty
  - Regex tolerates no space after session UUID in legacy format

- `parse_dm_info/1`: Extracts sender name, status (done/failed), and URL from DM body
  - Returns map with sender name, status, url, session_id, and format type
  - Detects status keywords: done, completed, failed, error
  - Extracts HTTP(S) URLs from message body

**UI rendering:**
- DM messages show a sender chip with `lucide-robot` icon (commit 0c999311, changed from `hero-cpu-chip`)
- Chip displays agent name and `#session_id` (integer ID when available)
- **Sender chip is clickable when session_id is present:** Links to the session via `/dm/{session_id}` with hover effects (commit 0c999311)
- **Fallback when no session_id:** Renders as a static span badge (no link)
- Status pill shows done/failed state if present
- Clickable URL chip if a status URL is detected
- User DM bubbles have primary/20 border for visual distinction

**Implementation files:**
- `lib/eye_in_the_sky_web/components/dm_helpers.ex` — parsing functions and shared component helpers
- `lib/eye_in_the_sky_web/components/dm_message_components.ex` — chip rendering and linking
- `lib/eye_in_the_sky/agents/cmd_dispatcher/dm_handler.ex` — DM body construction

---

## DM Component Helper Centralization

**Commits:** `92aaf35d`, `5dfb1e53`, `f3f68c8c`

`DmHelpers` is the single source of truth for shared DM component helpers, eliminating duplication across composer and message components.

**Centralized helpers:**
- `provider_icon/1` — Returns the icon path for a provider (Claude, Codex, Gemini). Previously duplicated in `stream_provider_avatar` component with inline cond logic; now unified via `DmHelpers.provider_icon()`.
- `effort_display_name/1` — Maps effort atoms (low, medium, high, max) to display strings. Previously duplicated in both `Composer` and `DmHelpers`; now single source in `DmHelpers`.

**Deduplication strategy:**
- Component helpers that are used in multiple modules are extracted to `dm_helpers.ex`
- Components import the module and call helpers directly (no alias needed when importing)
- Reduces maintenance burden and ensures consistent rendering across the DM UI

---

## DM Composer

**Component:** `lib/eye_in_the_sky_web/components/dm_page/composer.ex`

The DM composer is the message input area at the bottom of the DM page, with context display, context meter, format toolbar, and inline autocomplete.

**Cleanup (commit e9747de7):** The @ file picker was removed from DmComposer JS hook (158 lines) because `SlashCommandPopup` now handles all autocomplete popups, including @ file suggestions. The DmComposer hook now focuses solely on:
- Keyboard layout and visualViewport handling
- Format toolbar (markdown button)
- Draft persistence
- Clipboard paste for images

### Composer Layout and Context (commit 81ca01cf)

**Context display:**
- Agent name injected into textarea placeholder as "Reply to <agent>…"
- Removed floating `display_name` chip (was redundant overhead)
- Placeholder text provides lightweight context without extra UI clutter

**Styling (commits f770e19b, 652c90f3):**
- Textarea text size: `text-[13px]` for mockup density
- Wrapper uses `--surface-composer` + `--border-subtle` semantic tokens
- Focus-within accent border for visual feedback

**Send/Queue buttons:**
- **Send ↵** — Text label (was icon-only arrow) with `h-7` height consistency
- **Queue button** — Text label + pill styling (`h-6` model/effort pills)
- **Stop button** — Paired with queue button for in-progress sessions

### Context Meter Widget (commit 761b7c85)

**Display:** 10-cell segmented bar showing context window usage percentage.

**Features:**
- **Segmented bar:** 10 cells, each representing ~10% of the session context window
- **Visual feedback:** Cells fill proportionally based on current context usage (system prompt + conversation + files)
- **Clickable:** Click to open a popover with detailed breakdown

**Popover contents:**
- **3-segment breakdown:** System prompt size, conversation size, files size (each with bytes and percentage)
- **Token count:** Total tokens used in the session
- **Session cost:** Estimated cost in USD based on model pricing
- **Action buttons:**
  - `/compact` — Launch the compact flow to consolidate conversation
  - `/clear` — Clear conversation history (system prompt retained)

**Context window detection (commit cde249cb):**
- Models with `-1m` suffix (e.g., `claude-opus-4-6-1m`) are detected and use 1,000,000 token context window
- Otherwise defaults to 200,000 tokens
- Detection checks for `[1m]` in the model key and applies to both warning logs and context meter calculation

**Overlay pattern:**
- Uses existing `active_overlay` pattern with `:context_meter` as the overlay ID
- Styled with DaisyUI popover for consistent UI

**Implementation:**
- `lib/eye_in_the_sky_web/components/dm_page/composer.ex` — context meter bar and popover
- `lib/eye_in_the_sky_web/live/dm_live/tab_helpers.ex` — context calculation and 1M window detection

### Format Toolbar

**Commit:** `fb46a50c`

A markdown format toolbar (Aa button) in the DM composer enables inline text formatting.

**Trigger:** Click the "Aa" button in the left toolbar to show/hide the format strip.

**Format actions:**
| Action | Marker |
|--------|--------|
| Bold | `**text**` |
| Italic | `*text*` |
| Strikethrough | `~~text~~` |
| Inline code | `` `text` `` |
| Code block | ``` `text` ``` |
| Link | `[text](url)` |

**Behavior:**
- Hidden by default; format bar slides in when Aa is clicked
- Buttons wrap/unwrap selected text with markdown syntax
- If selection is already wrapped, clicking the button removes the markers (toggle)
- For links, the URL placeholder is auto-selected after insertion so user can type the URL
- Correct cursor placement for empty selections (marker pair inserted and cursor centered)

**Note:** Keyboard shortcuts (Cmd+B/I/E, Cmd+Shift+E) were removed (commit `dede88f1`) — use toolbar buttons instead.

**Implementation:** 
- `lib/eye_in_the_sky_web/components/dm_page/composer.ex` — HEEx format bar
- `assets/js/hooks/dm_composer.js` — selection wrapping logic

### ReasoningPill: Extended Thinking & Plan Mode (commits d170a9b4, e6c926a7, aa7bccc5)

**Display:** Horizontal pill in the composer footer showing thinking status, plan mode toggle, and effort level selector.

**Segments:**

1. **Thinking Toggle** (Claude only, hidden for Codex/Gemini)
   - Shows icon + "Think" label
   - Click to enable/disable extended thinking
   - Styled with rounded-left corners
   - When thinking is off: light text, hover brightens
   - When thinking is on: warning color background (`bg-warning/[0.04]`), warning text

2. **Separator Divider**
   - 1px vertical line between segments
   - Subtle background color (`bg-base-content/[0.10]`)
   - 4px height, flex-shrink-0

3. **Effort Level Picker** (DaisyUI dropdown)
   - Displays current effort level (Low/Medium/High/Max)
   - Click to open dropdown menu listing available levels
   - Styled with rounded-right corners
   - Muted text, hover brightens
   - **Layout fix (commit aa7bccc5):** Removed `overflow-hidden` from pill wrapper to allow dropdown menu to escape and render fully. Per-segment rounded corners replace the overflow clip.
   - **Interaction fix (commit e6c926a7):** `phx-click` moved from button to parent `.dropdown` div. This keeps focus on the dropdown container after LiveView re-renders, ensuring the DaisyUI `:focus-within` selector remains true and the menu stays visible after server round-trip.

**Plan Mode Toggle (commit d170a9b4)**

The plan button (icon button left of effort segment) toggles `permission_mode: "plan"` in session CLI options.

- **Before:** Button toggled `plan: true` in opts, but `build_args` was ignored by the flag builder (was looking for `permission_mode`).
- **After:** Button now sets `permission_mode: "plan"` (or clears it). The flag is correctly passed to Claude CLI as `--permission-mode plan`.
- **UI:** Plan button shows warning color when active, muted when inactive.

**Plan Button Indicator Fix (commit 70580de8)**

The plan button now correctly shows the active state when toggled. Previously, the `session_cli_opts` assign was updated in the DmLive handler but was never passed to the `DmPage.dm_page` component in the render function. The composer always received an empty `[]` value, causing the plan button indicator to never show active state even though the plan mode was toggled on.

- **Before:** `DmPage.dm_page` was called without the `session_cli_opts` attribute; composer received empty opts.
- **After:** `session_cli_opts={@session_cli_opts}` is now passed to the component, ensuring the composer displays the correct active/inactive state for the plan button.
- **Result:** Plan button indicator now reflects the actual plan mode state in the session CLI options.

**Effort Level Flag (commit d170a9b4)**

The selected effort level is now passed to Claude CLI via `--effort <level>` flag.

- **Before:** Only `CLAUDE_CODE_EFFORT_LEVEL` env var was set; `--effort` flag was missing from args.
- **After:** `build_args/1` in `CLI.Args` now includes `--effort` flag mapped from `opts[:effort_level]`.
- **Possible values:** `low`, `medium`, `high`, `max` (matched to Sonnet/Opus model tiers).

**Implementation:**
- `lib/eye_in_the_sky_web/components/dm_page/message_composer.ex` — ReasoningPill component (three segments)
- `lib/eye_in_the_sky/claude/cli/args.ex` — `build_args/1` includes `--effort` flag
- `lib/eye_in_the_sky_web/live/dm_live.ex` — `toggle_plan_mode` and `toggle_effort_menu` handlers

**Styling notes:**
- Wrapper: `inline-flex items-center rounded-lg border transition-colors` (no overflow-hidden)
- First segment (thinking): `rounded-l-lg`
- Last segment (effort): `rounded-r-lg`
- Divider: `w-px h-4 bg-base-content/[0.10] flex-shrink-0`

### Active CLI Flags Badge (commit 7447546e)

**Display:** Small flag icon button in the composer toolbar with a hover tooltip listing active session-level CLI flags.

**Purpose:** Surfaces CLI flags set via slash command (`/sandbox`, `/add-dir`, `/mcp`, `/plugin`, `/config`, `/agents`, `/max-turns`, `/permissions`, etc.) that have no dedicated toolbar control. These flags were already being serialized into the form's data attribute but had no UI surface.

**Excluded from badge:** Model, effort, and plan-mode are handled by their own dedicated pills and controls, so they never appear in the active flags list (see `SlashCommands.opt_key_to_slug/0`).

**Behavior:**
- Icon: flag emoji or `hero-flag` icon
- Hover tooltip shows comma-separated list of active flags
- Click does nothing (read-only indicator)
- Appears/disappears dynamically based on which flags are active
- No visual distinction between flags; all flags treated equally

**Implementation:**
- `flags_badge/1` component in `message_composer.ex` (commit 7447546e)
- Receives `session_cli_opts` list from parent assigns
- Filters opts via `serialize_cli_opts/1` to extract displayable flag names
- Renders tooltip with flag list; empty list means badge is hidden

**Files:**
- `lib/eye_in_the_sky_web/components/dm_page/message_composer.ex` — `flags_badge/1` component

### Prompt Queue Accordion (commit cb354c03)

**Display:** Queue rows in the prompt queue section collapse/expand based on message length.

**Behavior:**
- **Short messages (≤80 characters):** Render flat without accordion, showing the full message inline
- **Long messages (>80 characters):** Render as a collapsible `<details>` element with:
  - **Summary:** Shows first 80 characters truncated with "…" ellipsis
  - **Rotating chevron icon:** `hero-chevron-right` rotates 90° when expanded (group-open/pq:rotate-90)
  - **Expanded body:** Shows full message with whitespace preserved (`whitespace-pre-wrap`)

**Styling:**
- Summary text styled with `text-xs text-base-content/50 truncate`
- Expanded text uses `text-xs text-base-content/60 whitespace-pre-wrap break-words leading-relaxed`
- Chevron transitions smoothly via `transition-transform` and `group-open/pq:rotate-90`
- Named group `group/pq` used to scope the chevron rotation to the parent details element

**Implementation:**
- `lib/eye_in_the_sky_web/components/dm_page/composer/prompt_queue.ex` — accordion logic with conditional `<details>` rendering
- Decision made with `<% long? = String.length(msg) > 80 %>` to branch at render time

**Files:**
- `lib/eye_in_the_sky_web/components/dm_page/composer/prompt_queue.ex`

### Composer Autocomplete and History

See **Composer Autocomplete: @ File and @@ Agent** (above) for file and agent name completion.

See **DM Composer: localStorage History Persistence** and **Keyboard History Navigation** (below) for message history and recall.

---

## Pi Discovery Cache Warming: DM Composer Init

**Commit:** `42ccd392`

When a DM page mounts with a Pi-session composer, the Pi model discovery cache is automatically warmed to ensure the composer's model selector displays available Pi models immediately, without waiting for another page (drawer, settings, etc.) to trigger a cache refresh.

**Problem solved:**

The composer's model selector (`entries_for_provider("pi")`) is read-only—it never triggers a fetch itself, only reading from the existing cache. For Pi sessions, if the cache was empty on first load, the Pi group would appear empty in the dropdown until some other page (drawer, modal, settings) happened to warm the cache. This created a confusing UX where the Pi selector appeared broken.

**Solution:**

In `DmLive.mount_with_agent/3`, when the session provider is `"pi"`, the mount path now calls:

```elixir
if session.provider == "pi", do: EyeInTheSky.Pi.ModelDiscoveryCache.refresh_async()
```

This is an async refresh that populates the cache without blocking the mount. By the time the user opens the model selector dropdown, the cache is already warm and shows all available Pi models.

**Timing:**

- Refresh is async, so mount completes immediately — no user-visible latency
- Cache refresh happens on every mount, ensuring fresh model availability even if Pi models were added since the session started
- Subsequent mounts of the same session benefit from the refreshed cache

**File:**
- `lib/eye_in_the_sky_web/live/dm_live.ex` — `mount_with_agent/3` adds async cache refresh for Pi sessions

---

## DM Model Helpers: Extracted Model Selection Logic

**Commit:** `98fd83e9`

Model selection and composer state management logic was extracted into a dedicated `DmModelHelpers` module, reducing the complexity of `MessageComposer` and centralizing model/effort handling for reuse.

**Module:** `lib/eye_in_the_sky_web/live/shared/dm_model_helpers.ex`

### Exported Functions

**Model Menu Toggle:**
```elixir
handle_toggle_model_menu(socket) :: {:noreply, Socket.t()}
```
Toggles the `:model_menu` overlay. Used by model selector button click.

**Effort Menu Toggle:**
```elixir
handle_toggle_effort_menu(socket) :: {:noreply, Socket.t()}
```
Toggles the `:effort_menu` overlay. Used by effort level button click.

**Think Toggle:**
```elixir
handle_toggle_thinking(socket) :: {:noreply, Socket.t()}
```
Toggles extended thinking on/off via `:thinking_enabled` assign.

**Live Stream Toggle:**
```elixir
handle_toggle_live_stream(params, socket) :: {:noreply, Socket.t()}
```
Toggles `:show_live_stream` based on `params["enabled"]`. Defaults to toggling current state.

**Model Selection (New Format):**
```elixir
handle_select_model(%{"provider" => provider, "model" => model, "effort" => effort}, socket) ::
  {:noreply, Socket.t()}
```

Validates and persists a model selection. Enforces:
1. **Provider lock:** Cannot switch providers mid-conversation (spec §5.2). Rejects payload if `provider != session.provider`.
2. **Model validation:** Checks `ModelConfig.valid_model?(provider, model)` to ensure the model exists in the provider's registry.
3. **Persistence:** Calls `Sessions.update_session(session, %{model: model})` and updates socket assigns.
4. **Effort defaulting:** For Opus models without explicit effort, defaults to `"medium"`.

Closes the model menu overlay on success (`active_overlay: nil`). Returns flash error on validation failure.

**Model Selection (Back-Compat):**
```elixir
handle_select_model(%{"model" => model, "effort" => effort}, socket) ::
  {:noreply, Socket.t()}
```

Pre-Task-7 format (no `provider` key). Kept for mid-deploy rollout safety — treats the session's own provider as implicit. Uses same validation and persistence as new format.

**Effort Selection:**
```elixir
handle_select_effort(%{"effort" => effort}, socket) :: {:noreply, Socket.t()}
```

Updates `:selected_effort` and closes the effort menu overlay.

**Max Budget:**
```elixir
handle_set_max_budget(%{"value" => value}, socket) :: {:noreply, Socket.t()}
```

Parses the budget value (string → float) and assigns `:max_budget_usd`. Returns `nil` if parsing fails or value ≤ 0 (no limit).

### Model Selection Validation

The `handle_select_model` functions enforce safety constraints:

| Check | Action on Failure |
|-------|------------------|
| Provider matches session | Flash error: "Cannot switch provider mid-conversation" |
| Model is valid for provider | Flash error: "Invalid model selection" |
| Session update succeeds | Flash error: "Failed to save model selection" (logs changeset error) |
| Effort is empty and model is Opus | Default effort to `"medium"` instead of empty string |

### Integration with DmLive

`DmLive` imports `DmModelHelpers` and delegates event handlers:

```elixir
import EyeInTheSkyWeb.Live.Shared.DmModelHelpers

def handle_event("toggle_model_menu", _params, socket) do
  handle_toggle_model_menu(socket)
end

def handle_event("select_model", params, socket) do
  handle_select_model(params, socket)
end
```

This pattern keeps `DmLive` focused on LiveView concerns (PubSub, streams, mounts) while `DmModelHelpers` concentrates on model/effort logic.

**Files:**
- `lib/eye_in_the_sky_web/live/shared/dm_model_helpers.ex` — All model/effort handlers
- `lib/eye_in_the_sky_web/components/dm_page/message_composer.ex` — Uses DmModelHelpers via DmLive delegation
- `lib/eye_in_the_sky_web/live/dm_live.ex` — Imports and delegates to DmModelHelpers

---

## DM Composer: localStorage History Persistence

**Commit:** `57c4b747`

DM composer messages are persisted to browser localStorage, keyed by session UUID, enabling history recall across page reloads and tab closes.

**Storage:**
- Key format: `dm_history:<session_uuid>`
- Max 100 entries per session
- Loaded on composer mount; written on every new message
- Includes multiline text (avoids HTML attribute serialization to preserve newlines)

**Archive Eviction:**
- When sessions are archived, `archive_sessions_action/2` pushes an `evict-dm-history` event with a list of archived session UUIDs
- `DmHistoryCleanup` hook on the sessions page receives the event and removes `dm_history:*` keys from localStorage
- Storage sentinel pattern broadcasts the eviction to other open tabs via `dm_history_evict` key

**Files:**
- `assets/js/hooks/command_history.js` — history load, persistence, cross-tab eviction
- `assets/js/hooks/dm_history_cleanup.js` — eviction handler
- `lib/eye_in_the_sky_web/live/project_live/sessions/actions.ex` — eviction broadcast

---

## Keyboard History Navigation (Ctrl+R / Ctrl+Shift+R)

**Commit:** `57c4b747`

The DM composer supports keyboard-driven history search via Ctrl+R and Ctrl+Shift+R.

**Commands:**
- **Ctrl+R** — Open search dropdown filtered to current session's history
- **Ctrl+Shift+R** — Open search dropdown merged across all `dm_history:*` keys (global history), each item labeled with the first 8 chars of its source session UUID

**Dropdown UI:**
- Live filter input as you type
- Arrow keys (↑/↓) navigate results
- Enter selects the highlighted item
- Escape closes dropdown
- Click outside dismisses

**Multiline Handling:**
- Results stored in `_filteredItems` on hook instance
- Click handlers use closure over filtered item text; avoids HTML attribute round-trip that would truncate newlines

**ArrowUp behavior (commit dede88f1):**
- ArrowUp is gated behind `_isOnFirstLine()` check
- On first line of textarea: recalls previous history item
- On any other line: normal cursor movement (up one line)

**Implementation:** 
- `assets/js/hooks/command_history.js` — Ctrl+R/Ctrl+Shift+R handlers, dropdown, live filter

---

## DM Top Bar: Editable Session Name

**Commit:** `8dd909ea`

The DM session name in the desktop breadcrumb can now be edited inline.

**Behavior:**
- Desktop breadcrumb renders an `<input>` instead of static text for `:dm` pages
- Press Enter to save and focus the composer
- Blur (click away) also saves the change
- Handler updates `:page_title` so the top bar reflects the new name immediately

**Mobile:**
- Mobile header card shows the session name (editable on future iteration)

**Files:**
- `lib/eye_in_the_sky_web/components/layouts.ex` — breadcrumb input rendering
- `lib/eye_in_the_sky_web/live/shared/dm_session_helpers.ex` — session name update handler

---

## DM Top Bar: Copy UUID & Open in iTerm

**Commits:** `c2f8af10`, `2edd0f05`

The DM page top bar and mobile menu include quick-access actions for session UUID and terminal integration.

**Desktop Top Bar:**
- "Copy UUID" menu item shows first 8 characters of session UUID (e.g., `1a2b3c4f…`)
- Click copies the full UUID to clipboard
- Uses `CopyToClipboard` LiveView hook for system clipboard integration

**Mobile Menu:**
- Same "Copy UUID" and "Open in iTerm" actions available in the mobile action menu
- Consistent UX across device sizes

**Open in iTerm:**
- Sends session UUID to iTerm for terminal-side agent interaction
- Command format: `eits dm --to <session_uuid> --message "..."`

**Files:**
- `lib/eye_in_the_sky_web/components/layouts.ex` — desktop top bar
- `lib/eye_in_the_sky_web/components/dm_page.ex` — mobile menu integration
- `lib/eye_in_the_sky_web/components/top_bar/dm.ex` — DM-specific actions

---

## Vim Navigation: i Focuses DM Composer

**Commit:** `23a02760`

The vim navigation `i` command (insert mode) now focuses the DM composer on `/dm/*` pages.

**Behavior:**
- Press `i` on any `/dm` or `/dm/:uuid` page to focus the message input textarea
- Cursor immediately ready for typing without clicking the input
- Follows standard vim insert-mode convention

**Scope:** Active only on DM pages (`:dm` route); ignored on other pages.

**Implementation:**
- `assets/js/hooks/vim_nav_commands.ts` — `i` command registration for DM pages
- `assets/js/hooks/vim_nav.test.ts` — test coverage for DM composer focus

---

## CLI: eits dm inbox

**Commit:** `1c0b5ba6`

The CLI now supports `eits dm inbox` as a convenient alias for listing DM messages with improved output formatting.

**Usage:**
```bash
eits dm inbox                    # List DMs in table format
eits dm inbox --json            # Raw JSON output
eits dm inbox --from <uuid>     # Filter by sender
eits dm inbox --since <iso8601> # Only messages after timestamp (commit dcfd4508)
eits dm inbox --team-only       # Filter to team members only
eits dm inbox --help            # Show command help
```

**--since filter (commit dcfd4508):**
- Accepts ISO8601 timestamp (e.g., `2026-04-30T12:00:00Z`)
- Returns only messages with `inserted_at > since`
- Enables incremental polling: orchestrators can fetch new replies without diffing the full inbox client-side
- Wired through both REST API (`GET /api/v1/dm?since=...`) and CLI
- API returns `filter_since` in response metadata

**Table Output (_tbl_dm renderer):**
| Column | Description |
|--------|-------------|
| FROM | Sender session UUID (first 8 chars) |
| MESSAGE | Message body (DM-from prefix stripped) |
| AGE | Time ago relative format (UTC-aware on macOS) |

**Features:**
- `--json` flag for programmatic consumption
- `--from` filter to show DMs from a specific session UUID only
- `--since` filter (commit dcfd4508) for incremental inbox polling
- `--team-only` filter (commit 2321695e) to show DMs only from sessions that share a team with the current agent
  - Uses `EITS_AGENT_UUID` to discover teams via `GET /teams?member_agent_uuid=`
  - Fetches members per team and filters `from_session_id` against the collected set
  - Client-side filtering via jq
- `--help` to display command reference
- Strips redundant `DM from:` prefix from message body for cleaner display
- UTC age calculation fixed on macOS (commit 1c0b5ba6 fixed `date -ju` parsing)

**Agent Model Aliases (commit 1c0b5ba6):**
- `eits agents spawn --help` now lists shorthand aliases first (recommended usage)
- haiku, sonnet, opus appear before full model names (e.g., `claude-haiku-4-5`) for discoverability

**Files:**
- `scripts/eits` — inbox subcommand, _tbl_dm renderer, --json/--from/--since/--team-only flags, _age UTC fix
- `lib/eye_in_the_sky/messages/listings.ex` — `list_inbound_dms/3` filters by `since` parameter
- `lib/eye_in_the_sky_web/controllers/api/v1/messaging_controller.ex` — `list_dms/2` parses and applies ISO8601 `since` filter
- `docs/EITS_CLI.md` — command reference

---

## CLI: eits dm --metadata

**Commit:** `d7bdffd7`

The `eits dm` command now accepts a `--metadata` flag for sending structured agent context alongside message text.

**Usage:**
```bash
eits dm --to <session_uuid> --message "Task complete" \
  --metadata '{"task_id": 42, "status": "done", "duration_ms": 1250}'
```

**Behavior:**
- `--metadata` accepts a JSON string (shell-escaped or via heredoc)
- JSON is parsed and merged into the DM request body
- Server-side validation ensures valid JSON; invalid metadata returns 422
- Metadata is stored in the message record and passed to AgentWorker as `dm_metadata` context
- Never rendered in the UI; only visible to downstream agents

**Integration with AgentWorker:**
- `dm_metadata` appears in `RuntimeContext.build()` when processing a DM with metadata
- AgentWorker logs whether metadata was used vs. body-only fallback
- Enables agent-to-agent communication of structured data without polluting message display

**Files:**
- `scripts/eits` — argument parsing and JSON validation for --metadata flag
- `docs/EITS_CLI.md` — command reference

---

## CLI: eits tasks complete --notify

**Commit:** `2321695e`

The `eits tasks complete` command now accepts a `--notify` flag to send a DM notification upon successful completion.

**Usage:**
```bash
eits tasks complete <task_id> --message "All tests passing" \
  --notify <recipient_session_uuid>
```

**Behavior:**
- After a successful `tasks complete`, sends a DM to the specified recipient session
- DM format: `"Task <task_id> complete: <message>"`
- Uses the existing `cmd_dm` path for delivery
- Useful for notifying upstream orchestrators or team members when a task finishes

**Example:**
```bash
# Complete task 123 and notify the parent orchestrator
eits tasks complete 123 --message "Feature implemented and tested" \
  --notify b80b9a8d-5dd4-4246-9507-ee0d186d113b
```

Result: Task marked done, and the orchestrator receives a DM: `"Task 123 complete: Feature implemented and tested"`

**Files:**
- `scripts/eits` — --notify flag and DM dispatch logic
- `docs/EITS_CLI.md` — command reference

---

## DM Deduplication Fix

**Commit:** `5b3ac3f2`

Duplicate DM messages on send have been eliminated. Previously, `AgentManager.send_message` injected the DM body into the target session's Claude stdin, which triggered the `UserPromptSubmit` hook to persist the DM as a second `sender_role="user"` message. Combined with the direct `Messages.create_message` call, this produced two DB records that both rendered as DM chips.

**Fix:**
- Skip `AgentManager.send_message` entirely in the `send_dm` handler
- Persist the DM record directly via `Messages.create_message`
- Broadcast via `session_new_dm` PubSub topic to notify all subscribers

**Result:** One DM record, one render; no duplicate messages in the chat.

**Implementation file:** `lib/eye_in_the_sky/agents/cmd_dispatcher/dm_handler.ex`

---

## Messages.send_to_session/2: Atomic Session Resolution & DM Send

**Commit:** `6945108f`

The `Messages.send_to_session/2` function atomically resolves a session by ID or UUID and sends a message to it within a database transaction. This extracts transaction logic from the LiveView layer into the Messages context, maintaining proper separation of concerns.

**Function signature:**
```elixir
@spec send_to_session(String.t() | integer(), String.t(), Keyword.t()) ::
  {:ok, Sessions.Session.t()} | {:error, any()}
def send_to_session(session_id, body, _opts \\ [])
```

**Parameters:**
- `session_id`: Session UUID (string) or numeric session ID (integer)
- `body`: Message body text (string)
- `opts`: Optional keyword list (reserved for future use)

**Behavior:**
1. Wraps the operation in `Repo.transaction/1`
2. Resolves the session using `Sessions.resolve/1` (handles both UUID and integer ID formats)
3. Sends a message with `sender_role="user"` and `recipient_role="agent"` via `send_message/1`
4. Returns `{:ok, session}` on success, `{:error, reason}` on failure
5. Automatic rollback on error via `Repo.rollback/1`

**Use case:** Centralized API for sending DMs to sessions—eliminates transaction boilerplate in LiveView and command handlers. Callers no longer need to wrap session resolution and message creation in manual transactions.

**Note:** The `AgentManager.continue_session` call remains in the LiveView layer (via `floating_chat_live`) to preserve orchestration layer separation. This function handles only the message persistence, not session state transitions.

**Implementation file:** `lib/eye_in_the_sky/messages.ex`

---

## DM Sidebar Tab Default

**Commit:** `81f211e4`

The DM page now defaults to the **Sessions sidebar tab** instead of Chat.

**Change:**
- `DmLive.mount` assigns `:sidebar_tab` to `:sessions` on mount
- Users see the sessions list immediately when opening the DM page
- Chat tab is available if needed via tab navigation

**File:** `lib/eye_in_the_sky_web/live/dm_live/mount_state.ex`

---

## Rejection of DMs from Terminated Sessions

**Commit:** `106e5b9f`

The DM endpoint rejects messages from sessions in terminal states (completed or failed).

**Behavior:**
- Sessions with status `"completed"` or `"failed"` cannot send DMs
- Endpoints return `422 Unprocessable Entity` with error message: `"Sender session is terminated and cannot send DMs"`
- Prevents zombie agent sessions from flooding the message queue with repeated DMs after their work is done

**Check location:** `lib/eye_in_the_sky_web/controllers/api/v1/messaging_controller.ex` in `do_dm/4`

**Use case:** Agent sessions that have finished work are blocked from issuing further messages, so stale broadcast signals or retry loops don't pollute the DM queue.

---

## GET /api/v1/dm/wait — Long-Poll for Next DM

**Commit:** `5836ef77`

Event-driven endpoint that blocks until a new DM arrives for a session, eliminating busy-polling patterns.

**Endpoint:** `GET /api/v1/dm/wait`

**Query params:**
| Param | Default | Max | Description |
|-------|---------|-----|-------------|
| `session` | current session | — | Session UUID to wait on |
| `since` | now | — | ISO8601 timestamp; returns any DM already in inbox since this time |
| `timeout` | 25s | 55s | How long to wait before returning empty |

**Behavior:**
- Subscribes to the existing `session:#{id}` PubSub topic and waits for `:new_dm` broadcast
- If a DM arrives during the wait window, returns immediately with `{"items":[...],"count":1}`
- After `timeout` with no DM, returns `{"items":[],"count":0}`
- Client HTTP timeout is set to server timeout + 15s headroom to avoid cutting the long-poll short locally

**CLI equivalent:** `eits dm wait [--session] [--since] [--timeout] [--team-only]` — prints the result and exits when a DM lands. With `--team-only`, each long-poll iteration filters results to messages from sessions that share a team with the current agent (requires `EITS_AGENT_UUID`). If all polled messages are filtered out and time remains, the loop re-polls with an updated `since` cursor (taken from the last message's `inserted_at`) until a team message arrives or the overall timeout elapses; on timeout it returns `{"items":[],"count":0}` as usual.

**Use case:** Orchestrators and background scripts can block on this endpoint instead of interval-polling `GET /api/v1/dm`, reducing latency and server load.

**Files:**
- `lib/eye_in_the_sky_web/controllers/api/v1/messaging_controller.ex` — `wait/2` action
- `lib/eye_in_the_sky_web/router.ex` — route registration
- `crates/eits-cli/src/commands/dm.rs` — `eitsr dm wait` subcommand

---

## DM Authorization and Duplicate Alert Suppression

**Commit:** `64b6b81d`

DM reads are now authorized via IAM policy, and duplicate alert notifications are suppressed.

**Authorization:**
- `GET /api/v1/dm` (inbox) and `GET /api/v1/dm/wait` enforce policy checks so only authorized sessions can read another session's DM inbox
- Previously, any authenticated request could fetch DMs for any session ID

**Duplicate alert suppression:**
- Native notification alerts for new DMs are deduplicated — if a DM arrives while the session already has a pending alert, a second alert is not fired
- Prevents alert storms when a session is heavily messaged

**Files:**
- `lib/eye_in_the_sky_web/controllers/api/v1/messaging_controller.ex`
- `lib/eye_in_the_sky_web/controllers/api/v1/session_controller.ex`

---

## Copy-to-Clipboard

**Commits:** `d04b7f63`, `10d75ff3`, `7447546e`

DM messages and tool call/output blocks expose a clipboard icon on hover for one-click copy.

**Coverage:**
- DM message bodies (rendered markdown) — both agent and user messages
- Tool call widgets: BASH, Edit, Write
- Tool output blocks

**User Message Copy Button (commit 7447546e):**

User messages now get a hover copy button matching the existing agent message one. When clicked, the button:
1. Copies the full message text to clipboard
2. Swaps the icon to a checkmark (✓) for 1.5 seconds to provide visual feedback
3. Restores the original icon after the feedback period

Previously, user messages had no copy affordance even though the copy data was being serialized into the form's data attribute. This brings feature parity with agent message copy.

**Implementation:**
- `MarkdownMessage` hook injects the clipboard icon after markdown renders (agent messages)
- New copy button on user message bubbles in `messages_tab.ex`
- A global capture-phase click listener intercepts icon clicks before they reach surrounding `<details>` elements, preventing accidental expand/collapse toggling
- Copy uses the Clipboard API with a transient checkmark icon swap (1.5s) for feedback
- SVG checkmark icon defined in `assets/js/app.js` for reuse across copy buttons

---

## DM Stream: PreserveDetails Hook

**Commit:** `43bef912`

The `PreserveDetails` JS hook preserves the open state of tool cluster `<details>` elements across LiveView patches.

**Problem:** When new tool events arrive, morphdom updates the cluster content (count, event list) correctly, but morphdom also reconciles the `open` attribute against server HTML (never rendered with `open`), collapsing any expanded cluster.

**Solution:** PreserveDetails hooks snapshots `this.el.open` in `beforeUpdate()` and restores it in `updated()` — two lines, no state outside the hook instance.

**Wire it on the `<details>` element:**
```heex
<details id={"cluster-#{first_id}"} phx-hook="PreserveDetails">
```

**Files:**
- `assets/js/app.js` — hook registration
- `assets/js/hooks/preserve_details.js` — implementation
- `lib/eye_in_the_sky_web/components/dm_page/messages_tab.ex` — wiring on tool_cluster

---

## Auto-Scroll Across LiveView Patches

**Commits:** `08fdbac0`, `fd56f6fd`, `4462d2b8`

The `AutoScroll` hook preserves the auto-scroll behavior when the DM message list DOM is rebuilt during LiveView patches and handles content growth after mount.

**Problem solved (08fdbac0):**
- After commit 33405bb8 disabled native `overflow-anchor`, the `AutoScroll` hook became the sole mechanism keeping messages pinned to the bottom
- On full message reloads (DOM rebuild), `scrollTop` briefly reset to 0 during the patch, causing the scroll listener to fire and flip `shouldAutoScroll = false`
- This made newly arrived messages land off-screen instead of auto-scrolling into view

**Solution (08fdbac0):**
- Added `beforeUpdate()` to lock `shouldAutoScroll` to its pre-patch geometry state computed before the DOM swap
- Added `_updating` flag to ignore scroll events fired during the DOM patch
- After the browser settles the DOM swap, `requestAnimationFrame` releases the flag so future scrolls work normally

**Post-mount content growth (fd56f6fd):**
- Message rows expand AFTER mount due to LocalTime hooks filling empty `<time>` tags, phx-mounted transitions, and late-arriving stream patches
- The container scrollHeight can grow by 600–1100px after initial scroll, leaving the view stuck partway up
- Solution: Added a `ResizeObserver` on the container and its children. While `shouldAutoScroll` is true, the observer snaps to bottom whenever scrollHeight changes
- User scroll-up still wins — observer only acts when `shouldAutoScroll` is already true

**Performance optimization (4462d2b8):**
- Removed dead `_loadingMore` flag tracking
- Replaced O(n) child iteration with `MutationObserver` to detect content changes
- Eliminates expensive DOM queries on every message append; observer fires only when DOM changes

**Files:**
- `assets/js/hooks/auto_scroll.js` — `beforeUpdate`, `updated`, scroll listener, MutationObserver logic

---

## Scroll-to-Bottom Pill in Messages Container

**Commits:** `2f8b2fb6`, `7447546e`

A floating action pill appears in the bottom-right of the messages container once the user scrolls away from the bottom (e.g., reading back through a long conversation), and disappears when scrolling back near the bottom.

**Purpose:** Gives users a quick way to jump back to the latest messages without scrolling all the way down, especially useful for long or frequently-updated conversations.

**Behavior:**

- **Appears when:**
  - Container has overflowing content (`scrollHeight > clientHeight + 4px`)
  - User has scrolled away from bottom (not within 50px of the end)
- **Disappears when:**
  - User is within 50px of the bottom
  - User clicks the pill to scroll to bottom
- **No LiveView interaction:** Fully client-side via the AutoScroll hook — no round-trip to server

**Implementation (commit 7447546e):**

The `AutoScroll` hook manages pill visibility:
1. On mount: snapshots the pill element (`#scroll-to-bottom-pill`) via `getElementById`
2. On every scroll event: calls `_updatePill()` to check geometry and toggle visibility
3. On pill click: sets `shouldAutoScroll = true`, scrolls to bottom, and hides pill
4. On `updated()` (after LiveView patch): calls `_updatePill()` to recalculate visibility based on new content height
5. On destroy: removes pill click listener and cleans up references

**Pill visibility logic:**

```javascript
_updatePill() {
  if (!this._pill) return
  const scrollable = this.el.scrollHeight > this.el.clientHeight + 4
  this._pill.classList.toggle("hidden", this.shouldAutoScroll || !scrollable)
}
```

The pill is hidden if `shouldAutoScroll` is true OR the container doesn't have overflow.

**Scope Fix (commit 2f8b2fb6):**

The AutoScroll hook is mounted twice on the DM page:
1. On `#messages-container` (actual message list)
2. On `#codex-raw-lines` panel (collapsible raw JSONL view)

The pill lookup used a bare `getElementById`, so whichever hook instance mounted last controlled the shared pill — meaning the raw JSONL panel's scroll position could drive pill visibility instead of the message list. 

Fixed by scoping pill wiring to the `#messages-container` instance only. The hook now checks if its element ID matches `#messages-container` before claiming the pill:

```javascript
mounted() {
  // Only #messages-container's AutoScroll manages the pill
  this._pill = this.el.id === "messages-container" ? document.getElementById("scroll-to-bottom-pill") : null
}
```

**Files:**
- `assets/js/hooks/auto_scroll.js` — `_updatePill()`, pill click handler, cleanup
- `lib/eye_in_the_sky_web/components/dm_page/messages_tab.ex` — `#scroll-to-bottom-pill` element rendering

---

## DM Page Loading Skeleton on Mount

**Commit:** `95d0d1d6`

The DM page now displays a YouTube-style shimmer skeleton while the session file sync completes, instead of messages appearing incrementally. This prevents the "one by one" loading effect caused by a stream reset mid-render.

**Mount flow:**

1. **Initial render** (dead and connected both start here):
   - `assign_ui_flags/2` sets `syncing: true`
   - MessagesTab checks `@syncing` and renders skeleton instead of messages
   - `:grouped_messages` stream is initialized empty (critical for later stream_insert/stream reset calls)

2. **Connected render continues:**
   - A 5-second `Process.send_after` schedules a `:sync_timeout` failsafe
   - Async `Task.start` begins session file sync (calls `SessionImporter.sync`)
   - Task sends `{:sync_done, result}` message on completion (regardless of sync outcome)

3. **Sync task completes:**
   - `handle_info({:sync_done, _result}, socket)` dismisses skeleton (`syncing: false`)
   - `TabHelpers.force_reload_messages/2` loads all messages from DB in one pass
   - `push_event("new_message", %{})` triggers AutoScroll hook to re-anchor
   - Skeleton fades away; messages appear all at once

4. **Timeout failsafe:**
   - If Task takes > 5 seconds, `:sync_timeout` fires
   - `handle_info(:sync_timeout, %{assigns: %{syncing: true}}, socket)` dismisses skeleton and loads from DB
   - Prevents UI lock on large sessions or slow disk I/O
   - No-op if sync already completed before timeout fires

**Sync result states:**

The Task sends `{:sync_done, result}` with:
- `:clean` — No new messages imported from session file (0 inserted, 0 updated)
- `:dirty` — New messages imported (N inserted and/or updated); new messages appear with existing ones
- Error also sends `:clean` — treat import failure as no-op; messages load from DB unchanged

Both states trigger `force_reload_messages`, so messages always load from DB after sync completes, ensuring atomic all-at-once rendering.

**Skeleton UI:**

Renders 4 shimmer rows while `syncing: true`:
- **Avatar circle** — 28px rounded-full with base-content/10 opacity
- **Skeleton text lines** — 4 lines with varying widths (1/4, 11/12, 4/5 of container)
- **Pill tags** — 2 pseudo-pills below text lines with reduced opacity (base-content/6)
- **Animation** — `animate-pulse` class for continuous fade effect
- **Accessibility** — `aria-hidden="true"` prevents screen reader announcement

**Implementation files:**

- `lib/eye_in_the_sky_web/live/dm_live.ex` — mount, `handle_info({:sync_done, _})`, `handle_info(:sync_timeout, ...)`
- `lib/eye_in_the_sky_web/live/dm_live/mount_state.ex` — `assign_ui_flags/2` sets `syncing: true`
- `lib/eye_in_the_sky_web/live/dm_live/message_handlers.ex` — `load_messages_on_mount/1` orchestrates Task + timeout
- `lib/eye_in_the_sky_web/components/dm_page/messages_tab.ex` — `message_skeleton/1` component + guard on `@syncing`

**Why this approach:**

Previously, `load_messages_on_mount` had a race: both the mount Task sync and event-driven handlers (e.g., `handle_claude_complete`) could call `SessionImporter.sync` concurrently for active sessions. Both paths would read the same cursor before either committed, causing duplicate message inserts with distinct `source_uuid` values.

The skeleton defers all DB loads until after sync completes, eliminating the race entirely. For active sessions, the event-driven pipeline (`claude_complete → sync_and_reload`) handles imports; the mount Task only syncs when the session is already idle/finished.

**Gemini sessions** (`4ff24598`, `ace5897d`, `a5455b39`): `load_messages_on_mount/1` uses conditional sync. If the session has zero DB rows (JSONL-only session or cleared DB), `GeminiImporter.sync` runs from the JSONL file so history appears on first load. If the session already has DB rows, sync is skipped — the live-stream persistence path uses a different UUID space than JSONL turn IDs, so BulkImporter cannot dedup across them and would insert duplicates on every mount.

---

## Auto-Scroll Fix: Browser Scroll Restoration

**Commits:** `6e388fd1`, `cd52540c`

The AutoScroll hook now prevents browser scroll restoration from interfering with navigation-based scroll behavior.

**Problem:** When navigating between DM sessions, the browser's `history.scrollRestoration` can fire between the initial `mounted()` and the `sync_done` event. This stale scroll position tricks `beforeUpdate()` into calculating `shouldAutoScroll=false`, leaving the message view stuck at the top when new messages load.

**Solution (6e388fd1):**

1. **Set `history.scrollRestoration = 'manual'` in `AutoScroll.mounted()`**
   - Prevents the browser from restoring previous scroll positions during navigation
   - Saved as `_prevScrollRestoration` for restoration on cleanup
   - Restored to original value in `destroyed()` so other pages are unaffected

2. **Push `scroll_to_bottom` from sync_done instead of `new_message`**
   - New event handler in AutoScroll hook bypasses `shouldAutoScroll` flag
   - Unconditionally resets `shouldAutoScroll=true` and scrolls to bottom
   - Fired from `DmLive` after `sync_done` completes, ensuring landing at latest message on every mount

**Implementation:**

```javascript
// AutoScroll.mounted()
if (typeof history !== "undefined" && "scrollRestoration" in history) {
  this._prevScrollRestoration = history.scrollRestoration
  history.scrollRestoration = "manual"
}

// AutoScroll event handler
this.handleEvent("scroll_to_bottom", () => {
  this.shouldAutoScroll = true
  this.scrollToBottom()
})

// AutoScroll.destroyed()
if (typeof history !== "undefined" && this._prevScrollRestoration !== undefined) {
  history.scrollRestoration = this._prevScrollRestoration
}
```

**Files:**
- `assets/js/hooks/auto_scroll.js` — scroll restoration management and scroll_to_bottom handler
- `lib/eye_in_the_sky_web/live/dm_live.ex` — sync_done handler pushes scroll_to_bottom instead of new_message

---

## DM Height Chain Fix: Flex Layout Correction

**Commit:** `81e05028`

The `dm-live-root` element was missing flex layout classes, causing the entire DM page to scroll incorrectly.

**Problem:** Without height classes on `dm-live-root`, the `<main>` element remained the scroll container for the entire page. The AutoScroll hook on `messages-container` was targeting a container that wasn't actually the viewport scroll container. Messages would land in the wrong scroll position, and the composer would not stay pinned at the bottom.

**Solution:** Add `flex flex-col flex-1 min-h-0` to `dm-live-root` to restore the proper height chain:

```
<main>                          (flex-1 overflow-auto flex-col)
  <div id="dm-live-root">       (flex flex-col flex-1 min-h-0) ← ADD THESE
    <DmPage />
      <dm-tab-content>          (flex-1 min-h-0)
        <dm-messages-tab>       (flex-1 min-h-0 flex-col)
          <messages-container>  (flex-1 min-h-0 overflow-y-auto) ← scroll here
```

**Effect:**
- `dm-live-root` now fills the available space in `<main>`
- Height propagates down the flex chain to `messages-container`
- `messages-container` becomes the true scroll container (not `<main>`)
- AutoScroll hook fires against the correct scrollable element
- Composer stays pinned at bottom; messages-container is the only scrollable area

**Files:**
- `lib/eye_in_the_sky_web/live/dm_live.ex` — render() template with updated dm-live-root classes

---

## DM Interface Mode: PTY vs Web Chat Toggle

**Commit:** `52b81e02`

A new `dm_use_pty` settings toggle allows switching the DM interface between web chat and PTY-backed terminal modes.

**Setting:** `dm_use_pty` (boolean, default: `false`)

**Location:** Settings → General tab → Terminal section

**Behavior:**

- **`false` (default):** Web chat interface with message bubbles, markdown rendering, and rich formatting
- **`true`:** PTY-backed terminal interface embedded in the DM session, providing shell interaction

**UI Control:**

In `lib/eye_in_the_sky_web/live/overview_live/settings/general_tab.ex`, a new "Terminal" section appears with:
- Label: "Use PTY terminal in DM sessions"
- Description: "Replace the web chat interface with an embedded PTY terminal. Requires a page reload to take effect."
- Toggle control: DaisyUI checkbox (toggle-sm toggle-primary)
- Event handler: `toggle_setting` with key `"dm_use_pty"`

**Effect on DM Mount:**

When DmLive mounts, it checks the setting:

```elixir
use_pty = EyeInTheSky.Settings.get_boolean("dm_use_pty")

if connected?(socket) && use_pty do
  subscribe_dm_pty(socket, session.uuid)
else
  socket
end
```

- If `true` and connected: subscribes to PTY events, wiring the terminal interface
- If `false` or on dead render: uses standard web chat, skipping PTY subscription

**Page Reload Requirement:**

The setting requires a page reload to take effect because:
- PTY subscriptions are set up at mount time, not dynamically
- Changing the toggle mid-session doesn't swap the interface until page refresh
- UI note in settings clearly states this requirement

**Session creation branching on dm_use_pty (commit 7250ab9a):**

Previously, all three session creation callers unconditionally called `AgentManager.create_pty_session/1`, even when `dm_use_pty=false`. Because the DM page only subscribes to PTY output when `dm_use_pty=true` (default: false), newly created sessions would appear blank in web chat mode.

All three callers now branch on the setting at creation time:

```elixir
create_fn =
  if EyeInTheSky.Settings.get_boolean("dm_use_pty"),
    do: &AgentManager.create_pty_session/1,
    else: &AgentManager.create_agent/1
```

- `dm_use_pty=true` → `create_pty_session/1` (PTY-backed terminal interface)
- `dm_use_pty=false` → `create_agent/1` (SDK/messages mode, default)

**Callers updated:**
- `lib/eye_in_the_sky_web/live/agent_live/index_actions.ex`
- `lib/eye_in_the_sky_web/live/project_live/sessions/actions.ex`
- `lib/eye_in_the_sky_web/live/workspace_live/sessions/actions.ex`

**create_pty_session working directory fix (commit 7250ab9a):**

`AgentManager.create_pty_session/1` was using `opts[:project_path]` (the base project directory) as the working directory for the Claude launch command. This ignored the git worktree path resolved by `RecordBuilder` when a worktree had been created for the agent.

The function now uses `agent.git_worktree_path` with `opts[:project_path]` as fallback, matching the already-correct logic in `DmLive.build_launch_command`:

```elixir
working_path = agent.git_worktree_path || opts[:project_path]
```

**File:** `lib/eye_in_the_sky/agents/agent_manager.ex`

**Files:**
- `lib/eye_in_the_sky/settings.ex` — new setting `"dm_use_pty" => "false"` in defaults
- `lib/eye_in_the_sky_web/live/dm_live.ex` — conditional PTY subscription on mount
- `lib/eye_in_the_sky_web/live/overview_live/settings/general_tab.ex` — settings UI for toggle
- `lib/eye_in_the_sky/agents/agent_manager.ex` — worktree path fix and create_fn branch (commit 7250ab9a)
- `lib/eye_in_the_sky_web/live/agent_live/index_actions.ex` — branch on dm_use_pty (commit 7250ab9a)
- `lib/eye_in_the_sky_web/live/project_live/sessions/actions.ex` — branch on dm_use_pty (commit 7250ab9a)
- `lib/eye_in_the_sky_web/live/workspace_live/sessions/actions.ex` — branch on dm_use_pty (commit 7250ab9a)

---

## Gemini Reload + Sync (DM Toolbar)

**Commits:** `4ff24598`, `d94555c2`

The **Reload** and **Sync** toolbar buttons in the DM page work for Gemini sessions:

- **Reload** (`DmExportHelpers.handle_reload_from_session_file/2`, `"gemini"` branch): Reloads messages from the database directly. Does NOT read the JSONL file — `GeminiReader.read_messages` returns `{:error, :not_found}` in practice because the Gemini CLI uses a different session UUID space than EITS. The DB is authoritative since BulkImporter continuously syncs via the live-stream path.
- **Sync** (`MessageHandlers.sync_messages_from_session_file/1`, `"gemini"` branch): Calls `sync_gemini_async/3` which resolves the project path via `SessionHelpers.resolve_project_path/2` and runs `GeminiImporter.sync/3` from the JSONL file. Only useful for JSONL-only sessions (DB empty) — when rows already exist, the UUID space mismatch prevents dedup.

`sync_gemini_async/3` in `message_handlers.ex`:

```elixir
defp sync_gemini_async(session_id, session_uuid, session, agent) do
  project_path =
    case SessionHelpers.resolve_project_path(session, agent) do
      {:ok, path} -> path
      _ -> nil
    end

  GeminiImporter.sync(session_uuid, project_path, session_id)
end
```

---

## DM Page Settings Tab

**Commits:** `de1f085e` (UI), `c0550615` (persistence)

The DM page has a Settings tab with scope controls and provider-specific settings panels. Settings are persisted to the database via JSONB columns on sessions and agents.

**Tab structure:**
- **General subtab:** Global DM settings (thinking enabled, show live stream, max budget, notifications)
- **Claude subtab:** Claude-specific configurations
- **Codex subtab:** Codex-specific configurations

**Scope toggle:**
- **Session scope:** Settings apply to the current session only; stored in `sessions.settings` JSONB column
- **Agent scope:** Settings apply to all agents (persistent across sessions); stored in `agents.settings` JSONB column

**Settings persistence (commit c0550615):**

Settings are stored as JSONB overrides in two places:
- `sessions.settings` — session-level overrides
- `agents.settings` — agent-level overrides (apply as defaults to all sessions from that agent)

Effective settings are computed at read time via `JsonSettings.effective_settings/2`:
```elixir
effective = JsonSettings.effective_settings(agent_overrides, session_overrides)
# Result: app_defaults ⊕ agent_overrides ⊕ session_overrides
# Session overrides win; agent overrides are fallback; app defaults are base
```

**Settings schema:**

`EyeInTheSky.Settings.Schema` is the single source of truth for all settings:
- Dotted-key format: `"general.show_live_stream"`, `"anthropic.permission_mode"`, etc.
- Each setting has: type (bool/string/number), default value, namespace, and allowed scopes
- Schema.defaults provides the base map for all settings

**Event handlers (commits c0550615, e1ca21ea):**

Settings handlers were extracted into a dedicated `SettingsHandlers` module (commit e1ca21ea) to reduce DmLive size:
- `SettingsHandlers.persist_setting_update/4` — coerce value via `JsonSettings.coerce_value/3`, persist via `Sessions.put_setting/3` or `Agents.put_setting/3`, update assigns with fresh effective settings
- `SettingsHandlers.reset_scoped_settings/3` — clear overrides via `Sessions.reset_settings/1` or `Agents.reset_settings/1`, update assigns
- `SettingsHandlers.build_settings_assigns/2` — compute effective settings and build all three levels of assigns
- `SettingsHandlers.format_setting_error/2` — render friendly flash messages on bad input (invalid type, enum mismatch, scope violation)
- `DmLive` thin one-line handlers delegate to SettingsHandlers; `dm_live.ex` reduced from 746 to 631 lines

**Mount initialization (commit c0550615):**

`DmLive.MountState.assign_ui_flags/2` now:
1. Loads agent + session overrides from their `.settings` JSONB columns
2. Computes effective settings via `JsonSettings.effective_settings/2`
3. Assigns all three levels to the socket (`:dm_settings_effective`, `:dm_settings_agent_overrides`, `:dm_settings_session_overrides`)
4. Initializes runtime assigns (`:show_live_stream`, `:thinking_enabled`, `:max_budget_usd`, `:notify_on_stop`) from effective settings
5. Critical: reads keys directly from effective map to preserve literal `false` values (avoids `get_in(...) || default` pattern)

**Files:**
- `lib/eye_in_the_sky/settings/schema.ex` — Settings.Schema (single source of truth)
- `lib/eye_in_the_sky/settings/json_settings.ex` — JsonSettings module (pure logic: merge, put, get, delete, coerce)
- `lib/eye_in_the_sky/sessions.ex` — Sessions context gains put_setting, delete_setting, reset_settings, reset_settings_namespace
- `lib/eye_in_the_sky/agents.ex` — Agents context gains put_setting, delete_setting, reset_settings, reset_settings_namespace
- `lib/eye_in_the_sky_web/components/dm_page/settings_tab.ex` — settings UI component
- `lib/eye_in_the_sky_web/live/dm_live.ex` — thin event handlers delegating to SettingsHandlers
- `lib/eye_in_the_sky_web/live/dm_live/settings_handlers.ex` — settings persistence and helpers
- `lib/eye_in_the_sky_web/live/dm_live/mount_state.ex` — initialization with effective settings computation
- `priv/repo/migrations/20260504112139_add_settings_to_sessions_and_agents.exs` — migration adding settings JSONB columns

### DmSettings: Settings-to-CLI-Opts Bridge (commits `7dea1b91`, `a9da2669`, `620532f0`)

Three bug-fix commits wired effective settings all the way through to provider CLI opts, fixed scope display, and hardened the UI.

**`DmSettings` module (commit `7dea1b91`):**

`EyeInTheSky.Settings.DmSettings` is a new pure (no DB calls) module that converts an effective settings map into a keyword list of provider CLI opts:

```elixir
DmSettings.to_provider_opts(effective, "claude")
# → [permission_mode: "plan", max_turns: 10, bare: true, ...]

DmSettings.to_provider_opts(effective, "codex")
# → [full_auto: false, bypass_sandbox: false, ...]

DmSettings.to_provider_opts(effective, "pi")  # or any unknown provider
# → []
```

- Claude provider: maps all `anthropic.*` keys to CLI opts (permission_mode, max_turns, fallback_model, system_prompt, bare, verbose, sandbox, skip_permissions, chrome, etc.)
- Codex provider: maps `openai.*` keys (full_auto, bypass_sandbox, sandbox, ask_for_approval)
- Pi and unknown providers: return `[]` (no-op)
- `nil` settings values are filtered out; boolean `false` is preserved (important for `bypass_sandbox: false`)
- `chrome` string `"on"/"off"` converted to `true/false`

**`session_cli_opts` derived from settings (commit `7dea1b91`):**

Previously `session_cli_opts` was always initialized to `[]` on mount. Now:
- `MountState` calls `DmSettings.to_provider_opts(effective, provider)` on mount, so settings are applied immediately on page load
- `SettingsHandlers.build_settings_assigns/4` also calls `DmSettings.to_provider_opts` after any settings change, so updated settings take effect on the next message without a remount

**`bypass_sandbox` resolution bug fix (commit `7dea1b91`):**

`RuntimeContext.build/3` had `bypass_sandbox: opts[:bypass_sandbox] || provider == "codex"`. Because `false || true == true`, explicitly disabling bypass for a Codex session was silently ignored. Fixed with `Keyword.fetch/2` to distinguish nil (not set) from false (explicitly disabled):

```elixir
defp resolve_bypass_sandbox(opts, provider) do
  case Keyword.fetch(opts, :bypass_sandbox) do
    {:ok, val} -> val       # user explicitly set it — respect false
    :error -> provider == "codex"  # not set — default by provider
  end
end
```

**Scope-aware display (commit `a9da2669`):**

The Settings tab now renders inputs from the correct effective map for the active scope:
- **Session scope:** Uses the full merged effective map (defaults ⊕ agent ⊕ session)
- **Agent scope:** Uses agent-only effective map (defaults ⊕ agent, no session overrides)

Previously both scopes read from the merged effective map, so agent-scope inputs showed session-overridden values. The `dm_page.ex` component computes `dm_settings_agent_effective` (agent.settings only) and passes it alongside the merged `dm_settings_effective`. The `settings_tab` component picks `scoped_effective` based on the active scope.

General section inputs (`show_live_stream`, `thinking_enabled`, `max_budget_usd`, `notify_on_stop`) were also updated to read from `scoped_effective` instead of `session_state` assigns.

**Provider tab visibility fix (commit `a9da2669`):**

Tab visibility conditions changed from `!= provider` to `== provider`:
- "Claude flags" tab only shown when `provider == "claude"` (was hidden only for codex, showed for pi)
- "Codex flags" tab only shown when `provider == "codex"` (was hidden only for claude, showed for pi)
- Pi sessions now show only the General tab

**Subtab fallback guard (commit `a9da2669`):**

`active_subtab/2` now guards against nil and unknown subtabs, and provider mismatches for all three providers. A `catch-all` clause prevents `CaseClauseError`. Unknown or nil subtabs fall back to "general".

**Agent scope toggle uses agent-only map (commit `620532f0`):**

`SettingsHandlers.handle_setting_toggle/3` previously read the current value from `dm_settings_effective` (the merged map) regardless of scope. When scope is "agent", it now reads from `JsonSettings.effective_settings(dm_settings_agent_overrides, %{})` so the toggle flips the agent's own value, not the session-merged value.

**Stable DOM IDs (commit `a9da2669`):**

All interactive controls now have predictable IDs for testing and browser automation:
- Scope buttons: `dm-scope-session`, `dm-scope-agent`
- Subtab buttons: `dm-subtab-general`, `dm-subtab-anthropic`, `dm-subtab-openai`
- Reset button: `dm-settings-reset`
- All inputs/toggles/selects: `dm-setting-<dotted.key>` (e.g., `dm-setting-anthropic.permission_mode`)

**Agent scope button disabled when no agent (commit `a9da2669`):**

The "Agent default" scope button is `disabled` when no agent record is associated with the session.

**`from_pr` row session-scoped (commit `a9da2669`):**

The "From PR" row in the Claude flags subtab is only rendered when `scope == "session"`. It is hidden in agent scope because the schema restricts it to session-level writes only.

**`max_turns` integer constraint (commit `a9da2669`):**

The `max_turns` number input now uses `step="1" min="1"` (positive integer) instead of `step="0.01" min="0"` (float).

**Codex CLI: `--full-auto` removal (commit `620532f0`):**

Newer Codex versions removed `--full-auto`. The `Codex.CLI` module now expands the legacy `full_auto` setting to its current equivalent:
- `full_auto: true` → `--sandbox workspace-write -c approval_policy="on-request"`
- `full_auto: false` with explicit sandbox/approval → uses the provided values
- `on-failure` approval policy (legacy) is mapped to `on-request`

`DmSettings.to_provider_opts` for Codex was also extended to map `openai.sandbox` → `:sandbox` and `openai.ask_for_approval` → `:ask_for_approval`.

**`extra_cli_opts` merge fix (commit `620532f0`):**

Provider strategy `build_opts` functions previously concatenated `base_opts ++ optional_opts ++ extra`, so `extra_cli_opts` entries appended as duplicates instead of overriding. Changed to `Keyword.merge(base_opts ++ optional_opts, extra, ...)` with a custom resolver:
- `:append_system_prompt`: concatenates EITS prompt and custom prompt with `\n\n`
- All other keys: `extra_cli_opts` value wins

**Test coverage:**
- `test/eye_in_the_sky/settings/dm_settings_test.exs` — 27 unit tests for `DmSettings.to_provider_opts/2` covering Claude, Codex, and unknown providers
- `test/eye_in_the_sky/agents/runtime_context_test.exs` — 4 tests for `bypass_sandbox` resolution including the `false || true` edge case
- `test/eye_in_the_sky_web/live/dm_live/settings_handlers_test.exs` — 2 integration tests for `session_cli_opts` propagation after setting changes; 1 test for agent-scope toggle using agent-only map
- `test/eye_in_the_sky_web/components/dm_page/settings_tab_test.exs` — 38 focused component tests for scope display, tab visibility, fallback subtab, stable DOM IDs
- `test/eye_in_the_sky/claude/provider_strategy_settings_test.exs` — 2 tests verifying `extra_cli_opts` override strategy defaults for both Claude and Codex
- `test/eye_in_the_sky/codex/cli_test.exs` — updated tests: `--full-auto` replaced with sandbox/approval-policy equivalents

**Files:**
- `lib/eye_in_the_sky/settings/dm_settings.ex` — new `DmSettings` module
- `lib/eye_in_the_sky/agents/runtime_context.ex` — `resolve_bypass_sandbox/2` fix
- `lib/eye_in_the_sky_web/live/dm_live/mount_state.ex` — session_cli_opts from effective settings on mount
- `lib/eye_in_the_sky_web/live/dm_live/settings_handlers.ex` — session_cli_opts updated on setting change; agent-scope toggle reads agent map
- `lib/eye_in_the_sky_web/components/dm_page.ex` — computes `dm_settings_agent_effective` and `dm_settings_overrides`
- `lib/eye_in_the_sky_web/components/dm_page/settings_tab.ex` — scope-aware effective map, Pi tab fix, subtab fallback, stable IDs, from_pr guard, max_turns constraint
- `lib/eye_in_the_sky/claude/provider_strategy/claude.ex` — `build_opts` uses `Keyword.merge` with custom resolver
- `lib/eye_in_the_sky/claude/provider_strategy/codex.ex` — `build_opts` uses `Keyword.merge`
- `lib/eye_in_the_sky/codex/cli.ex` — `--full-auto` replaced with `--sandbox`/approval-policy expansion

---

## DM Component Refactoring

**Commits:** `6826708f`, `e1ca21ea`

### Module Extraction and Organization

**M2a: Tool widget extraction (6826708f)**
- Moved `tool_widget`, `tool_result_body`, `tool_widget_body` functions from `dm_message_components.ex` to new sub-module `dm_message_components/tool_widget.ex`
- Parent imports the new sub-module for cleaner organization
- Reduces main component file size without losing functionality

**M2b: Prompt queue extraction (6826708f)**
- Moved `prompt_queue/1` from `composer.ex` to new sub-module `composer/prompt_queue.ex`
- Composer delegates via `defdelegate` for transparent integration

**M3: Duplicate extract in dm_page (6826708f)**
- Extracted private `messages_tab_content/1` function in `dm_page.ex`
- Both "messages" and catch-all branches now call the single component instead of duplicating the attribute list
- Improves maintainability by centralizing attribute list

**L3: Crash guard on empty events (6826708f, e1ca21ea)**
- Added empty-list guard clause on `tool_cluster/1` in `messages_tab.ex`
- Prevents `List.first(@events).id` crash when events is `[]`
- Handles edge case where cluster is created with no events

**M5: Stream content guard (e1ca21ea)**
- Guard `stream_content` clear in `:do_message_reload` — only clear when `show_live_stream` is false or stream_content is already empty
- Prevents in-flight stream bubbles from being dismissed by a reload trigger
- Preserves ongoing live-stream display across message reloads

**Result:** DmLive reduced from 746 to 631 lines; improved code organization and reusability.

**L4: Redundant @impl true removal (ac2ff402)**
- Removed ~60 redundant `@impl true` annotations from `handle_event/3`, `handle_info/2` callbacks throughout DmLive
- These annotations were unnecessary since the module includes `use Phoenix.LiveView`, which establishes the default `@impl true` behavior for all callback functions
- Cleaning up the boilerplate reduces visual noise and improves readability without changing behavior
- Only removed where the default truly applies; any exceptional callback still retains explicit `@impl` if needed

**Code reduction:** Removing annotations across ~400 lines of callback definitions

---

## DmLive.Actions Module Extraction

**Commit:** `c01b76f9`

The `DmLive.Actions` module houses core `handle_event` callbacks extracted from `DmLive`, following the LiveView Action module extraction pattern to improve code organization and maintainability.

**Module location:** `lib/eye_in_the_sky_web/live/dm_live/actions.ex` (310 lines)

**Purpose:**
- Extracts general-purpose UI event handlers from the main LiveView file
- Keeps modal toggles, note creation, message pagination, file operations, and display mode toggles organized in a dedicated module
- Reduces cognitive load on the main `DmLive` file by separating concerns

**Event Categories Handled:**

1. **PTY Terminal Events**
   - `handle_pty_input/2` — Write data to PTY terminal
   - `handle_pty_resize/2` — Handle terminal resize with launch command firing

2. **Tab & UI Toggles**
   - `handle_change_tab/2` — Switch between Messages, Tasks, Notes, etc. tabs
   - `handle_toggle_context_meter/1` — Toggle context meter overlay
   - `handle_toggle_new_task_drawer/1` — Toggle new task modal

3. **Modal & Drawer Controls**
   - Overlay state management for task detail, effort menu, model selection
   - Drawer visibility toggles for task creation, note creation

4. **Message & File Operations**
   - Message pagination and list loading
   - File upload handling
   - Display mode toggles for diffs and commits

**Integration with DmLive:**

`DmLive` delegates event handling to `DmLive.Actions` via module imports:

```elixir
import EyeInTheSkyWeb.DmLive.Actions
```

Event handlers in `DmLive.handle_event/3` delegate to the appropriate action function:

```elixir
def handle_event("change_tab", params, socket) do
  handle_change_tab(socket, params)
end
```

**Related Modules:**

The Actions pattern is used alongside other extraction modules for complete DM feature organization:
- `DmLive.ExternalActions` — Third-party integrations (sessions, agents, etc.)
- `DmLive.TabHelpers` — Tab-specific logic (Messages, Tasks, Notes, Settings)
- `DmLive.FileAutocomplete` — File path autocomplete server logic
- `DmLive.MessageHandlers` — Message delivery and UI updates

**Type Specifications:**

All functions include `@spec` annotations for clarity:
```elixir
@spec handle_change_tab(Phoenix.LiveView.Socket.t(), map()) ::
  {:noreply, Phoenix.LiveView.Socket.t()}
```

**Pattern Established:**

This follows the LiveView Action module extraction pattern used elsewhere in the EITS codebase (e.g., `ProjectLive.Actions`, `AgentLive.Actions`). Extracting actions into dedicated modules:
- Improves code organization and discoverability
- Makes testing easier (can test handlers in isolation)
- Reduces main LiveView file bloat
- Establishes clear separation of concerns

**File:**
- `lib/eye_in_the_sky_web/live/dm_live/actions.ex` — Complete action handler module

---

## Desktop Top Bar

**Commits:** `d6c5ae2e`, `ef000cd3`, `b58104ad`, `fa1f2f94`, `37c837a9`

A desktop-only top bar appears above the main content area on the DM page, providing breadcrumb navigation, search access, and tab controls.

**Layout:**
- **Desktop:** Top bar displays with breadcrumb (project + section), search button, and DM tabs/search
- **Mobile:** Top bar is hidden (`md:flex`); mobile-only layout takes over
- **Position:** Rendered above `@inner_content` in `app.html.heex`

**DM-specific toolbar:**
- **Session breadcrumb:** Shows current project and "DM" section label
- **Message search:** Quick-search box for filtering messages in conversation
- **Tab pills:** Messages, Tasks, Commits, Notes, Context, Settings — desktop-only
- **No inline header card:** The DM page header card is now hidden on desktop (`md:block`)

**`...` dropdown menu (fa1f2f94):**

An ellipsis button in the toolbar opens an inline dropdown with session-level actions:

| Item | Event | Notes |
|------|-------|-------|
| Notify | `phx-hook="PushSetup"` | Bell button for push notification setup (commit 4ea00a18); also visible in mobile ActionMenu (commit d480a88e) |
| Reload | `JS.dispatch("dm:reload-check", ...)` | Opens reload-confirm modal |
| Export as Markdown | `export_markdown` | — |
| Schedule Message | `open_schedule_timer` | — |
| Cancel Schedule | `cancel_timer` | Only rendered when `dm_active_timer` is set |

**Notify button (commits 4ea00a18, d480a88e):**
- Integrated into topbar dropdown menu and mobile ActionMenu
- Uses `PushSetup` hook for browser notification setup
- Respects `notify_on_stop` flag from layout assigns
- Shows bell icon (hero-bell) in dropdown and mobile menus
- State attribute: `data-push-state` (disabled/enabled)
- Mobile ActionMenu now includes `show_push_setup` and `notify_on_stop` parameters to ensure button renders on small screens

**Breadcrumb generation:**
- Section label derived from `sidebar_tab` atom (`:dm` → "DM")
- Breadcrumb follows pattern: `Project › Section`

**Top bar attributes passed by DmLive:**
- `dm_active_tab` — current tab identifier
- `dm_session_name` — session name for breadcrumb
- `dm_message_search_query` — search filter text
- `dm_active_timer` — active schedule timer map; controls visibility of "Cancel Schedule" item

**Height calculation fix (b58104ad):**
- The top bar consumes `h-10` (2.5rem) of the main flex column
- The DM page height is now calculated as `md:h-[calc(100dvh-2.5rem)]` to match the parent container size
- Previously, the page height was computed as `100dvh - 2rem`, which caused an 8px overflow into the parent container
- With overflow-auto on main, this overflow made the main container scrollable, causing messages to be clipped and auto-scroll to land 8px short of the visual bottom

**Scroll fixes (37c837a9):**

*Navigation-aware scroll reset:*
- When navigating between sessions (not patching/submitting), reset `#main-content` scrollTop to 0 so the DM composer is always visible when entering a session
- Problem: Scrolling down the sessions list then clicking a session would leave `#main-content` scrolled, hiding the composer below the viewport
- Solution: `phx:page-loading-start` event now captures the navigation `kind` (navigate/patch/submit); `phx:page-loading-stop` resets scroll only on navigate
- Prevents accidental scroll state bleeding across different conversations

*Flex height chain fixes:*
- `dm-tab-content` div now has `flex flex-col` classes to ensure proper height distribution within the tab container
- `dm-messages-tab` changed from `h-full` to `flex-1 min-h-0` to participate in flex height constraints instead of filling arbitrary height
- The `min-h-0` override tells the flex container to collapse below its natural height, allowing sibling elements to constrain the viewport
- Without these changes, the messages container would either overflow its parent or fail to fill available space

**Files:**
- `assets/js/app.js` — navigation kind tracking and scroll reset on `phx:page-loading-stop`
- `lib/eye_in_the_sky_web/components/layouts.ex` — top_bar component with dm_toolbar private component
- `lib/eye_in_the_sky_web/components/layouts/app.html.heex` — top bar integration
- `lib/eye_in_the_sky_web/components/dm_page.ex` — DM page height calculation and dm-tab-content flex layout
- `lib/eye_in_the_sky_web/components/dm_page/messages_tab.ex` — messages tab flex height constraints

---

## Sessions Sidebar: Live Status Updates and Grouped Layout

**Commits:** `045fdac4`, `3095d561`, `f75e576d`

The DM sidebar sessions list displays agent status and relative time, grouped by activity level, with live updates via PubSub.

### Grouped Sessions Layout (commit 045fdac4)

**Session grouping:**
- **ACTIVE:** Up to 5 sessions with recent activity or "working" status
- **RECENT:** Up to 8 sessions sorted by last activity
- **Search mode:** Flat results list capped at 10 items

**Visual design:**
- Section labels with 2px accent-color left border and uppercase tracking-widest text
- "View all sessions →" footer link pinned to bottom of sessions section

**Features:**
- Search input remains visible; sort dropdown and "All" toggle removed
- Sessions section uses `flex-col` layout for internal scrolling while keeping footer sticky

**Implementation:**
- `lib/eye_in_the_sky_web/components/rail/flyout/sessions_section.ex` — grouping, filtering, and layout
- `lib/eye_in_the_sky_web/components/rail/flyout.ex` — integration with main flyout

### Session Status Display (commit f75e576d)

**Status and time metadata:**
- Session row shows **status badge** (working, idle, waiting, completed, failed) next to session name
- **Relative time** displays below session name (e.g., "3m ago", "just now")
- Status dot in top breadcrumb when `:dm_session_status` is set

**Implementation:**
- `mount_state.ex` — assigns `:session_status` on mount from `session.status`
- `agent_lifecycle.ex` — syncs `:session_status` on PubSub `session_updated` broadcasts
- `sessions_section.ex` — renders status badge and time secondary line

### Live PubSub Updates (commit 3095d561)

**Architecture:**
- `NavHook` already subscribes to `agents` topic (`agent_updated`, `agent_stopped`, `agent_created` broadcasts)
- `NavHook` forwards these events to `Rail` via `send_update/2`
- `Rail.handle_info/2` receives the update and replaces changed session in-place

**Targeted update path:**
```elixir
# In Rail component
def handle_info({:agent_updated, agent}, socket) do
  socket =
    update_flyout_sessions(socket, fn sessions ->
      Enum.map(sessions, &replace_if_matches(&1, agent))
    end)
  {:noreply, socket}
end
```

**Fallback for new sessions:**
- If a new session is not yet in the list, `Rail` triggers a full reload of the sessions list

**Bug Fix (commit f6dcd122):**
- Fixed `send_update/3` call in NavHook: was passing `"app-rail"` as pid; now uses `send_update/2` with `id` in assigns
- This prevented crashes when `agent_updated` broadcasts fired during DM page sessions

**Files:**
- `lib/eye_in_the_sky_web/components/rail.ex` — `handle_info` for targeted session updates
- `lib/eye_in_the_sky_web/live/nav_hook.ex` — PubSub subscription and `send_update/2` dispatch
- `lib/eye_in_the_sky_web/components/rail/flyout/sessions_section.ex` — status display

---

## DM Action Menu

**Commits:** `d6c5ae2e`, `ef000cd3`

The DM page overlay (timer controls, task detail) now includes an action menu button that exposes additional session-specific operations.

**Component:** `lib/eye_in_the_sky_web/components/dm_page/action_menu.ex`

**Menu items:**
1. **Copy Session UUID** — Displays first 8 characters of the session UUID and copies the full UUID to clipboard on click
2. **Pause/Resume timer** — Control timer state (if overlay_data.active_timer is set)
3. **Schedule task** — (if applicable)
4. **Reload check modal** — Explicitly trigger reload confirmation dialog

**Attributes:**
- `session_uuid` — optional; if present, adds the "Copy UUID" menu item
- `wrapper_id` — menu wrapper identifier (used in button ID generation)
- `cancel_btn_id` — required; ID of the cancel button for closing
- `active_timer` — timer state object
- `overlay_data` — overlay context
- `notify_on_stop` — whether to emit notification on timer stop

**Copy to Clipboard behavior:**
- Menu item shows: `Copy 1a2b3c4f…` (first 8 chars of UUID)
- Click copies full UUID to system clipboard
- Uses the `CopyToClipboard` LiveView hook

**File:**
- `lib/eye_in_the_sky_web/components/dm_page/action_menu.ex` — menu component

---

## DM Receivable Statuses

**Commits:** `eb55f37c` (idle added), `870f3e3a` (waiting added), `ee5b42e0` (terminated sessions now accepted)

The `/api/v1/dm` endpoint accepts messages destined for sessions in **any status**, including terminal ones.

**All statuses accept DMs:**
- `working` — message delivered live to the session worker
- `idle` — message delivered live to the session worker
- `waiting` — sdk-cli session queued for resume; DM is persisted and delivered on next wakeup
- `completed` / `failed` — message persisted directly via `DMDelivery.persist/4` (no live worker required); available for later polling or inspection

**Removed behavior (commit `ee5b42e0`):** The `@receivable_statuses` allowlist and `check_receiver_reachable/1` guard have been removed from `MessagingController`. Previously, DMs to `completed` or `failed` sessions returned `422 "Target session is terminated and cannot receive DMs"`. Now `DMDelivery.deliver_or_persist/4` is called instead, which routes to live delivery or direct persistence based on session status.

**File:**
- `lib/eye_in_the_sky/messaging/dm_delivery.ex` — `deliver_or_persist/4` routes based on status; `persist/4` for terminal sessions
- `lib/eye_in_the_sky_web/controllers/api/v1/messaging_controller.ex` — `do_dm/4` now calls `deliver_or_persist` with no status pre-check

---

## Duplicate Message Fix: Mount Task Race

**Commit:** `5fbe6c7f`

When the DM page mounted while a session was actively running, `load_messages_on_mount` launched an async `Task` that called `SessionImporter.sync` concurrently with the event-driven `handle_claude_complete`/`handle_agent_stopped` handlers. Both paths read the same `get_last_source_uuid` cursor before either committed. Because `agent_reply_already_recorded?` returned false for both, each inserted the same JSONL assistant entry with a distinct `source_uuid`. `on_conflict: :nothing` only deduplicates identical UUIDs, so both rows landed in the DB and the message rendered twice.

**Fix:** `load_messages_on_mount` skips the `Task.start` entirely when `session.status` is `"working"` or `"compacting"`. The event-driven pipeline (`claude_complete → sync_and_reload`) already handles all imports for active sessions; the Task sync is only needed for the "open DM page after session already finished" case.

**File:** `lib/eye_in_the_sky_web/live/dm_live/message_handlers.ex`

---

## Real-Time Update Fix: nil Guard in session_belongs_to?

**Commit:** `30ff5d60`

`session_belongs_to?(_session_id, nil)` returned `false`, so with `DISABLE_AUTH=true` (`current_user=nil`), `maybe_subscribe` short-circuited to `:unauthorized` and `setup_subscriptions` never ran. The LiveView mounted and rendered but held no PubSub subscription — all `{:new_message}` and `{:new_dm}` broadcasts were silently dropped.

**Fix:** Collapsed the two-clause function into a single always-true guard:

```elixir
defp session_belongs_to?(_session_id, _current_user), do: true
```

This allows access in both auth-enabled (any user) and auth-disabled (`current_user=nil`) modes. Future ownership enforcement requires adding `user_id` to the sessions table.

**File:** `lib/eye_in_the_sky_web/live/dm_live/mount_state.ex`

---

## Sessions.set_session_idle/1 Owns agent_stopped Event

**Commit:** `a8725252`

`Events.agent_stopped/1` is no longer fired directly from `DmSessionHelpers`. The call was moved into `Sessions.set_session_idle/1`, a new function in the Sessions context that atomically updates status to `"idle"` and fires the event with the updated session struct.

**Before:**
```elixir
# dm_session_helpers.ex — cancel/stop handler
Sessions.update_session(session, %{status: "idle"})
Events.agent_stopped(session)  # fired with stale pre-update struct
```

**After:**
```elixir
# Sessions context
def set_session_idle(%Session{} = session) do
  with {:ok, updated} <- update_session(session, %{status: "idle"}) do
    Events.agent_stopped(updated)  # updated struct guaranteed
    {:ok, updated}
  end
end

# dm_session_helpers.ex — cancel/stop handler
Sessions.set_session_idle(session)
```

**Why it matters:** The old pattern fired `agent_stopped` with the pre-update struct, so subscribers received stale status data. `set_session_idle/1` ensures the event always carries the post-update session. The `Events` alias was removed from `DmSessionHelpers` as it is no longer needed there.

**Files:**
- `lib/eye_in_the_sky/sessions.ex` — `set_session_idle/1` added
- `lib/eye_in_the_sky_web/live/shared/dm_session_helpers.ex` — `Events` alias removed; calls `Sessions.set_session_idle/1`

---

## DM Delivery Internals Cleanup

**Commit:** `5cc5e369`

Two dead-code wrappers were removed from `MessagingController`:

- `deliver_and_persist_dm/4` — one-line private function that delegated to `DMDelivery.deliver_and_persist/4`; all three call sites now call `DMDelivery.deliver_and_persist/4` directly
- `deliver_team_dm/4` — private wrapper for team broadcasts; inlined at the call site with proper error logging

`Settings.get_integer/1` no longer defines its own `parse_integer/1` helper; it now delegates to the shared `ToolHelpers.parse_int/1`.

**Files:**
- `lib/eye_in_the_sky_web/controllers/api/v1/messaging_controller.ex`
- `lib/eye_in_the_sky/settings.ex`

---

## DMDelivery: deliver_or_persist and persist

**Commit:** `ee5b42e0`

Two new public functions in `EyeInTheSky.Messaging.DMDelivery` handle DMs to sessions whose status cannot accept live delivery.

### deliver_or_persist/4

```elixir
def deliver_or_persist(to_session_id, from_session_id, body, metadata \\ %{})
```

Routes a DM based on the target session's current status:

- **Terminal session (`completed` or `failed`):** Calls `persist/4` directly. There is no live worker to accept the message, so it is stored straight to the durable inbox without attempting live delivery.
- **Non-terminal session (or session not found):** Falls through to `deliver_and_persist/4`, which delivers to the live worker and persists as before.

This replaces the previous behavior where DMs to terminated sessions were rejected outright at the API layer. Completed/failed sessions are still valid DM recipients — their messages are stored for later polling or inspection.

### persist/4

```elixir
def persist(to_session_id, from_session_id, body, metadata \\ %{})
```

Persists a DM directly to the messages table and broadcasts a `session_new_dm` PubSub event, without requiring a live session worker. This is the write path for CLI/headless sessions that poll their durable inbox, and for any session where live delivery is not possible.

Previously this logic was inlined inside `deliver_and_persist/4`; it is now a named public function so `deliver_or_persist/4` can call it independently.

**Files:**
- `lib/eye_in_the_sky/messaging/dm_delivery.ex` — `deliver_or_persist/4` and `persist/4`

---

## DM Response Fields: reachable and metadata

**Commit:** `15d2eb16` (reachable), `94215a51` (metadata)

The `/api/v1/dm` endpoint now includes two new fields in success responses:

### reachable

**Field type:** Boolean

**Meaning:** Indicates whether the target session is in a receivable status and the DM was delivered immediately (not queued).

**Values:**
- `true` — session is in `working`, `idle`, or `waiting` status; message delivered to reachable session
- `false` — (future) session is offline or in a non-receivable state; message queued or buffered

**Current behavior:** All successful DM responses have `reachable: true`. Terminated sessions (`completed` and `failed`) are accepted — `reachable: true` is returned after the message is persisted via `deliver_or_persist/4`. The field was originally intended to distinguish live vs. queued delivery; this distinction is now handled internally by `DMDelivery`.

### metadata

**Field type:** Optional object (JSONB)

**Meaning:** Structured context passed alongside the DM body, for agent-to-agent communication without JSON bleeding into the UI.

**Usage:** Agents can send:
- Message body: user-facing text (rendered in DM chat)
- Metadata object: structured data (passed to agent worker, never rendered in UI)

**Example request:**
```json
POST /api/v1/dm
{
  "to_session_id": "abc123",
  "message": "Task complete",
  "metadata": {
    "task_id": 42,
    "status": "done",
    "duration_ms": 1250
  }
}
```

**Pipeline:**
1. REST controller accepts optional `metadata` from request body
2. `DMDelivery.deliver_and_persist` merges metadata into the message record
3. On delivery to target session, `dm_metadata` is passed to `RuntimeContext.build()` and available to `AgentWorker` for processing
4. AgentWorker logs whether metadata was used vs. body-only delivery
5. DM LiveView templates render body only; metadata never exposed to UI

**Backward compatibility:** Legacy DMs without metadata work unchanged. Metadata is optional.

**Files:**
- `lib/eye_in_the_sky_web/controllers/api/v1/messaging_controller.ex` — request parsing
- `lib/eye_in_the_sky/messaging/dm_delivery.ex` — metadata propagation
- `lib/eye_in_the_sky/agents/runtime_context.ex` — RuntimeContext.build() type signature and dm_metadata field
- `lib/eye_in_the_sky/claude/agent_worker.ex` — logging on metadata use
- `docs/REST_API.md` — metadata field documentation and request examples

---

## DM Delivery Error Codes

**Commit:** `d2672eb9`

The `/api/v1/dm` endpoint now returns specific HTTP status codes and error codes for delivery failures instead of generic 500 errors. All error responses include a `reachable` boolean to distinguish "retry later" scenarios from permanent failures.

**Error responses:**

| Scenario | HTTP Status | Error Code | Reachable | Message | Action |
|----------|-------------|-----------|-----------|---------|--------|
| Target queue full | 503 | `queue_full` | `true` | "Target session queue is full; retry later" | Retry with backoff |
| Worker not found / not running | 503 | `target_session_unreachable` | `false` | "Target session worker is not running" | Don't retry (session is dead) |
| Worker crashed (exit) | 503 | `target_session_unreachable` | `false` | "Target session worker crashed" | Don't retry (session is dead) |
| Invalid message payload | 422 | `unprocessable_entity` | — | "Invalid message payload" | Fix the request |
| Unknown/other error | 503 | `delivery_failed` | `false` | "Failed to deliver message" | Don't retry (unknown condition) |

**Response format:**

All error responses (503 and 422) follow this structure:
```json
{
  "error": "<error_code>",
  "message": "<human-readable message>",
  "reachable": <true|false>  // Present on 503 errors only
}
```

**Caller behavior:**

- **`reachable: true` (queue_full):** Safe to retry with exponential backoff. Session will process the message once queue drains.
- **`reachable: false` (target_session_unreachable, delivery_failed):** Don't retry. Session worker is not running or unknown error occurred. Consider notifying the user or escalating.

**Implementation:**

In `MessagingController.do_dm/4`:
- Catch specific error atoms from `DMDelivery.deliver_and_persist/4`
- Return 503 with appropriate error code and reachable flag
- Log warnings (queue_full) or errors (worker exit, unknown) for observability
- Unknown errors default to `delivery_failed` with `reachable: false`

**File:**
- `lib/eye_in_the_sky_web/controllers/api/v1/messaging_controller.ex`

---

## Message Search: ILIKE → pg_search

**Commit:** `40c11471`

Full-text search (FTS) replaced the leading-wildcard ILIKE pattern in `search_messages_for_session/2`.

**Before:**
```elixir
Message
|> where([m], m.session_id == ^session_id)
|> where([m], ilike(m.body, ^"%#{query}%"))  # Full-table scan on messages.body
|> order_by([m], asc: m.inserted_at)
|> limit(100)
|> Repo.all()
```

**After:**
```elixir
PgSearch.search(
  table: "messages",
  schema: Message,
  query: query,
  search_columns: ["body"],
  sql_filter: "AND m.session_id = $2",
  sql_params: [session_id],
  fallback_query: fallback_query,  # Fallback to ILIKE on FTS failure
  preload: [:attachments],
  limit: 100
)
```

**Benefits:**
- FTS uses PostgreSQL GIN index on `messages` table (fast prefix matching)
- Eliminates full-table scan from leading-wildcard ILIKE
- Automatic fallback to ILIKE if FTS fails (existing pattern)
- Session filter pushed to database (via `sql_filter` parameter)

**File:**
- `lib/eye_in_the_sky/messages/listings.ex` — `search_messages_for_session/2`

---

## DM Page Performance Optimizations

**Commits:** `40c11471`, `1cf1fb88`

Two performance improvements reduce unnecessary DB queries and computations on page load.

### current_task Sentinel Fix (commit 40c11471)

**Problem:** `current_task` was initialized to `nil`. On every visit to the Messages or Tasks tab, the `tab_helpers` sentinel check would see `nil` and re-trigger `Tasks.get_current_task_for_session`, loading the current task even when already cached.

**Fix:** Changed sentinel from `nil` to `:not_loaded` atom.
- `assign_task_defaults` initializes `current_task: :not_loaded` 
- `tab_helpers` sentinel checks for `:not_loaded` instead of `nil`
- `dm_page` template guard changed to `is_struct/1` to safely handle `:not_loaded` on dead render
- Result: avoid redundant DB queries on tab navigation

**Files:**
- `lib/eye_in_the_sky_web/live/dm_live/mount_state.ex` — initialize to `:not_loaded`
- `lib/eye_in_the_sky_web/live/dm_live/tab_helpers.ex` — sentinel check
- `lib/eye_in_the_sky_web/components/dm_page.ex` — template guard

### Dead Render Optimization (commit 1cf1fb88)

**Problem:** `load_messages_on_mount` called `load_tab_data` on both dead (pre-connection) and connected renders. On dead render, `load_tab_data` would trigger `read_session_usage_stats` — either a filesystem read (SessionReader) or two aggregate DB queries (`total_tokens_for_session` + `total_cost_for_session`) over all messages in the session (up to 4.6k rows). This work was discarded when the WebSocket connected and the connected render ran `load_tab_data` again.

**Fix:** Added `load_messages_only/2` to TabHelpers.
- Dead render path: `load_messages_only(socket, session_id)` 
  - Loads messages + sets context assigns
  - Skips usage stats entirely (file read or aggregate DB queries)
- Connected render path: `load_tab_data(socket, "messages", session_id)` (unchanged)
  - Loads messages AND usage stats
  - Stats are now persisted and used

**Result:** Dead render is now lightweight; connected render handles the full load.

**Files:**
- `lib/eye_in_the_sky_web/live/dm_live/message_handlers.ex` — routing to correct load path
- `lib/eye_in_the_sky_web/live/dm_live/tab_helpers.ex` — `load_messages_only/2` function

---

## Performance Considerations

**Streaming:**
- Messages streamed via PubSub (not polling)
- Only visible messages rendered (virtualization for large chats)
- Token count updated incrementally

**Updates:**
- Debounced PubSub broadcasts (100ms) to reduce re-renders
- Only affected rows re-rendered in agent list
- New messages use stream append (not full re-render)

**Search:**
- FTS via pg_search with GIN index (commit 40c11471)
- Fallback to ILIKE if FTS fails

**Mount Optimization:**
- `current_task` sentinel fix prevents redundant task queries on tab navigation (commit 40c11471)
- Dead render skips expensive usage stats load (commit 1cf1fb88)

**Limits:**
- Max 1000 messages per session (paginated on scroll)
- Max 100 agents visible at once (paginated/searchable)

---

## Note Creation and Editing

**LiveView:** `lib/eye_in_the_sky_web_web/live/note_live/new.ex`
**Full Editor Hook:** `assets/js/hooks/note_full_editor.js`
**Notes Contexts:** `lib/eye_in_the_sky_web_web/live/overview_live/notes.ex`, `lib/eye_in_the_sky_web_web/live/project_live/notes.ex`, `lib/eye_in_the_sky_web_web/live/dm_live.ex`

### Create Note on DM Page (commit 33931330)

**Trigger:** "Create Note" button on the DM page Notes tab (visible when notes empty or exist).

**Features:**
- **Modal dialog** for creating notes with optional title and required body
- **Title input**: Auto-focused placeholder, optional
- **Body textarea**: Rich text area for note content
- **Modal controls**: Escape key or cancel button closes modal

**Flow:**
1. User clicks "Create Note" button on DM Notes tab
2. Modal opens with focus on title input
3. User enters optional title and required body
4. Submit button creates note via `create_dm_note` event handler
5. Modal closes and notes list refreshes automatically
6. Note appears in DM Notes tab with session context

**Parent Type Resolution:**
- **DM page notes**: Creates with `parent_type: "session"`, `parent_id: <session.id>`
- Notes are scoped to the current DM session

**Success/Error Feedback:**
- Success: "Note created" flash message; notes tab reloads automatically
- Error: "Failed to create note" flash message displays error details

**Implementation:**
```elixir
# DmLive event handler
def handle_event("create_dm_note", %{"title" => title, "body" => body}, socket) do
  case Notes.create_note(%{
    parent_type: "session",
    parent_id: socket.assigns.session.id,
    title: title,
    body: body,
    starred: false
  }) do
    {:ok, _note} ->
      socket
      |> put_flash(:info, "Note created")
      |> assign(:show_create_note_modal, false)
      |> load_tab_data("notes", socket.assigns.session.id)
      |> {:noreply, _}
    {:error, _changeset} ->
      put_flash(socket, :error, "Failed to create note")
  end
end
```

### Quick Note Modal (Overview & Project Pages)

**Trigger:** "Quick Note" button in notes list (available on overview and project notes pages).

**Features:**
- **Title input**: Auto-focused, placeholder "Title...", required
- **Body textarea**: 4 rows, placeholder "Note content..."
- **Starred checkbox**: Optional, star this note immediately
- **Modal controls**: Escape key or cancel button closes modal

**Flow:**
1. User clicks "Quick Note" button
2. Modal opens with focus on title input
3. User enters title and body
4. Submit button creates note via `create_quick_note` event
5. Modal closes and notes list reloads
6. Note appears in list with parent type set

**Parent Type Resolution:**
- **Overview notes page**: Creates with `parent_type: "system"`, `parent_id: "0"`
- **Project notes page**: Creates with `parent_type: "project"`, `parent_id: <project.id>`

**Implementation:**
```elixir
# handle_event("create_quick_note", params, socket)
case Notes.create_note(%{
  parent_type: parent_type,
  parent_id: parent_id,
  title: params["title"],
  body: params["body"],
  starred: starred
}) do
  {:ok, _note} -> socket |> assign(:show_quick_note_modal, false) |> load_notes()
  {:error, _changeset} -> put_flash(socket, :error, "Failed to create note")
end
```

---

### New Note CodeMirror Editor

**Page:** `/notes/new` (full-screen editor)

**Features:**
- **CodeMirror 6 editor**: Markdown syntax highlighting
- **Title field**: Editable in header, updates via `update_title` event
- **Save handler**: Cmd+S (Mod+S) triggers `note_saved` event
- **Escape handler**: Returns to previous page (`return_to` param)
- **Status bar**: Shows current line and column (Ln X, Col Y)
- **Line numbers**: Line number gutter on left
- **Active line highlight**: Current line highlighted
- **Line wrapping**: Enabled for better readability

**Query Parameters:**
- `parent_type`: One of "session", "task", "agent", "project", "system" (defaults to "system")
- `parent_id`: Parent resource ID (defaults to "0")
- `return_to`: Safe redirect path after save (validated against whitelist)

**Parent Type Resolution:**
Valid parent types are validated in mount/handle_params:
```elixir
@valid_parent_types ["session", "task", "agent", "project", "system"]

parent_type =
  if params["parent_type"] in @valid_parent_types, do: params["parent_type"], else: "system"
```

Invalid parent types default to "system". This ensures notes are always assigned to a valid scope.

**Return-To Validation:**
Safe redirects are validated against a whitelist to prevent open redirect attacks:
```elixir
@valid_return_paths ["/notes", ~r|^/projects/\d+/notes$|]

defp safe_return_to(path) when is_binary(path) do
  if String.starts_with?(path, "/") and
       Enum.any?(@valid_return_paths, fn
         p when is_binary(p) -> p == path
         r -> Regex.match?(r, path)
       end),
     do: path,
     else: "/notes"
end
```

Only `/notes` and `/projects/:id/notes` paths are allowed. All other paths default to `/notes`.

**CodeMirror Hook Integration:**

The `NoteFullEditorHook` initializes a full-screen CodeMirror editor with markdown support:

```javascript
// assets/js/hooks/note_full_editor.js
export const NoteFullEditorHook = {
  mounted() {
    // Initialize CodeMirror with:
    // - markdown() syntax highlighting
    // - Line numbers and active line highlight
    // - History undo/redo
    // - Cmd+S to save (pushes "note_saved" event)
    // - Escape to navigate back
    // - Status bar updates (Ln/Col)
  }
}
```

**Save Handler:**
When user presses Cmd+S or clicks the Save button, the hook:
1. Collects editor content via `view.state.doc.toString()`
2. Pushes `note_saved` event with body content
3. LiveView creates note with validated parent_type and parent_id
4. On success, redirects to safe return path
5. On error, displays flash message "Failed to create note"

**Keyboard Shortcuts:**
| Shortcut | Action |
|----------|--------|
| `Cmd/Ctrl + S` | Save note and redirect |
| `Escape` | Go back without saving |
| `Tab` (in title) | Focus editor |
| `Cmd/Ctrl + Z` | Undo |
| `Cmd/Ctrl + Shift + Z` | Redo |

---

## Blocking DM Wait Endpoint

**Commit:** `5836ef77`

`GET /api/v1/dm/wait` long-polls for the next inbound DM for the requesting session. Returns as soon as a DM arrives (via PubSub `session:#{id}` `:new_dm` broadcast) or after the timeout elapses.

**Query params:**

| Param | Type | Default | Description |
|-------|------|---------|-------------|
| `session` | string | from `x-eits-session` header | Session UUID or integer ID to wait on |
| `since` | ISO 8601 datetime | — | Only return DMs received after this timestamp |
| `timeout` | integer (seconds) | 25 | Server-side wait cap; max 55 |

**Responses:**

- `200 OK` with `{"items":[...],"count":1}` — DM arrived before timeout
- `200 OK` with `{"items":[],"count":0}` — Timeout elapsed with no DM

No busy-polling: the connection is held open until a PubSub event fires or the timeout fires. The client HTTP timeout should be set to at least `timeout + 15` seconds to avoid cutting the long-poll short locally.

**`eits dm wait` subcommand** wraps this endpoint. It blocks until a DM lands and prints the result, letting a background process exit immediately instead of interval-polling `dm inbox`. Pass `--team-only` to restrict delivery to messages from sessions sharing a team with the current agent: the subcommand loops internally — each long-poll iteration filters by team membership, and if all polled messages are filtered out with time remaining, it advances the `since` cursor to the last message's `inserted_at` and re-polls until a team message arrives or the timeout elapses.

**Files:**
- `lib/eye_in_the_sky_web/controllers/api/v1/messaging_controller.ex` — `wait_for_dm/2` action
- `lib/eye_in_the_sky_web/router.ex` — `GET /api/v1/dm/wait`
- `crates/eits-cli/src/commands/dm.rs` — `eits dm wait` subcommand

---

## DM Read Authorization

**Commit:** `64b6b81d`

`GET /api/v1/dm` (list) and `GET /api/v1/dm/:id` (show) now enforce that the caller is the intended recipient.

**How it works:**

- The caller is identified by the `x-eits-session` header (UUID or integer ID).
- For `GET /api/v1/dm`: the header is resolved and compared against the queried session. A mismatch returns `403 Forbidden`.
- For `GET /api/v1/dm/:id`: the `session` query param was removed; only the `x-eits-session` header is accepted. The resolved caller must match `msg.to_session_id`.
- Missing or unresolvable header always returns `403 Forbidden` — no anonymous reads.

**Error response:**
```json
HTTP 403 Forbidden
{"error": "You are not the recipient of this message"}
```

**Duplicate alert suppression:** A companion fix suppresses duplicate flash alerts that could appear when authorization failures were retried by the LiveView reconnect logic.

**Files:**
- `lib/eye_in_the_sky_web/controllers/api/v1/messaging_controller.ex` — `authorize_session_recipient/2` replaces `authorize_dm_recipient/2`; `show_dm/2` no longer accepts `session` query param

---

## Settings Tab: Input Population from Effective Settings

**Commit:** `efe62f68`

The DM page settings tab now populates all input fields from saved effective settings on load, ensuring users see their current configuration values instead of blank/default states.

**Problem solved:**
Previously, settings inputs were blank on load. Users had to manually re-enter values when editing, making it unclear what the current setting actually was. The effective settings (merged from session, project, and global scopes) were stored but not reflected in the UI.

**Solution:**

Added a new `dm_settings_effective` assign that passes the effective settings map through the component hierarchy:

1. **DmLive.mount** — Loads effective settings and assigns to socket as `dm_settings_effective`
2. **DmPage component** — Accepts `:dm_settings_effective` attr and passes to SettingsTab
3. **SettingsTab component** — Accepts `:effective` attr and passes to subsections (anthropic_section, openai_section)
4. **Individual setting components** — Uses `setting_val(@effective, "key")` helper to populate input values from the map

**Helper function:**

```elixir
defp setting_val(effective_map, key) when is_map(effective_map) do
  Map.get(effective_map, key) || Map.get(effective_map, String.to_atom(key))
end
```

Returns the value from the effective settings map, or nil if not present. Fallback to `nil` allows inputs to show their placeholder text when no value is set.

**Updated inputs:**

All Anthropic/OpenAI settings inputs now use `setting_val`:
- `anthropic.permission_mode` — populated from effective settings (defaults to "acceptEdits" if nil)
- `anthropic.max_turns` — populated from effective settings (shows placeholder "No limit" if nil)
- `anthropic.fallback_model` — populated from effective settings (defaults to "" if nil)
- `anthropic.from_pr` — populated from effective settings (shows placeholder if nil)
- `anthropic.json_schema` — populated from effective settings (shows placeholder if nil)
- All OpenAI settings follow the same pattern

**User experience:**

- On settings tab open, all inputs show their current value (or placeholder if not set)
- Users immediately see what the effective setting is before making changes
- No ambiguity between "not set" (placeholder) vs "set to value" (displayed value)
- Scope selector still allows switching between session/project/global views

**Files:**
- `lib/eye_in_the_sky_web/components/dm_page.ex` — DmPage component passes `dm_settings_effective`
- `lib/eye_in_the_sky_web/components/dm_page/settings_tab.ex` — SettingsTab receives `effective` attr, all subsections and inputs use `setting_val` helper

---

## Session Auto-Naming

**Commits:** `89f5ca56` (merge), `33106b6a`

When a new session is created from `/dm/new`, the session is automatically named based on the user's opening message using Haiku, mirroring the Tauri desktop app naming lifecycle.

### Flow

1. User clicks **+** on the sessions flyout → navigates to `/dm/new?project_id=X`
2. User types a first message and submits the form
3. `MessageHandlers.do_spawn_new_session/2` runs:
   - Sets `fallback_name = String.slice(body, 0, 60)` (first 60 chars of the message)
   - Creates agent + session records via `AgentManager.create_agent_without_start/1` (DB records only — no worker started yet)
   - Stores `{body, send_opts}` in `PendingSessionMessages` ETS store (60 s TTL, atomic `pop/1`)
   - Fires `Task.start` to run `Sessions.Naming.try_auto_name/3` asynchronously
   - `push_navigate` to `/dm/:session_id`
4. `DmLive` mounts on `/dm/:session_id`, `handle_params/3` pops `{body, send_opts}` from `PendingSessionMessages` and sends `{:auto_send, body, send_opts}` to self
5. `handle_info({:auto_send, body, send_opts})` merges `send_opts` into `:session_cli_opts` and calls `MessageHandlers.handle_send_message/2` — this starts the `AgentWorker`
6. Concurrently, `try_auto_name/3` calls the Anthropic API and writes the generated name back

### Naming Module (`Sessions.Naming`)

**File:** `lib/eye_in_the_sky/sessions/naming.ex`

| Field | Value |
|-------|-------|
| Model | `claude-haiku-4-5-20251001` |
| Prompt window | First 200 chars of opening message |
| Max name length | 60 chars |
| Max tokens (response) | 20 |
| API timeout | 10 s |
| Auth | `ANTHROPIC_API_KEY` env var (non-fatal if absent) |

**System prompt:**
```
You are a chat-session namer. Output ONLY a short descriptive name
(3–6 words, noun-preferring, no quotes, no markdown, no trailing punctuation).
Nothing else — just the name on a single line.
```

**Atomic write guard:** `try_auto_name/3` uses a `WHERE name = fallback_name` clause in `Repo.update_all`. If the user renames the session before Haiku responds, the update is a no-op — no TOCTOU race.

**Non-fatal:** Any error path (missing API key, network timeout, API error, empty response) is silently swallowed via `else _ -> :ok`. The session retains the fallback name (first 60 chars of opening message) on failure.

**PubSub:** On a successful write, `Events.broadcast_rail_session_updated/1` fires, updating the session name in the rail flyout in real time.

### PendingSessionMessages (`EyeInTheSky.PendingSessionMessages`)

**File:** `lib/eye_in_the_sky/pending_session_messages.ex`

ETS-backed one-shot store that bridges the gap between session creation (on `/dm/new`) and the first message send (after navigate to `/dm/:id`). Prevents the message body from living in the URL.

| Function | Behavior |
|----------|----------|
| `put(session_id, body, send_opts)` | Stores `{body, send_opts}` with 60 s TTL |
| `pop(session_id)` | Atomic `:ets.take` — returns `{body, send_opts}` or `nil`, consumed once |

`send_opts` carries `eits_workflow: "0"` plus any session-level CLI opts the user had active (plan mode, sandbox, etc.).

### Why No Worker on Create

`create_agent_without_start/1` calls only `RecordBuilder.create_records/1` — it does not start an `AgentWorker`. The worker starts on the first `continue_session/3` call inside `handle_send_message`, which runs after the navigate. This avoids a race where the worker would start with no message to process.

**Files:**
- `lib/eye_in_the_sky/sessions/naming.ex` — Haiku API call, atomic DB write, PubSub broadcast
- `lib/eye_in_the_sky/pending_session_messages.ex` — ETS one-shot store, 60 s TTL
- `lib/eye_in_the_sky_web/live/dm_live/message_handlers.ex` — `do_spawn_new_session/2`, `:new` handler
- `lib/eye_in_the_sky_web/live/dm_live.ex` — `handle_params/3` pops pending message, `handle_info({:auto_send})` sends it
- `lib/eye_in_the_sky_web/components/new_dm_page.ex` — `/dm/new` composer UI (bottom-pinned, full controls)
- `lib/eye_in_the_sky_web/components/rail/flyout.ex` — `+` button routes to `/dm/new?project_id=X`

---

## /dm/new: Blank Composer for New Sessions

**Commits:** `f7220927`, `4369d4ed`, `89f5ff92`, `89f5ca56`, `368aaab9`, `927c7ea0`, `33106b6a`

### Overview

`/dm/new?project_id=<id>` is a blank DM page where users compose the first message before a session is created. The session is created only when the user sends, keeping the session list clean and naming the session from the opening message.

### Route

```
GET /dm/new
```

Added to `router.ex`. Requires a `?project_id=<integer>` query parameter. Renders the existing `DmLive` LiveView under the `:new` action.

### DmLive :new Action

**File:** `lib/eye_in_the_sky_web/live/dm_live.ex`

Mount clause (`mount/3`) dispatched when no `session_id` param is present:
1. Parses `project_id` from query params
2. Calls `Projects.get_project/1` — redirects to `/` if the project doesn't exist or the param is missing
3. Assigns `:live_action` = `:new`, `:new_session_project_id`, and all default composer assigns via `MountState.assign_new_session_defaults/1`

`handle_params/3` is a no-op for `:new` (only fires the ETS drain on `:show` navigation).

`render/1` dispatches to `NewDmPage.new_dm_page/1` when `live_action == :new`.

### NewDmPage Component

**File:** `lib/eye_in_the_sky_web/components/new_dm_page.ex`

A minimal composer-only page with no title, subtitle, or session metadata:
- Rounded border matching the DM composer design
- Model selector pill (reads `selected_model` from assigns)
- Send button
- `processing` spinner state

The page intentionally has no heading — the composer floats in a blank screen, ready for input.

### Send Handler: Spawning the Session

**File:** `lib/eye_in_the_sky_web/live/dm_live/message_handlers.ex`

`handle_send_message/2` has a new clause for `live_action: :new`:
1. Trims the body; ignores empty sends
2. Calls `AgentManager.create_agent_without_start/1` — creates the `Agent` + `Session` DB records without starting a Claude worker process
3. Stores the body in `PendingSessionMessages` (ETS, 60 s TTL) keyed by `session.id`
4. Spawns a background `Task` to auto-name the session via `Sessions.Naming.try_auto_name/3`
5. Calls `push_navigate/2` to redirect to `/dm/<session_id>`

When `DmLive` mounts for that session ID (`:show`), `handle_params/3` calls `PendingSessionMessages.pop/1`, which returns `{body, send_opts}`. A `send/2` to `self()` queues `{:auto_send, body, send_opts}`, which `handle_info/2` delivers as a normal `send_message` — this starts the Claude worker and sends the first prompt.

### AgentManager.create_agent_without_start/1

**File:** `lib/eye_in_the_sky/agents/agent_manager.ex`

```elixir
def create_agent_without_start(opts) do
  RecordBuilder.create_records(opts)
end
```

Creates the `Agent` and `Session` DB rows (same as `create_agent/1`) but does **not** start the AgentWorker. The worker is started on the first `continue_session` call via `SessionBridge.ensure_worker_running/2`, which happens when `handle_send_message` processes the `{:auto_send, ...}` message.

### PendingSessionMessages ETS Store

**File:** `lib/eye_in_the_sky/pending_session_messages.ex`

GenServer-backed ETS table (`:pending_session_messages`) that buffers the initial message body and send opts until the session mounts and drains them.

| Function | Behavior |
|----------|----------|
| `put(session_id, body, send_opts)` | Stores `{body, send_opts}` with a 60 s monotonic TTL; overwrites any existing entry |
| `pop(session_id)` | Atomically deletes and returns `{body, send_opts}`, or `nil` if absent or expired |

The 60 s TTL handles the case where a user navigates away before the redirect completes — the pending entry expires without leaving stale data.

### Sessions.Naming: Haiku Auto-Naming

**File:** `lib/eye_in_the_sky/sessions/naming.ex`

Calls `claude-haiku-4-5` via the Anthropic Messages API to generate a concise 3–6 word session name from the opening message body.

```
try_auto_name(session_id, body, fallback_name)
```

- Sends the first 200 characters of `body` to Haiku with a strict system prompt: output only the name, nothing else
- Uses an atomic `UPDATE … WHERE name = ^fallback_name` to avoid overwriting a user-edited name (no TOCTOU window)
- Broadcasts `Events.broadcast_rail_session_updated/1` on success so the rail sidebar updates immediately
- Silent on failure (`:no_api_key`, API error, empty response) — `fallback_name` (first 60 chars of body) stays

Requires `ANTHROPIC_API_KEY` in the server environment. The renaming task runs in a detached `Task` so it never blocks the redirect.

### Rail: New Session Navigation

**File:** `lib/eye_in_the_sky_web/components/rail/project_actions.ex`

`handle_new_session_navigate/2` checks the `dm_use_pty` setting:
- **`true`** → creates agent immediately and navigates to `/dm/<id>` (existing fast-path)
- **`false`** (default) → navigates to `/dm/new?project_id=<id>` (blank composer flow)

This setting controls whether users land on a ready-to-talk session (PTY mode) or the blank composer first.

### Files

| File | Role |
|------|------|
| `lib/eye_in_the_sky_web/router.ex` | `GET /dm/new` route |
| `lib/eye_in_the_sky_web/live/dm_live.ex` | `:new` mount clause, `handle_params`, `handle_info({:auto_send})`, render branch |
| `lib/eye_in_the_sky_web/live/dm_live/mount_state.ex` | `assign_new_session_defaults/1` |
| `lib/eye_in_the_sky_web/live/dm_live/message_handlers.ex` | `handle_send_message` `:new` clause, `do_spawn_new_session/2` |
| `lib/eye_in_the_sky_web/components/new_dm_page.ex` | Blank composer component |
| `lib/eye_in_the_sky/agents/agent_manager.ex` | `create_agent_without_start/1` |
| `lib/eye_in_the_sky/pending_session_messages.ex` | ETS body buffer GenServer |
| `lib/eye_in_the_sky/sessions/naming.ex` | Haiku auto-naming via Anthropic API |
| `lib/eye_in_the_sky_web/components/rail/project_actions.ex` | `handle_new_session_navigate/2` routing |
| `test/eye_in_the_sky_web/live/dm_live_new_test.exs` | LiveView + PendingSessionMessages + Naming tests |
