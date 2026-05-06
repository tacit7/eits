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

## Real-Time Updates

**PubSub subscriptions:**
- `agents` — monitor all agent state changes
- `session:<current_session_id>:status` — monitor current session
- `messages:<session_id>` — incoming messages from agent

**Message broadcasting:**
- On every message: `{:message_added, message}` to `session:<id>:status` topic
- Includes full message object with tokens, type, content
- Broadcast triggered by `NotifyListener` (Postgres LISTEN/NOTIFY) instead of polling

**Handler:**
```elixir
def handle_info({:message_added, message}, socket) do
  # Update messages stream
  # Update token count display
  # Scroll to newest message
  {:noreply, update_view(socket, message)}
end
```

---

## File Upload & Attachments

**Feature:** Drag-and-drop file upload in chat input.

**Supported:**
- Text files (markdown, code, logs)
- Images (PNG, JPG, for analysis)
- PDFs (for document review)

**Flow:**
1. User drags file into chat input zone
2. File uploaded to temp storage
3. URL injected into message context (not sent as attachment, embedded in prompt)
4. Agent receives file content in message body

**Limitations:**
- File size capped at 20 MB
- Only types listed above supported

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

### @@ Agent Autocomplete

**Trigger:** Type `@@` to autocomplete agent names from the current workspace.

**Behavior:**
- Client-side autocomplete (no server call)
- Filters agent list by typed prefix
- Selects and inserts agent name into message
- Remapped from original `@` trigger to avoid conflict with file autocomplete

**Implementation:**
- Client-side filtering in `assets/js/hooks/slash_command_popup.js`
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
| `@@` | Trigger agent autocomplete in composer |

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

## DM Message Bubble Format with Sender Chip

**Commits:** `4e0b0f12`, `677a0c78`, `16b3a213`, `6edecd7e`

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
- DM messages show a sender chip with hero-cpu-chip icon
- Chip displays agent name and `#session_id` (integer ID when available)
- Status pill shows done/failed state if present
- Clickable URL chip if a status URL is detected
- User DM bubbles have primary/20 border for visual distinction

**Implementation files:**
- `lib/eye_in_the_sky_web/components/dm_helpers.ex` — parsing functions and shared component helpers
- `lib/eye_in_the_sky_web/components/dm_message_components.ex` — chip rendering
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

The DM composer is the message input area at the bottom of the DM page, with context display, format toolbar, and inline autocomplete.

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

### Composer Autocomplete and History

See **Composer Autocomplete: @ File and @@ Agent** (above) for file and agent name completion.

See **DM Composer: localStorage History Persistence** and **Keyboard History Navigation** (below) for message history and recall.

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

## Copy-to-Clipboard

**Commits:** `d04b7f63`, `10d75ff3`

DM messages and tool call/output blocks expose a clipboard icon on hover for one-click copy.

**Coverage:**
- DM message bodies (rendered markdown)
- Tool call widgets: BASH, Edit, Write
- Tool output blocks

**Implementation:**
- `MarkdownMessage` hook injects the clipboard icon after markdown renders
- A global capture-phase click listener intercepts the icon click before it reaches the surrounding `<details>` element, preventing accidental expand/collapse toggling
- Copy uses the Clipboard API with a transient "copied" state on the icon

---

## Auto-Scroll Across LiveView Patches

**Commits:** `08fdbac0`, `fd56f6fd`

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

**Files:**
- `assets/js/hooks/auto_scroll.js` — `beforeUpdate`, `updated`, scroll listener, and `ResizeObserver` logic

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

**Event handlers (commit c0550615):**

`DmLive` handlers now persist settings to the scoped record:
- `dm_setting_update/4` — coerce value via `JsonSettings.coerce_value/3`, persist via `Sessions.put_setting/3` or `Agents.put_setting/3`, update assigns with fresh effective settings
- `reset_dm_settings/3` — clear overrides via `Sessions.reset_settings/1` or `Agents.reset_settings/1`, update assigns
- Error handling: friendly flash messages on bad input (invalid type, enum mismatch, scope violation)

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
- `lib/eye_in_the_sky_web/live/dm_live.ex` — event handlers (dm_setting_update, reset_dm_settings)
- `lib/eye_in_the_sky_web/live/dm_live/mount_state.ex` — initialization with effective settings computation
- `priv/repo/migrations/20260504112139_add_settings_to_sessions_and_agents.exs` — migration adding settings JSONB columns

---

## Desktop Top Bar

**Commits:** `d6c5ae2e`, `ef000cd3`, `b58104ad`, `fa1f2f94`

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

**Files:**
- `lib/eye_in_the_sky_web/components/layouts.ex` — top_bar component with dm_toolbar private component
- `lib/eye_in_the_sky_web/components/layouts/app.html.heex` — top bar integration
- `lib/eye_in_the_sky_web/components/dm_page.ex` — DM page height calculation

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

**Commits:** `eb55f37c` (idle added), `870f3e3a` (waiting added)

The `/api/v1/dm` endpoint accepts messages destined for sessions in any non-terminal status.

**Allowed statuses (`@receivable_statuses`):**
- `working` — agent actively processing
- `idle` — agent waiting for input
- `waiting` — sdk-cli session ended and queued for resume; DM is persisted and delivered on next wakeup. Blocking this status caused false 422s when agents tried to reach headless sessions between turns.

**Rejected statuses (terminal):**
- `completed` — session finished; cannot receive DMs
- `failed` — session errored; cannot receive DMs

**Error message on rejection:** `"Target session is terminated (completed or failed) and cannot receive DMs"`

**File:**
- `lib/eye_in_the_sky_web/controllers/api/v1/messaging_controller.ex` — `@receivable_statuses` module attribute and `do_dm/4`

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

## DM Response Fields: reachable and metadata

**Commit:** `15d2eb16` (reachable), `94215a51` (metadata)

The `/api/v1/dm` endpoint now includes two new fields in success responses:

### reachable

**Field type:** Boolean

**Meaning:** Indicates whether the target session is in a receivable status and the DM was delivered immediately (not queued).

**Values:**
- `true` — session is in `working`, `idle`, or `waiting` status; message delivered to reachable session
- `false` — (future) session is offline or in a non-receivable state; message queued or buffered

**Current behavior:** All successful DM responses have `reachable: true` while only `completed` and `failed` statuses are rejected. Future iterations may support queue-to-unreachable sessions.

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
**Notes Contexts:** `lib/eye_in_the_sky_web_web/live/overview_live/notes.ex`, `lib/eye_in_the_sky_web_web/live/project_live/notes.ex`

### Quick Note Modal

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
