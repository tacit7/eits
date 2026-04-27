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

**Display:** Message stream with agent context, bubble-style rendering.

**Features:**
- Chronological message view (newest at bottom)
- Bubble-style message rendering (right-aligned user, left-aligned agent)
- Timestamps: hover-only at 9px via group-hover (desktop only, always visible on mobile)
- Syntax highlighting for code blocks
- Markdown rendering (via Marked.js)
- Mention support (@agent mentions)

**Message styling:**
- **User messages**: right-aligned bubble with bg-base-200, rounded-2xl, 3px padding
- **Agent messages**: left-aligned plain text, text-base-content/90
- **Agent model/cost badges**: Inline below agent message body (restored commit a3f4c3a1)
  - Model name in monospace badge (e.g., `claude-opus-4-6`)
  - Cost in USD (e.g., `$0.0045`) when metadata present
- **Tool events** (tool_result, tool_use): max-w-[70%] compact widget, no bubble, no timestamp
- **DM indicator**: primary/20 border on user DM bubbles
- **Spacing**: space-y-1 between messages (compact layout)

**Message types:**
- User messages (input)
- Agent messages (responses, analysis)
- System messages (task started, completed, etc.)
- Tool use logs and results (collapsible, details-closed by default)

**Streaming:**
- Messages streamed from agent worker via PubSub
- Live update as agent sends chunks
- Stream shows provider avatar (Claude or Codex) with thinking/tool indicators

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

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| `Cmd/Ctrl + Enter` | Send message |
| `Escape` | Close drawer (new agent/task) |
| `Cmd/Ctrl + K` | Search agents/tasks |
| `Cmd/Ctrl + N` | New agent |
| `Cmd/Ctrl + T` | New task |

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

**DM deduplication window split (commit 2dfddb77):**
- **Live DM path:** 60-second window for `dm_already_recorded?/3`
  - Prevents re-ingesting a DM that was forwarded to the local CLI and bounced back
  - Uses `Messages.find_recent_dm/3` with a tight time window
- **File import path:** 86400-second (24-hour) window when `importing_from_file?: true`
  - Used by Claude and Codex `SessionImporter` to safely replay session history
  - Avoids false deduplication on legitimate messages with the same content

**Body-match fallback removed (commit 58e557e9):**
- Previously, messages without a `source_uuid` would fall back to body matching for dedup
- Now, only `source_uuid` is used for primary dedup; body matching is not a fallback
- `find_unlinked_import_candidate/3` (renamed from `find_unlinked_message/3`) is used only by `BulkImporter` to retroactively link pre-existing rows that were created before a `source_uuid` was available

**Callsites:**
- **DM receive:** `Messages.record_incoming_reply/4` sets `source_uuid` on agent responses
- **File import:** `BulkImporter.import_messages/3` uses source UUIDs from session files
- **Dedup index:** Partial composite index on `(session_id, sender_role, body, inserted_at) WHERE source_uuid IS NULL` accelerates the unlinked-message lookup for older data

**Use case:** End-to-end tracking via `source_uuid` makes message deduplication reliable across spawned agents, file replays, and CLI tools—retries are safe.

---

## Tool Result Message UI

**Commits:** `76d6d61e`, `677a0c78`

Tool result messages in the DM chat have special UI treatment to reduce visual clutter.

**Display rules:**
- **Output closed by default**: `<details>` element renders without the `open` attribute, so tool output is collapsed
- **Empty output skipped**: When body is blank/whitespace, the widget is not rendered at all
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
- `lib/eye_in_the_sky_web/components/dm_helpers.ex` — parsing functions
- `lib/eye_in_the_sky_web/components/dm_message_components.ex` — chip rendering
- `lib/eye_in_the_sky/agents/cmd_dispatcher/dm_handler.ex` — DM body construction

---

## Format Toolbar

**Commit:** `fb46a50c`

A markdown format toolbar (Aa button) in the DM composer enables inline text formatting.

**Trigger:** Click the "Aa" button in the left toolbar to show/hide the format strip.

**Format actions and shortcuts:**
| Action | Marker | Keyboard |
|--------|--------|----------|
| Bold | `**text**` | Cmd+B |
| Italic | `*text*` | Cmd+I |
| Strikethrough | `~~text~~` | None |
| Inline code | `` `text` `` | Cmd+E |
| Code block | ``` `text` ``` | Cmd+Shift+E |
| Link | `[text](url)` | None |

**Behavior:**
- Hidden by default; format bar slides in when Aa is clicked
- Buttons wrap/unwrap selected text with markdown syntax
- If selection is already wrapped, clicking the button removes the markers (toggle)
- For links, the URL placeholder is auto-selected after insertion so user can type the URL
- Correct cursor placement for empty selections (marker pair inserted and cursor centered)

**Implementation:** 
- `lib/eye_in_the_sky_web/components/dm_page/composer.ex` — HEEx format bar
- `assets/js/hooks/dm_composer.js` — selection wrapping logic, keyboard handlers (Cmd+B/I/E, Cmd+Shift+E)

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

**Commit:** `de1f085e`

The DM page now has a sixth tab (Settings) with scope controls and provider-specific settings panels.

**Tab structure:**
- **General subtab:** Global DM settings
- **Claude subtab:** Claude-specific configurations
- **Codex subtab:** Codex-specific configurations

**Scope toggle:**
- **Session scope:** Settings apply to the current session only
- **Agent scope:** Settings apply to all agents (persistent across sessions)

**Current state (mockup):**
- UI is fully rendered and styled
- Event handlers (`dm_setting_scope`, `dm_setting_subtab`, `dm_setting_update`, `reset_dm_settings`) are stubbed
- Changes write to socket assigns only; no persistence yet
- JSONB persistence layer (schema + API) planned for future iteration

**Files:**
- `lib/eye_in_the_sky_web/components/dm_page.ex` — tab registration
- `lib/eye_in_the_sky_web/components/dm_page/settings_tab.ex` — settings UI component
- `lib/eye_in_the_sky_web/live/dm_live.ex` — event handlers

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
| Reload | `JS.dispatch("dm:reload-check", ...)` | Opens reload-confirm modal |
| Export as Markdown | `export_markdown` | — |
| Schedule Message | `open_schedule_timer` | — |
| Cancel Schedule | `cancel_timer` | Only rendered when `dm_active_timer` is set |

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

**Commit:** `eb55f37c`

The `/api/v1/dm` endpoint now accepts messages from sessions in the `idle` status in addition to `working` and `waiting`.

**Allowed statuses:**
- `working` — agent actively processing
- `idle` — agent waiting for input (newly added)
- `waiting` — agent queued for resources

**Rejected statuses:**
- `completed` — session terminated; cannot send DMs
- `failed` — session errored; cannot send DMs

**File:**
- `lib/eye_in_the_sky_web/controllers/api/v1/messaging_controller.ex` — `do_dm/4` status allowlist

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

## Performance Considerations

**Streaming:**
- Messages streamed via PubSub (not polling)
- Only visible messages rendered (virtualization for large chats)
- Token count updated incrementally

**Updates:**
- Debounced PubSub broadcasts (100ms) to reduce re-renders
- Only affected rows re-rendered in agent list
- New messages use stream append (not full re-render)

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
