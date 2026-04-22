# Editable File Tree Design

**Date**: 2026-04-22  
**Status**: Draft (Rev 3)  
**Author**: Claude + Uriel

## Overview

A VSCode-style editable file tree in the EITS rail flyout. Users select a project, browse files in a lazy-loaded tree, open files in CodeMirror, edit, and save. The tree stays visible while the editor shows the selected file in the main content area.

This is a **user-facing project editor**, not a read-only inspection tool. Save functionality is included from the start.

## Goals

- Visible Files section in the rail flyout
- Lazy-loaded project file tree
- Safe project-root-bounded file access
- Editable text file preview using CodeMirror
- Save support with conflict detection
- Dirty-state tracking with unsaved-change warnings
- Basic protection against stale writes

## Non-Goals (Deferred)

- Multi-tab editing
- Split panes
- Git status indicators
- Full project search
- File watchers
- Rename/delete/create file actions
- Drag and drop
- Autosave
- Format on save
- Diff or merge UI
- Full `.gitignore` parsing
- LSP / autocomplete / diagnostics
- Context menus
- File icons by extension
- Persisted workspace state
- Full fsync durability
- CRLF line ending preservation
- Draft recovery after reconnect

---

## Ownership Model

### Critical Boundaries

```
ProjectLive.Files
  Owns editor workflow.
  Owns selected file path (from route).
  Owns open_file metadata.
  Owns dirty state (coarse).
  Owns save/conflict/reload/discard behavior.
  Owns conflict dialogs.
  Handles select_file event and guards dirty state before patching.

FileTree service (EyeInTheSky.Projects.FileTree)
  Owns all filesystem behavior.
  Owns path safety (lexical and symlink).
  Owns directory listing.
  Owns file reads and writes.
  Owns guards and conflict detection.

FileTree component (rail/file_tree.ex)
  Only renders tree nodes.
  Emits expand/collapse/select events.
  Does NOT read or write files.
  Does NOT own tree state.

CodeMirror hook (file_editor_hook.js)
  Owns editor instance and unsaved client content.
  Tracks dirty state locally.
  Sends content only on save.
  Handles beforeunload.
  Guards against stale save responses.

Persistent rail/shell (NavHook or equivalent)
  Owns active rail section.
  Owns tree expansion state (expanded_folders, tree_nodes, loading_folders).
  Does NOT own file saves or editor workflow.
  Does NOT handle CodeMirror events.
```

### Key Invariants

- `open_file.path` must equal `selected_file_path` when a file is loaded
- If file load fails, set `open_file = nil` and show `file_error`
- Save must reject if payload path does not match `open_file.path`
- MVP supports one open file at a time

---

## Architecture

### Three-Layer Design

```
UI Component (file_tree.ex)
  -> LiveView state/event owner (ProjectLive.Files + rail shell)
  -> Safe filesystem service (EyeInTheSky.Projects.FileTree)
```

### Files to Create

| File | Purpose |
|------|---------|
| `lib/eye_in_the_sky/projects/file_tree.ex` | Safe filesystem service |
| `lib/eye_in_the_sky_web/components/rail/file_tree.ex` | Recursive tree rendering component |
| `assets/js/hooks/file_editor_hook.js` | CodeMirror hook with save support |

### Files to Modify

| File | Change |
|------|--------|
| `lib/eye_in_the_sky_web/components/rail.ex` | Add `hero-folder` icon for `:files` section |
| `lib/eye_in_the_sky_web/components/rail/flyout.ex` | Add `:files` case with `files_content/1` |
| `lib/eye_in_the_sky_web/live/project_live/files.ex` | Editor workflow owner |

**Note**: `nav_hook.ex` should NOT handle save/editor events. It may own tree expansion state only if rail shell is persistent.

---

## Event Ownership Table

| Event | Owner | Notes |
|-------|-------|-------|
| `open_files_section` | Rail/Shell | Loads root tree if needed |
| `expand_folder` | Rail/Shell | Calls `FileTree.children/3`, adds to `loading_folders` |
| `collapse_folder` | Rail/Shell | Removes from `expanded_folders` |
| `select_file` | ProjectLive.Files | Must check dirty state before patch |
| `editor_dirty` | ProjectLive.Files | Sent from CodeMirror hook on first change |
| `editor_clean` | ProjectLive.Files | Sent after save/discard/reload |
| `save_file` | ProjectLive.Files | Calls `FileTree.write_file/4` |
| `overwrite_file` | ProjectLive.Files | Calls `FileTree.write_file/4` with `force?: true` |
| `reload_file` | ProjectLive.Files | Reloads selected file if confirmed |
| `discard_changes` | ProjectLive.Files | Clears dirty state, applies pending switch |

### Event Targeting

Tree events are split across owners. The file tree component receives explicit targets:

```heex
<%!-- Folder expand/collapse target rail/shell --%>
<button phx-click="expand_folder" phx-target={@tree_target} phx-value-path={node.path}>
  ...
</button>

<%!-- File selection targets ProjectLive.Files --%>
<button phx-click="select_file" phx-target={@select_target} phx-value-path={node.path}>
  <%= node.name %>
</button>
```

**MVP Simplification**: If Phoenix event targeting between rail/shell and `ProjectLive.Files` proves awkward, collapse ownership — have `ProjectLive.Files` own all tree state (expanded_folders, tree_nodes, loading_folders) as well as editor state. Cleaner than cross-LiveView event routing.

**Rule**: File selection must be handled by the same process that owns dirty state.

### Server-to-Client Push Events

```elixir
push_event(socket, "file_loaded", %{
  path: path,
  content: content,
  hash: hash,
  language: language
})

push_event(socket, "file_saved", %{
  path: path,
  hash: new_hash
})

push_event(socket, "file_save_failed", %{
  path: path,
  error: error
})

push_event(socket, "file_conflict", %{
  path: path
})
```

### JS Hook Listeners

```javascript
this.handleEvent("file_loaded", ...)
this.handleEvent("file_saved", ...)
this.handleEvent("file_save_failed", ...)
this.handleEvent("file_conflict", ...)
```

---

## Filesystem Service

### Module: `EyeInTheSky.Projects.FileTree`

```elixir
defmodule EyeInTheSky.Projects.FileTree do
  @max_file_size 1_000_000
  @max_entries_per_directory 500

  # All functions take root_path (string), not %Project{}
  # Callers decide the root: project.path, session.worktree_path, etc.

  def root(root_path, opts \\ [])
  def children(root_path, rel_path, opts \\ [])
  def read_file(root_path, rel_path, opts \\ [])
  def write_file(root_path, rel_path, content, opts \\ [])
  def safe_path(root_path, rel_path)
  def safe_real_path(root_path, rel_path)  # resolves symlinks
end
```

### Root Path Validation Errors

```elixir
{:error, :missing_root_path}       # nil or empty
{:error, :root_path_not_found}     # path does not exist
{:error, :root_path_not_directory} # path is not a directory
{:error, :permission_denied}       # cannot read directory
```

### Safe Path Resolution

Prevents lexical path traversal:

```elixir
def safe_path(project_root, rel_path) do
  root = Path.expand(project_root)
  rel_path = to_string(rel_path)

  # Check absolute path BEFORE any trimming
  if Path.type(rel_path) == :absolute do
    {:error, :absolute_path_not_allowed}
  else
    target = Path.expand(Path.join(root, rel_path))

    if target == root or String.starts_with?(target, root <> "/") do
      {:ok, target}
    else
      {:error, :outside_project}
    end
  end
end
```

**Note**: The `root <> "/"` suffix prevents sibling-path escapes (e.g., `/tmp/project2` vs `/tmp/project`).

### Symlink Validation

For symlinked files, validate the resolved target stays inside project root:

```elixir
def safe_real_path(project_root, rel_path) do
  # Pseudocode — actual implementation must use a tested symlink resolver:
  # 1. Resolve lexical path using safe_path/2.
  # 2. If path is a symlink, resolve its final target (follow all links).
  # 3. Expand the resolved target to absolute path.
  # 4. Verify the resolved target remains under project_root.
  # 5. Return {:ok, resolved_path} or {:error, :symlink_escapes_project}.
  #
  # Note: File.read_link/1 exists but resolves one link only.
  # Use :file.read_link_all/1 (Erlang) for recursive resolution.
end
```

**Implementation detail**: Do not copy this sketch as final code. Use a tested helper for symlink resolution.

### Write File API

```elixir
# Normal save with conflict detection
write_file(root_path, rel_path, content, original_hash: hash)

# Force overwrite (after user confirms)
write_file(root_path, rel_path, content, force?: true)
```

**Note**: Service takes `root_path`, not `%Project{}`. Callers decide the root (`project.path`, `session.worktree_path`, etc.).

**Rules:**
- Validate content is UTF-8 before writing — return `{:error, :invalid_utf8}` if not
- If `original_hash` is missing and `force?` is not true, return `{:error, :missing_original_hash}`
- If `force?: true`, skip conflict check and overwrite
- Always use atomic write

### Save-Time Path Checks

Before writing, re-validate the path (it may have changed externally):

```elixir
# Before write:
# - safe path resolution
# - if path missing -> {:error, :file_deleted}
# - if path is directory -> {:error, :path_is_directory}
# - if path is symlink -> {:error, :symlink_not_saveable} (MVP)
# - if unsupported type -> {:error, :unsupported_file_type}
```

### Atomic Write with Permission Preservation

```elixir
def atomic_write(path, content) do
  dir = Path.dirname(path)
  base = Path.basename(path)
  random = Base.url_encode64(:crypto.strong_rand_bytes(8), padding: false)
  tmp_path = Path.join(dir, ".#{base}.tmp-#{random}")

  # Preserve original file mode if it exists
  original_mode = case File.stat(path) do
    {:ok, %{mode: mode}} -> mode
    _ -> nil
  end

  with :ok <- File.write(tmp_path, content),
       :ok <- maybe_chmod(tmp_path, original_mode),
       :ok <- File.rename(tmp_path, path) do
    :ok
  else
    error ->
      File.rm(tmp_path)
      error
  end
end

defp maybe_chmod(_path, nil), do: :ok
defp maybe_chmod(path, mode), do: File.chmod(path, mode)
```

**Note**: Use dotfile temp pattern (`.filename.tmp-xyz`) to hide from tree. Add `.*.tmp-*` to ignored patterns.

### Directory Sorting

```elixir
entries
|> filter_ignored()
|> Enum.sort_by(fn node ->
  {
    if(node.type == :directory, do: 0, else: 1),
    String.downcase(node.name)
  }
end)
|> Enum.take(@max_entries_per_directory)
```

**Important**: Filter and sort BEFORE applying entry limit.

### Ignored Directories (Always Hidden)

```elixir
@ignored_directories ~w(.git node_modules _build deps .elixir_ls coverage tmp)

# Regex for temp files created during atomic write
@ignored_temp_regex ~r/^\..*\.tmp-[A-Za-z0-9_-]+$/
```

```elixir
def ignored?(entry_name) do
  entry_name in @ignored_directories or
    Regex.match?(@ignored_temp_regex, entry_name)
end
```

### Hidden Files Policy (MVP)

- Show normal dotfiles by default (`.formatter.exs`, `.gitignore`, etc.)
- Always hide heavy directories (`.git`, `node_modules`, `_build`, `deps`)
- No Show Hidden toggle in MVP

### Binary Detection

```elixir
def binary_file?(content) do
  :binary.match(content, <<0>>) != :nomatch
end
```

### Conflict Detection

Use content hash, not mtime:

```elixir
hash = :crypto.hash(:sha256, content) |> Base.encode16(case: :lower)
```

---

## Symlink Policy

- **Symlinked directories**: Show with visual marker, do NOT expand (`expandable?: false`)
- **Symlinked files**: Allow viewing/opening only if resolved target stays inside project root
- **Validation**: Both `safe_path/2` (lexical) AND `safe_real_path/2` (resolved) must pass for symlinked files

### Symlink Save Policy

**MVP does not save symlinked files.**

Symlinked files may be visible and may be opened only if the resolved target stays inside the project root. Saving symlinked files is deferred because `File.rename/2` (atomic write) replaces the symlink itself instead of writing through to the target.

If symlink saving is added later, it must explicitly write to the resolved target and preserve the symlink.

**Error**: "Saving symlinked files is not supported."

---

## Node Shape

```elixir
%{
  name: "router.ex",
  path: "lib/my_app_web/router.ex",  # relative path
  type: :file,           # :file | :directory | :warning
  symlink?: false,
  expandable?: true      # false for symlinked directories
}
```

### Warning Node (for truncated directories)

```elixir
%{
  name: "This directory has more than 500 entries. Some entries are hidden.",
  path: nil,
  type: :warning,
  symlink?: false,
  expandable?: false
}
```

### Symlinked Directory Node

```elixir
%{
  name: "linked_dir",
  path: "linked_dir",
  type: :directory,
  symlink?: true,
  expandable?: false  # symlinked directories do NOT expand
}
```

### Tree State (owned by rail/shell)

```elixir
tree_nodes: %{
  "" => [%{name: "lib", path: "lib", type: :directory}, ...],
  "lib" => [%{name: "my_app.ex", path: "lib/my_app.ex", type: :file}, ...]
}

expanded_folders: MapSet.new(["lib", "lib/my_app_web"])

loading_folders: MapSet.new()  # currently loading

folder_errors: %{
  "lib/private" => "permission denied"
}
```

---

## Socket Assigns

### Rail/Shell Assigns (tree state)

```elixir
assign(socket,
  active_section: :files,
  expanded_folders: MapSet.new(),
  tree_nodes: %{},
  loading_folders: MapSet.new(),
  folder_errors: %{}
)
```

### ProjectLive.Files Assigns (editor state)

```elixir
assign(socket,
  selected_file_path: nil,
  open_file: nil,
  file_error: nil,
  save_state: :clean,
  pending_file_switch: nil
)
```

### `open_file` Shape

```elixir
%{
  path: "lib/my_app_web/router.ex",
  name: "router.ex",
  content: "...",
  original_hash: "abc123...",
  size: 12345,
  language: :elixir,
  sensitive?: false
}
```

**Note**: `mtime` is for display/debug only. Use `original_hash` for conflict detection.

**Note**: File content in socket assigns is acceptable for MVP with 1MB limit. Do not log socket assigns.

### `save_state` Values

- `:clean` - No unsaved changes
- `:dirty` - Editor has unsaved changes
- `:saving` - Save in progress
- `:saved` - Just saved successfully
- `:error` - Save failed
- `:conflict` - File changed on disk

---

## Event Flow

### Open Files Section

```
User clicks folder rail icon
  -> active_section = :files
  -> if project selected AND tree_nodes[""] is empty:
       load root directory
  -> render tree
```

Root loading is idempotent — do not reload if already loaded unless project changes.

### Expand Folder

```
User clicks folder chevron
  -> if path in loading_folders: ignore (prevent duplicate loads)
  -> add path to loading_folders
  -> safe path resolution
  -> list children
  -> filter ignored entries
  -> sort children
  -> take first 500 (add warning node if truncated)
  -> update tree_nodes[path]
  -> add path to expanded_folders
  -> remove path from loading_folders
  -> on error: add to folder_errors, remove from loading_folders
```

### Select File (dirty-state guarded)

File tree row clicks use **events, not direct patch links**:

```heex
<button type="button" phx-click="select_file" phx-value-path={node.path}>
  <%= node.name %>
</button>
```

Flow:
```
User clicks file
  -> select_file event to ProjectLive.Files
  -> if current editor is clean:
       push_patch to /projects/:id/files?path=<rel_path>
  -> if current editor is dirty:
       set pending_file_switch = path
       show unsaved changes dialog
```

### Load File

```
Route has ?path=...
  -> safe path resolution
  -> stat path
  -> if directory -> {:error, :path_is_directory}
  -> if not regular file -> {:error, :unsupported_file_type}
  -> check size (max 1MB)
  -> read file
  -> check binary
  -> check UTF-8
  -> hash content
  -> detect language by extension (best-effort, fallback to plain text)
  -> assign open_file
  -> push_event "file_loaded" to CodeMirror
```

### Save File

```
User clicks Save or Cmd+S
  -> CodeMirror sends { path, content }
  -> LiveView validates path == open_file.path
       (if mismatch: {:error, :stale_editor_state})
  -> LiveView uses socket.assigns.open_file.original_hash (server-owned)
  -> FileTree.write_file with original_hash
  -> if conflict: push_event "file_conflict"
  -> else: atomic write, compute new hash
  -> push_event "file_saved" with new_hash
  -> update open_file.original_hash
  -> save_state = :saved
```

### Overwrite (after conflict)

```
User clicks Overwrite in conflict dialog
  -> FileTree.write_file with force?: true
  -> atomic write
  -> compute new hash
  -> update open_file.original_hash
  -> save_state = :saved
  -> clear conflict state
```

### Deleted File During Save

```
User saves file that was deleted externally
  -> FileTree.write_file detects file missing
  -> return {:error, :file_deleted}
  -> show error: "This file no longer exists."
  -> MVP does NOT recreate deleted files
```

### Project Switching

```
User switches project while editor is dirty
  -> show unsaved changes dialog
  -> Save: save then switch
  -> Discard: clear tree state, clear editor state, switch
  -> Cancel: stay on current project
```

### Pending File Switch Transitions

When `pending_file_switch` is set (user tried to switch files while dirty):

**If save succeeds:**
- Clear dirty state
- Clear `pending_file_switch`
- `push_patch` to pending path

**If save fails:**
- Keep dirty state
- Keep `pending_file_switch`
- Stay on current file
- Show save error

**If user discards:**
- Clear dirty state
- Clear `pending_file_switch`
- `push_patch` to pending path

**If user cancels:**
- Keep dirty state
- Clear `pending_file_switch`
- Stay on current file

### Conflict Dialog Transitions

**Reload:**
- Discard editor content
- Read file from disk
- Update `open_file` (content, hash)
- Clear dirty state
- Clear conflict state

**Overwrite:**
- Force write editor content
- Compute new hash
- Update `open_file.original_hash`
- Clear dirty state
- Clear conflict state
- Set `save_state = :saved`

**Cancel:**
- Keep editor content
- Keep dirty state
- Close conflict dialog

---

## Dirty-State Tracking

### Communication Flow

```
CodeMirror tracks actual content dirty state locally.
On first clean -> dirty transition: CodeMirror sends editor_dirty.
After save/reload/discard: CodeMirror sends or receives editor_clean.
LiveView tracks coarse dirty state for UI guards.
LiveView does NOT receive every keystroke.
```

### Guard Rule

If editor is dirty, routine LiveView updates must NOT replace CodeMirror content. Only explicit reload, discard, save success, or confirmed file switch may replace dirty content.

---

## UI Components

### Rail Icon

Add `hero-folder` icon to rail. Grey out when no project selected.

### Files Flyout Section

- Header: "FILES" label
- Tree: Recursive `<.tree_node>` component
- Empty states:
  - No project: "Select a project to browse files."
  - Invalid path: "This project does not have a valid path."
  - Path missing: "Project path does not exist."

### Tree Node

- Show loading indicator when folder is in `loading_folders`
- Show error inline when folder is in `folder_errors`
- Unreadable folder should not break whole tree

### CodeMirror Editor

Required features:
- Display file content
- Allow editing
- Track dirty state locally
- Save via button and Cmd+S / Ctrl+S
- Receive new content via push_event
- Guard against replacing dirty content
- Track currentPath to ignore stale save responses
- beforeunload warning when dirty
- Ignore `file_saved` events whose path does not match currentPath
- Update clean baseline hash from `file_saved.hash`

### Content Transfer

MVP transfers editor content via `push_event`, not as visible DOM text. `open_file.content` may be stored in assigns for server workflow, but should not be rendered directly. Do NOT put large file content in data attributes.

### Reconnect Limitation

If LiveView reconnects while editor is dirty, MVP does not guarantee draft recovery. The CodeMirror hook avoids replacing dirty content during normal updates, but a full page reload loses unsaved edits. `beforeunload` reduces this risk.

### Dirty State Indicator

When file is dirty, show asterisk: `router.ex *`

### Save Button States

- `Save` (enabled when dirty)
- `Saving...`
- `Saved`
- `Save failed`

### Conflict Dialog

```
This file changed on disk since you opened it.

[Reload] [Overwrite] [Cancel]
```

### Unsaved Changes Dialog

```
You have unsaved changes.

[Save] [Discard] [Cancel]
```

---

## Error States

| Condition | Message |
|-----------|---------|
| No project selected | "Select a project to browse files." |
| Project path missing | "This project does not have a valid path." |
| Root path not found | "Project path does not exist." |
| Root path not directory | "Project path is not a directory." |
| Path outside project | "This path is outside the project and cannot be opened." |
| Absolute path | "Absolute paths are not allowed." |
| Symlink escapes project | "This symlink points outside the project." |
| Symlink not saveable | "Saving symlinked files is not supported." |
| Path is directory | "This path is a directory, not a file." |
| File too large | "This file is too large to edit." |
| Binary file | "Binary files cannot be edited." |
| Invalid UTF-8 | "This file is not valid UTF-8." |
| Invalid UTF-8 on save | "Content is not valid UTF-8." |
| Permission denied | "Could not open file: permission denied." |
| File no longer exists | "This file no longer exists." |
| Save conflict | "This file changed on disk since you opened it." |
| File deleted during save | "This file no longer exists." |
| Stale editor state | "Editor state is stale. Please reload." |
| Missing original hash | "Cannot save: missing original file hash." |

---

## Sensitive Files

Mark these with a badge or warning (do not block in local MVP):

- `.env`, `.env.local`, `.env.production`
- `*.pem`, `*.key`
- `credentials.json`
- `config/prod.secret.exs`

### Logging Rules

- Do NOT log file contents
- Do NOT inspect socket assigns containing `open_file.content` in logs
- Do NOT include file contents in telemetry metadata
- Do NOT broadcast file contents via PubSub
- Do NOT include file contents in audit/event payloads

---

## Language Detection

Best-effort by file extension:

| Extension | Language |
|-----------|----------|
| `.ex`, `.exs` | elixir |
| `.heex` | html |
| `.js` | javascript |
| `.ts` | typescript |
| `.svelte` | svelte |
| `.md` | markdown |
| `.json` | json |
| (other) | plain text |

Syntax highlighting failure must not prevent editing.

---

## Tests Required

### Path Safety

```
safe relative path resolves
absolute path /etc/passwd is rejected (before any trimming)
../ traversal is rejected
outside project path is rejected
sibling project path is rejected (/tmp/project2 vs /tmp/project)
symlink to file inside project resolves
symlink to file outside project is rejected
symlink to directory does not expand
```

### File Guards

```
large file is blocked
binary file is blocked
invalid UTF-8 is blocked
directory path cannot be opened as file
```

### File Operations

```
text file reads successfully
directories sort before files alphabetically
heavy directories are filtered
entry limit applies after sort
```

### Write Operations

```
write saves content
write uses conflict detection
write rejects missing original_hash
write rejects stale original hash
write succeeds with force?: true
write rejects outside project path
atomic write cleans up temp file on failure
atomic write preserves file permissions
atomic write replaces existing file content
write rejects symlinked file (MVP)
write rejects if path became directory
write rejects if file was deleted (returns :file_deleted)
write validates UTF-8 content
write rejects invalid UTF-8 content
```

### Special Characters

```
filename with spaces resolves and opens
filename with # resolves and opens
filename with ? resolves and opens
Unicode filename resolves and opens
query-param encoded path opens correctly
```

---

## Implementation Phases

### Phase 1: Safe File Service

Build and test before any UI work:

- [ ] `EyeInTheSky.Projects.FileTree` module
- [ ] `safe_path/2` and `safe_real_path/2`
- [ ] `children/3` with sorting, filtering, limit
- [ ] `read_file/3` with size/binary/UTF-8/directory guards
- [ ] `write_file/4` with atomic write, permission preservation, conflict detection
- [ ] `force?: true` overwrite option
- [ ] Comprehensive tests

### Phase 2: Tree UI

- [ ] Rail folder icon in `rail.ex`
- [ ] `:files` section in `flyout.ex`
- [ ] `file_tree.ex` recursive component
- [ ] Tree state in rail/shell (expanded_folders, tree_nodes, loading_folders, folder_errors)
- [ ] Expand/collapse events
- [ ] `select_file` event (button, not link)
- [ ] File selection route `/projects/:id/files?path=<rel_path>`
- [ ] Selected file highlighting
- [ ] Empty/error states
- [ ] Folder loading indicator
- [ ] Per-folder error display

### Phase 3: Editor UI

- [ ] CodeMirror hook with dirty state tracking
- [ ] Load selected file into editor via push_event
- [ ] Dirty state indicator (asterisk)
- [ ] Save button with states
- [ ] Cmd+S / Ctrl+S save shortcut
- [ ] Save event handling (server-owned original_hash)
- [ ] Stale editor state rejection
- [ ] Conflict dialog
- [ ] Unsaved-switch warning (before file switch AND project switch)
- [ ] beforeunload warning
- [ ] Guard against replacing dirty content

### Phase 4: Polish

- [ ] Refresh button (reload expanded folders, preserve expansion)
- [ ] Sensitive file badges
- [ ] Better loading states
- [ ] Extension-to-language mapping

---

## Acceptance Criteria

### Phase 1 Complete When

- All path safety tests pass (lexical AND symlink, including absolute path rejection)
- Read guards (size, binary, UTF-8, directory) work
- Write guards (UTF-8 content, symlink rejection, save-time type checks) work
- Atomic write works and preserves permissions
- Conflict detection works
- force? overwrite works
- Root path validation returns specific errors

### Phase 2 Complete When

- Files rail icon visible and functional
- Tree loads project root on section open (idempotent)
- Folders expand/collapse with loading indicator
- Folder errors display inline without breaking tree
- File click uses event, checks dirty state, then patches
- Tree uses relative paths only

### Phase 3 Complete When

- CodeMirror loads and edits files via push_event
- Save works via button and keyboard shortcut
- Server owns original_hash, rejects stale saves
- Dirty state shows asterisk
- Conflict prompts user (Reload/Overwrite/Cancel)
- Switching files with unsaved changes prompts user
- Switching projects with unsaved changes prompts user
- Browser beforeunload warns when dirty
- Dirty content is not replaced by routine LiveView updates

### MVP Complete When

- User can browse project files
- User can open a text file in CodeMirror
- User can edit and save
- Path traversal attacks are blocked (lexical and symlink)
- Partial-write corruption risk is reduced via temp-file + rename
- Unsaved changes are not silently lost
- One open file at a time
- Symlinked files are viewable but not saveable
