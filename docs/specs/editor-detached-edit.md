# Spec: Detached Edit — Open DB Content in External Editor

## Problem

Notes, tasks, and prompts are database records. Their content fields
(note.body, task.description, prompt.prompt_text) can be long. The in-app
CodeMirror editor works, but users want to edit in their editor of choice
with their full setup (plugins, keybindings, LSP, etc.).

## Approach

Write content to a stable temp file, open it in the chosen editor, watch for
saves, write changes back to the DB. Same split-button UX as agents/skills.

**Scope:** This feature is intended for the single-user local app only. It
must not be enabled in shared hosted deployments without per-user temp
directories and access control.

---

## Temp File Paths

```
{System.tmp_dir!()}/eits/{instance_namespace}/note-{id}.md
{System.tmp_dir!()}/eits/{instance_namespace}/task-{id}.md
{System.tmp_dir!()}/eits/{instance_namespace}/prompt-{id}.md
```

`instance_namespace` is generated once at application start — 8 bytes of
`crypto.strong_rand_bytes/1`, Base64url-encoded — and stored in
`:persistent_term` under `{EyeInTheSky, :instance_namespace}`. It is not
persisted across restarts. A small accessor function reads it:

```elixir
EyeInTheSky.Instance.namespace()
```

This prevents collisions across concurrent app instances without ETS overhead.

Prompt slug is NOT used as identity — slugs can change, may not be globally
unique, and may contain path-hostile characters. `prompt.id` is always the
unique key. A sanitized slug may be appended for readability only:
`prompt-{id}-{safe_slug}.md`, where `safe_slug` passes through
`[a-z0-9_-]` allowlist only.

---

## Content Mapping

| Resource | Content field        | Update function           | DB key        |
|----------|----------------------|---------------------------|---------------|
| Note     | `note.body`          | `Notes.update_note/2`     | `body`        |
| Task     | `task.description`   | `Tasks.update_task/2`     | `description` |
| Prompt   | `prompt.prompt_text` | `Prompts.update_prompt/2` | `prompt_text` |

Note `title` is NOT exported — body only. Title editing stays in-app.

The type-to-field mapping, path construction, and update attr construction
are centralized in private helpers within `EditorSync`:

```elixir
defp path_for(type, id, namespace)    # -> String.t()
defp content_for(type, record)        # -> String.t()
defp update_attrs_for(type, content)  # -> map()
```

These are the only places the `case type do :note -> ... :task -> ...` pattern
appears. All other code calls them.

---

## New Module: `EyeInTheSky.EditorSync`

### Public API

```elixir
@spec open(:note | :task | :prompt, record_id :: term(), editor_id :: String.t()) ::
        {:ok, label :: String.t()} | {:error, reason :: term()}
def open(type, record_id, editor_id)
```

Takes type + id, not the full record struct. `EditorSync` owns loading the
record, resolving the field, computing the path, launching the editor, and
starting the watcher. LiveViews pass identity only.

`EditorSync` never accepts a path from the client or LiveView. It constructs
the temp path internally from trusted type/id values. No external path
allowlist check is needed for DB-backed content.

Authorization remains the caller's responsibility in v1. LiveViews only pass
ids for records already loaded through their normal project-scoped queries.

### Steps inside `open/3`

1. Load the current record using the non-raising getter
   (`Notes.get_note/1`, etc.). Return `{:error, :not_found}` if nil.
2. Compute temp path from `{type, id, namespace}`.
3. Check Registry for an existing watcher keyed by `{:editor_sync, type, id}`:
   - **If active:** open the existing temp file in the editor without
     overwriting it. Return `{:ok, label}`.
   - **If not active:**
     a. Write current DB content to temp path (creating
        `{System.tmp_dir!()}/eits/{namespace}/` if needed).
     b. Start and register the watcher via `DynamicSupervisor`.
     c. Launch the editor via `Editors.open_path/2`.
     d. If editor launch fails, stop the watcher and remove the registry
        entry before returning `{:error, reason}`.
4. Return `{:ok, label}`.

### Error Formatting

User-facing errors are normalized through a small helper rather than
interpolating raw internal terms:

```elixir
defp format_error(:not_found),     do: "Record not found"
defp format_error(:not_installed), do: "Editor not installed"
defp format_error(_),              do: "Could not open editor"
```

### Watcher Uniqueness

A Registry keyed by `{:editor_sync, type, record_id}` ensures only one watcher
runs per record. Opening the same record again reuses the existing watcher and
file without overwriting in-progress edits.

```elixir
EyeInTheSky.EditorSync.Supervisor  # DynamicSupervisor
EyeInTheSky.EditorSync.Registry    # Registry, keys: :unique
```

Both are added to the application supervision tree.

### Watcher State

```elixir
%{
  type: :note | :task | :prompt,
  record_id: term(),
  tmp_path: String.t(),
  last_hash: binary(),             # SHA-256 of last synced content
  last_change_ms: integer(),       # System.monotonic_time(:millisecond)
  missing_count: non_neg_integer(),
  poll_interval_ms: pos_integer(), # default 500; injectable for tests
  idle_timeout_ms: pos_integer()   # default 30 minutes; injectable for tests
}
```

All elapsed-time checks use `System.monotonic_time(:millisecond)` — not wall
clock — so system clock changes and DST do not affect timeout behavior.

`last_change_ms` is initialized to `System.monotonic_time(:millisecond)` at
watcher start.

### Poll Loop (`Process.send_after/3` at `poll_interval_ms`)

```
every poll:
  1. stat(tmp_path):
     - missing: increment missing_count
       if missing_count >= 5: stop watcher silently (atomic-save tolerance)
     - present: reset missing_count to 0
  2. read content
  3. if {mtime, size} unchanged from last stat: skip hash (fast path)
  4. hash = SHA-256(content)
  5. if hash == last_hash: no-op
  6. if hash != last_hash:
     - reload record by id using non-raising getter
     - if nil: broadcast editor_sync_failed(:record_deleted), stop
     - update only the mapped content field
     - on DB error: broadcast editor_sync_failed(reason), stop
     - on success: broadcast record_updated, store new hash, update last_change_ms
  7. if monotonic_now - last_change_ms > idle_timeout_ms: stop watcher silently
```

**Idle timeout definition (Option A):** idle means no content changes
successfully synced. Same-content saves do not reset the timer.

### Sync-Back: Reload by ID

The watcher reloads the current record by id before each write. It never
trusts the originally captured struct. Only the mapped content field is
updated; all other fields are untouched.

---

## PubSub Events

Add to `EyeInTheSky.Events`:

```elixir
# Note
def subscribe_note(note_id), do: subscribe("note:#{note_id}")
def note_updated(note), do: broadcast("note:#{note.id}", {:note_updated, note})

# Prompt
def subscribe_prompt(prompt_id), do: subscribe("prompt:#{prompt_id}")
def prompt_updated(prompt), do: broadcast("prompt:#{prompt.id}", {:prompt_updated, prompt})

# Sync failure — all types use record-specific topic
def editor_sync_failed(type, id, reason) do
  broadcast("#{type}:#{id}", {:editor_sync_failed, type, id, reason})
end
```

A private `record_topic(type, id)` helper centralizes topic construction:

```elixir
defp record_topic(type, id), do: "#{type}:#{id}"
```

**Tasks:** `task_updated` already broadcasts on `"tasks:#{project_id}"`.
Sync failures broadcast on `"task:#{id}"` (singular). Task detail LiveViews
must subscribe to both:

```elixir
Events.subscribe("tasks:#{project_id}")
Events.subscribe("task:#{task.id}")
```

Update `Notes.update_note/2` and `Prompts.update_prompt/2` to call
`Events.note_updated/1` and `Events.prompt_updated/1` after a successful write.

---

## LiveView Integration

### Mount Assigns (same as agents/skills)

```elixir
|> assign(:installed_editors, Editors.detect_installed())
|> assign(:preferred_editor, Settings.get("preferred_editor") || "code")
```

### Subscriptions

Subscribe when selection changes, not only at mount:

```elixir
def handle_event("select_note", %{"id" => id}, socket) do
  case Notes.get_note(id) do
    nil -> {:noreply, socket}
    note ->
      if connected?(socket), do: Events.subscribe_note(note.id)
      {:noreply, assign(socket, :selected_note, note)}
  end
end
```

Unsubscribing on deselect is optional in v1 — `handle_info` guards by id
to prevent stale updates from affecting the wrong selection.

### Event Handler

```elixir
def handle_event("open_in_editor", %{"editor" => editor_id}, socket) do
  record = socket.assigns.selected_{note|task|prompt}
  case EditorSync.open(:note, record.id, editor_id) do
    {:ok, label} ->
      {:noreply, put_flash(socket, :info, "Opened in #{label} — saves sync automatically")}
    {:error, reason} ->
      {:noreply, put_flash(socket, :error, EditorSync.format_error(reason))}
  end
end
```

### handle_info

Guard all updates by whether the record is still selected:

```elixir
def handle_info({:note_updated, note}, socket) do
  if socket.assigns.selected_note && socket.assigns.selected_note.id == note.id do
    {:noreply, assign(socket, :selected_note, note)}
  else
    {:noreply, socket}
  end
end

def handle_info({:editor_sync_failed, :note, id, _reason}, socket) do
  if socket.assigns.selected_note && socket.assigns.selected_note.id == id do
    {:noreply, put_flash(socket, :error, "Editor sync failed — check your editor")}
  else
    {:noreply, socket}
  end
end
```

Same pattern for task and prompt.

### In-App Conflict

In v1, if a user is editing in CodeMirror while an external save arrives, the
`assign` from the PubSub update wins (last-write-wins). The LiveView must not
crash. Dirty-state detection is v2.

---

## Component Changes: `OpenInEditorButton`

Add a mutually exclusive second mode. Exactly one of `path` (file-backed) or
`record_id` (DB-backed) must be set — never both, never neither:

```elixir
attr :path,      :string,  default: nil
attr :record_id, :integer, default: nil  # or :string if ids are UUIDs
```

Validation at render time:

```elixir
if is_nil(assigns.path) == is_nil(assigns.record_id) do
  raise "OpenInEditorButton: exactly one of path or record_id is required"
end
```

The emitted event is the same (`open_in_editor`). For file mode, `phx-value-path`
is set. For record mode, `phx-value-id` is set. The parent LiveView's handler
checks which value is present and dispatches to `Editors.open/2` or
`EditorSync.open/3` accordingly.

Use `:integer` for `record_id` if all DB ids are integers. `:any` is too loose.

---

## Pages to Wire

| Page | File | Record assign | Content field |
|------|------|---------------|---------------|
| Project Notes | `project_live/notes.ex` | `@selected_note` | `body` |
| Project Tasks | `project_live/tasks.ex` | via `task_detail_drawer` | `description` |
| Project Prompts | `project_live/prompts.ex` | `@selected_prompt` | `prompt_text` |
| Overview Prompts | `overview_live/prompts.ex` | `@selected_prompt` only if detail panel exists | `prompt_text` |

**Tasks:** button lives in `task_detail_drawer.ex` (where description is
rendered). Handler lives in `project_live/tasks.ex`. The drawer emits the
event; the LiveView owns the selected task and calls `EditorSync.open/3`.

**Overview Prompts:** wired only if `/prompts` has a selected-prompt detail
panel showing `prompt_text`. If the page is list-only, skip it in v1.

---

## Error Handling

| Failure | Behavior |
|---------|----------|
| Record not found during `open/3` | `{:error, :not_found}` immediately |
| Editor not installed | `{:error, :not_installed}` immediately — no file written |
| Temp dir/file write fails | `{:error, reason}` immediately |
| Editor launch fails after watcher start | Stop watcher, remove registry entry, return `{:error, reason}` |
| DB write fails on sync | Log, broadcast `{:editor_sync_failed, type, id, reason}`, stop watcher |
| Record deleted while watcher active | Log, broadcast failure, stop watcher |
| File missing briefly (atomic editor save) | Tolerate up to 5 consecutive missing polls (~2.5s) |
| File missing persistently | Stop watcher silently |
| 30-min idle (no content changes synced) | Stop watcher silently |
| Duplicate open, same record | Open existing file, reuse watcher, no overwrite |
| Two different editors, same record | Last write wins — acceptable v1 limitation |

---

## Tests

### Unit: path, content, and update attr mapping

- note id → `note-{id}.md`, content from `body`, attrs `%{body: content}`
- task id → `task-{id}.md`, content from `description`, attrs `%{description: content}`
- prompt id → `prompt-{id}.md`, content from `prompt_text`, attrs `%{prompt_text: content}`
- prompt slug appended as sanitized suffix; id is the stable key
- unknown type → `{:error, :unknown_type}`

### Watcher behavior

Use a real temp directory. Pass `poll_interval_ms: 50` and
`idle_timeout_ms: 500` to keep tests fast.

- writes initial DB content to temp file
- detects content change and calls correct DB update
- does not write when content hash is unchanged (same-content save)
- missing file: tolerates < 5 consecutive misses, exits after 5
- idle timeout: exits after configured timeout with no content change
- idle timer does not reset on same-content saves
- DB write failure: broadcasts `editor_sync_failed`, stops
- record deleted mid-watch: stops cleanly, broadcasts failure
- duplicate open: does not start second watcher
- duplicate open: does not rewrite temp file
- duplicate open: still calls `Editors.open_path/2` to reopen file in editor
- editor launch failure after watcher start: watcher is stopped, error returned

### LiveView/event

- `open_in_editor` with valid record → calls `EditorSync.open/3`, flashes info
- `open_in_editor` with not-installed editor → flashes formatted error
- `open_in_editor` with missing record → flashes formatted error
- `{:note_updated, note}` with matching selected id → updates `selected_note`
- `{:note_updated, note}` with non-matching id → no state change
- `{:editor_sync_failed, ...}` with matching id → flashes error
- `{:editor_sync_failed, ...}` with non-matching id → no change

### `OpenInEditorButton`

- raises if both `path` and `record_id` are set
- raises if neither `path` nor `record_id` is set
- file mode: emits `phx-value-path`, no `phx-value-id`
- record mode: emits `phx-value-id`, no `phx-value-path`

---

## Files to Create / Modify

**New:**
- `lib/eye_in_the_sky/editor_sync.ex` — public API, path/content helpers
- `lib/eye_in_the_sky/editor_sync/watcher.ex` — GenServer poll loop
- `lib/eye_in_the_sky/instance.ex` — `namespace/0` backed by `:persistent_term`
- `test/eye_in_the_sky/editor_sync_test.exs`

**Modify:**
- `lib/eye_in_the_sky/application.ex` — add `EditorSync.Supervisor`,
  `EditorSync.Registry`, and `Instance` initialization to supervision tree
- `lib/eye_in_the_sky/events.ex` — add `subscribe_note`, `note_updated`,
  `subscribe_prompt`, `prompt_updated`, `editor_sync_failed`, `record_topic/2`
- `lib/eye_in_the_sky/notes.ex` — broadcast after `update_note`; use
  non-raising getter (`get_note/1`)
- `lib/eye_in_the_sky/prompts.ex` — broadcast after `update_prompt`; use
  non-raising getter (`get_prompt/1`)
- `lib/eye_in_the_sky_web/components/open_in_editor_button.ex` — add
  `record_id` attr, mutual exclusion validation
- `lib/eye_in_the_sky_web/live/project_live/notes.ex`
- `lib/eye_in_the_sky_web/live/project_live/tasks.ex`
- `lib/eye_in_the_sky_web/components/task_detail_drawer.ex` — button placement
- `lib/eye_in_the_sky_web/live/project_live/prompts.ex`
- `lib/eye_in_the_sky_web/live/overview_live/prompts.ex` (if detail panel exists)
