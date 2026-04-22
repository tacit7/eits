# Editable File Tree Design

**Date**: 2026-04-22  
**Status**: Draft  
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

---

## Architecture

### Three-Layer Design

```
UI Component (file_tree.ex)
  -> LiveView state/event owner
  -> Safe filesystem service (EyeInTheSky.Projects.FileTree)
```

The UI layer renders and emits events. The LiveView handles events and updates socket assigns. The filesystem service owns all path resolution, directory listing, file reading, and writing.

### Files to Create

| File | Purpose |
|------|---------|
| `lib/eye_in_the_sky/projects/file_tree.ex` | Safe filesystem service |
| `lib/eye_in_the_sky_web/components/rail/file_tree.ex` | Recursive tree rendering component |

### Files to Modify

| File | Change |
|------|--------|
| `lib/eye_in_the_sky_web/components/rail.ex` | Add `hero-folder` icon for `:files` section |
| `lib/eye_in_the_sky_web/components/rail/flyout.ex` | Add `:files` case with `files_content/1` |
| `lib/eye_in_the_sky_web/live/nav_hook.ex` | Handle expand/collapse/select/save events |
| `lib/eye_in_the_sky_web/live/project_live/files.ex` | CodeMirror editor integration |
| `assets/js/hooks/file_editor_hook.js` | CodeMirror hook with save support |

---

## Filesystem Service

### Module: `EyeInTheSky.Projects.FileTree`

```elixir
defmodule EyeInTheSky.Projects.FileTree do
  @max_file_size 1_000_000
  @max_entries_per_directory 500

  def root(project, opts \\ [])
  def children(project, rel_path, opts \\ [])
  def read_file(project, rel_path, opts \\ [])
  def write_file(project, rel_path, content, opts \\ [])
  def safe_path(project_root, rel_path)
end
```

### Safe Path Resolution

All file and directory access must be restricted to the project root.

```elixir
def safe_path(project_root, rel_path) do
  root = Path.expand(project_root)

  rel_path =
    rel_path
    |> to_string()
    |> String.trim_leading("/")

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

### Directory Sorting

```elixir
Enum.sort_by(entries, fn node ->
  {
    if(node.type == :directory, do: 0, else: 1),
    String.downcase(node.name)
  }
end)
```

### Ignored Directories (Hidden by Default)

```elixir
@ignored_directories ~w(.git node_modules _build deps .elixir_ls coverage tmp)
```

### Binary Detection

```elixir
def binary_file?(content) do
  :binary.match(content, <<0>>) != :nomatch
end
```

### Atomic Write

```elixir
def atomic_write(path, content) do
  tmp_path = path <> ".tmp-" <> Base.url_encode64(:crypto.strong_rand_bytes(8), padding: false)

  with :ok <- File.write(tmp_path, content),
       :ok <- File.rename(tmp_path, path) do
    :ok
  else
    error ->
      File.rm(tmp_path)
      error
  end
end
```

### Conflict Detection

When opening a file, compute and store `original_hash`:

```elixir
hash = :crypto.hash(:sha256, content) |> Base.encode16(case: :lower)
```

When saving, read current disk content, hash it, compare to `original_hash`. If different, return `{:error, :conflict}`.

---

## Symlink Policy

- **Symlinked directories**: Show with visual marker, do not expand
- **Symlinked files**: Allow only if resolved target stays inside project root
- **Rationale**: Prevents escaping project root and infinite loops

---

## Node Shape

```elixir
%{
  name: "router.ex",
  path: "lib/my_app_web/router.ex",
  type: :file,           # :file | :directory
  symlink?: false
}
```

### Tree State

```elixir
tree_nodes: %{
  "" => [
    %{name: "lib", path: "lib", type: :directory},
    %{name: "mix.exs", path: "mix.exs", type: :file}
  ],
  "lib" => [
    %{name: "my_app.ex", path: "lib/my_app.ex", type: :file}
  ]
}
```

---

## Socket Assigns

```elixir
assign(socket,
  active_section: :files,
  expanded_folders: MapSet.new(),
  tree_nodes: %{},
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
  mtime: ~N[2026-04-22 00:00:00],
  size: 12345,
  language: :elixir,
  sensitive?: false
}
```

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
  -> if project selected, load root directory
  -> render tree
```

### Expand Folder

```
User clicks folder chevron
  -> push event expand_folder(path)
  -> safe path resolution
  -> list children
  -> filter ignored entries
  -> sort children
  -> update tree_nodes[path]
  -> add path to expanded_folders
```

### Select File

```
User clicks file
  -> if current editor is clean:
       push_patch to /projects/:id/files?path=<rel_path>
     if current editor is dirty:
       show unsaved changes dialog
```

### Load File

```
Route has ?path=...
  -> safe path resolution
  -> stat file
  -> check size (max 1MB)
  -> read file
  -> check binary
  -> check UTF-8
  -> hash content
  -> assign open_file
  -> CodeMirror receives content
```

### Save File

```
User clicks Save or Cmd+S
  -> CodeMirror sends path, content, original_hash
  -> LiveView calls FileTree.write_file
  -> safe path resolution
  -> read current disk hash
  -> if conflict, return {:error, :conflict}
  -> else atomic write
  -> return new hash
  -> editor clears dirty state
  -> save_state = :saved
```

---

## UI Components

### Rail Icon

Add `hero-folder` icon to rail. Grey out when no project selected.

### Files Flyout Section

- Header: "FILES" label
- Optional controls: Refresh button, Show hidden toggle
- Tree: Recursive `<.tree_node>` component
- Empty state: "Select a project to browse files."

### CodeMirror Editor

Required features:
- Display file content
- Allow editing
- Track dirty state
- Save via button and Cmd+S / Ctrl+S
- Receive new content when selected file changes
- Avoid overwriting dirty content accidentally

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
| Path outside project | "This path is outside the project and cannot be opened." |
| File too large | "This file is too large to edit." |
| Binary file | "Binary files cannot be edited." |
| Invalid UTF-8 | "This file is not valid UTF-8." |
| Permission denied | "Could not open file: permission denied." |
| File no longer exists | "This file no longer exists." |
| Save conflict | "This file changed on disk since you opened it." |

---

## Sensitive Files

Mark these with a badge or warning (do not block):

- `.env`, `.env.local`, `.env.production`
- `*.pem`, `*.key`
- `credentials.json`
- `config/prod.secret.exs`

Do not log file contents.

---

## Tests Required

```
safe relative path resolves
absolute path is rejected
../ traversal is rejected
outside project path is rejected
root directory lists
directories sort before files
heavy directories are filtered
large file is blocked
binary file is blocked
invalid UTF-8 is blocked
text file reads successfully
write saves content
write uses conflict detection
write rejects stale original hash
write rejects outside project path
symlink escaping root is blocked
atomic write cleans up temp file on failure
```

---

## Implementation Phases

### Phase 1: Safe File Service

Build and test before any UI work:

- [ ] `EyeInTheSky.Projects.FileTree` module
- [ ] `safe_path/2`
- [ ] `children/3` with sorting and filtering
- [ ] `read_file/3` with size/binary/UTF-8 guards
- [ ] `write_file/4` with atomic write and conflict detection
- [ ] Comprehensive tests

### Phase 2: Tree UI

- [ ] Rail folder icon in `rail.ex`
- [ ] `:files` section in `flyout.ex`
- [ ] `file_tree.ex` recursive component
- [ ] Expand/collapse events
- [ ] File selection route `/projects/:id/files?path=<rel_path>`
- [ ] Selected file highlighting
- [ ] Empty/error states

### Phase 3: Editor UI

- [ ] CodeMirror hook with dirty state tracking
- [ ] Load selected file into editor
- [ ] Save button
- [ ] Cmd+S / Ctrl+S save shortcut
- [ ] Save event handling
- [ ] Conflict dialog
- [ ] Unsaved-switch warning
- [ ] beforeunload warning

### Phase 4: Polish

- [ ] Refresh button
- [ ] Sensitive file badges
- [ ] Better loading states
- [ ] Extension-to-language mapping for syntax highlighting

---

## Acceptance Criteria

### Phase 1 Complete When

- All path safety tests pass
- Read guards (size, binary, UTF-8) work
- Atomic write works
- Conflict detection works

### Phase 2 Complete When

- Files rail icon visible and functional
- Tree loads project root on section open
- Folders expand/collapse
- File click updates route and highlights selection
- Tree uses relative paths only

### Phase 3 Complete When

- CodeMirror loads and edits files
- Save works via button and keyboard shortcut
- Dirty state shows asterisk
- Conflict prompts user before overwriting
- Switching files with unsaved changes prompts user
- Browser beforeunload warns when dirty

### MVP Complete When

- User can browse project files
- User can open a text file in CodeMirror
- User can edit and save
- Path traversal attacks are blocked
- File corruption is prevented via atomic write
- Unsaved changes are not silently lost
