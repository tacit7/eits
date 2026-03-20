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

**Display:** Message stream with agent context.

**Features:**
- Chronological message view (newest at bottom)
- Agent name + timestamp on each message
- Syntax highlighting for code blocks
- Markdown rendering (via Marked.js)
- Mention support (@agent mentions)

**Message types:**
- User messages (input)
- Agent messages (responses, analysis)
- System messages (task started, completed, etc.)
- Tool use logs (if enabled)

**Streaming:**
- Messages streamed from agent worker via PubSub
- Live update as agent sends chunks

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

## Real-Time Updates

**PubSub subscriptions:**
- `agents` — monitor all agent state changes
- `session:<current_session_id>:status` — monitor current session
- `messages:<session_id>` — incoming messages from agent

**Message broadcasting:**
- On every message: `{:message_added, message}` to `session:<id>:status` topic
- Includes full message object with tokens, type, content

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

**Top bar (Claude-style minimal design):**
- Simplified header with session name only
- Removed unlimited placeholder and token counter display
- Tab navigation in mobile overflow menu for additional features
- Agent status indicator in top bar

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
