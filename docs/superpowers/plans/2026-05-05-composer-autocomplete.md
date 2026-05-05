# Composer Autocomplete (`@` file, `@@` agent) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `@` file-path autocomplete (server-fetched, real-time) and `@@` agent-name autocomplete (client-side) to the DM composer textarea, remapping the existing `@` agent trigger to `@@`.

**Architecture:** A new `FileAutocomplete` Elixir module handles path resolution, traversal guarding, sorting, and `insert_text` generation. `DmLive` delegates the `list_files` pushEvent reply to it. On the JS side, `slash_command_popup.js` gains updated trigger detection (`@@` before `@`), a debounced `startFileAutocomplete` method, and a `renderFilePopup` renderer that stores file entries in `slashOrdered` so existing keyboard nav (`↑↓ Enter Tab Esc`) works without changes.

**Tech Stack:** Elixir/Phoenix LiveView pushEvent reply pattern, ExUnit, vitest/jsdom

---

## File Map

| File | Action | Responsibility |
|------|--------|----------------|
| `lib/eye_in_the_sky_web/live/dm_live/file_autocomplete.ex` | Create | `list_entries/3`, `under_root?/2`, root resolution, path splitting, sorting, exclusions, truncation, `insert_text` generation |
| `test/eye_in_the_sky_web/live/dm_live/file_autocomplete_test.exs` | Create | All server-side path logic tests |
| `lib/eye_in_the_sky_web/live/dm_live.ex` | Modify | Add `handle_event("list_files", ...)` clause |
| `assets/js/hooks/slash_command_popup.js` | Modify | `@@` before `@` trigger detection; `startFileAutocomplete`; `renderFilePopup`; `_fileSelect`; `fileMode` flag in `slashSelect` |
| `assets/js/hooks/slash_command_popup_file.test.js` | Create | JS unit tests for trigger parsing and file-mode behaviour |

---

## Task 1: FileAutocomplete Elixir Module

**Files:**
- Create: `lib/eye_in_the_sky_web/live/dm_live/file_autocomplete.ex`
- Create: `test/eye_in_the_sky_web/live/dm_live/file_autocomplete_test.exs`

- [ ] **Step 1: Create the test file with root validation tests**

```elixir
# test/eye_in_the_sky_web/live/dm_live/file_autocomplete_test.exs
defmodule EyeInTheSkyWeb.DmLive.FileAutocompleteTest do
  use ExUnit.Case, async: true

  alias EyeInTheSkyWeb.DmLive.FileAutocomplete

  # A fake session struct — only git_worktree_path matters here.
  defp session(path \\ nil), do: %{git_worktree_path: path}

  describe "list_entries/3 — root validation" do
    test "unknown root returns empty" do
      result = FileAutocomplete.list_entries("", "unknown", session())
      assert result == %{entries: [], truncated: false}
    end

    test "project root with nil worktree falls back to File.cwd!" do
      result = FileAutocomplete.list_entries("", "project", session(nil))
      # Just verify we get a map with entries — exact contents depend on cwd
      assert is_list(result.entries)
      assert is_boolean(result.truncated)
    end

    test "home root resolves to user home dir entries" do
      result = FileAutocomplete.list_entries("", "home", session())
      assert is_list(result.entries)
    end

    test "filesystem root resolves to / entries" do
      result = FileAutocomplete.list_entries("", "filesystem", session())
      assert Enum.any?(result.entries, &(&1.name == "etc"))
    end
  end

  describe "list_entries/3 — traversal guard" do
    test "../ does not escape project root" do
      root = System.tmp_dir!()
      result = FileAutocomplete.list_entries("../../etc", "project", session(root))
      assert result == %{entries: [], truncated: false}
    end

    test "under_root? does not match prefix-extended paths" do
      # /Users/uriel/project-old should NOT be under /Users/uriel/project
      refute FileAutocomplete.under_root?(
               "/Users/uriel/project-old",
               "/Users/uriel/project"
             )
    end

    test "under_root? accepts children of the root" do
      assert FileAutocomplete.under_root?(
               "/Users/uriel/project/src/foo.ex",
               "/Users/uriel/project"
             )
    end

    test "under_root? accepts path equal to root" do
      assert FileAutocomplete.under_root?(
               "/Users/uriel/project",
               "/Users/uriel/project"
             )
    end

    test "filesystem root / accepts all absolute paths" do
      assert FileAutocomplete.under_root?("/etc/hosts", "/")
      assert FileAutocomplete.under_root?("/usr/bin/env", "/")
    end
  end

  describe "list_entries/3 — sorting and filtering" do
    setup do
      root = Path.join(System.tmp_dir!(), "fa_test_#{:rand.uniform(999_999)}")
      File.mkdir_p!(root)
      File.mkdir_p!(Path.join(root, "alpha_dir"))
      File.mkdir_p!(Path.join(root, "beta_dir"))
      File.write!(Path.join(root, "alpha_file.txt"), "")
      File.write!(Path.join(root, "beta_file.txt"), "")
      on_exit(fn -> File.rm_rf!(root) end)
      {:ok, root: root}
    end

    test "directories appear before files", %{root: root} do
      result = FileAutocomplete.list_entries("", "project", session(root))
      dirs = Enum.take_while(result.entries, & &1.is_dir)
      assert length(dirs) == 2
      files = Enum.drop_while(result.entries, & &1.is_dir)
      assert Enum.all?(files, &(not &1.is_dir))
    end

    test "entries are alphabetized within each group", %{root: root} do
      result = FileAutocomplete.list_entries("", "project", session(root))
      dir_names = result.entries |> Enum.filter(& &1.is_dir) |> Enum.map(& &1.name)
      assert dir_names == Enum.sort(dir_names)
      file_names = result.entries |> Enum.reject(& &1.is_dir) |> Enum.map(& &1.name)
      assert file_names == Enum.sort(file_names)
    end

    test "prefix filter is case-sensitive and prefix-only", %{root: root} do
      result = FileAutocomplete.list_entries("alpha", "project", session(root))
      assert length(result.entries) == 2
      assert Enum.all?(result.entries, &String.starts_with?(&1.name, "alpha"))
    end

    test "dotfiles are shown by default", %{root: root} do
      File.write!(Path.join(root, ".env"), "")
      result = FileAutocomplete.list_entries("", "project", session(root))
      assert Enum.any?(result.entries, &(&1.name == ".env"))
    end
  end

  describe "list_entries/3 — excluded directories" do
    setup do
      root = Path.join(System.tmp_dir!(), "fa_excl_#{:rand.uniform(999_999)}")
      File.mkdir_p!(root)
      for dir <- ~w(.git node_modules deps _build .elixir_ls .tmp) do
        File.mkdir_p!(Path.join(root, dir))
      end
      File.mkdir_p!(Path.join(root, "lib"))
      on_exit(fn -> File.rm_rf!(root) end)
      {:ok, root: root}
    end

    test "noisy root-level dirs are hidden", %{root: root} do
      result = FileAutocomplete.list_entries("", "project", session(root))
      names = Enum.map(result.entries, & &1.name)
      assert "lib" in names
      for excluded <- ~w(.git node_modules deps _build .elixir_ls .tmp) do
        refute excluded in names, "Expected #{excluded} to be excluded"
      end
    end

    test "explicitly navigating into excluded dir returns its contents", %{root: root} do
      File.write!(Path.join([root, "node_modules", "foo.js"]), "")
      result = FileAutocomplete.list_entries("node_modules/", "project", session(root))
      assert Enum.any?(result.entries, &(&1.name == "foo.js"))
    end
  end

  describe "list_entries/3 — truncation" do
    setup do
      root = Path.join(System.tmp_dir!(), "fa_trunc_#{:rand.uniform(999_999)}")
      File.mkdir_p!(root)
      for i <- 1..55 do
        File.write!(Path.join(root, "file_#{String.pad_leading("#{i}", 3, "0")}.txt"), "")
      end
      on_exit(fn -> File.rm_rf!(root) end)
      {:ok, root: root}
    end

    test "returns at most 50 entries with truncated: true", %{root: root} do
      result = FileAutocomplete.list_entries("", "project", session(root))
      assert length(result.entries) == 50
      assert result.truncated == true
    end

    test "55 entries without filter — still 50 + truncated", %{root: root} do
      result = FileAutocomplete.list_entries("", "project", session(root))
      assert result.truncated
    end
  end

  describe "list_entries/3 — insert_text generation" do
    setup do
      root = Path.join(System.tmp_dir!(), "fa_ins_#{:rand.uniform(999_999)}")
      File.mkdir_p!(root)
      File.mkdir_p!(Path.join(root, "src"))
      File.write!(Path.join(root, "router.ex"), "")
      on_exit(fn -> File.rm_rf!(root) end)
      {:ok, root: root}
    end

    test "project root: insert_text starts with @", %{root: root} do
      result = FileAutocomplete.list_entries("", "project", session(root))
      router = Enum.find(result.entries, &(&1.name == "router.ex"))
      assert router.insert_text == "@router.ex"
      assert router.path == "router.ex"
    end

    test "project root directory: trailing slash in path and insert_text", %{root: root} do
      result = FileAutocomplete.list_entries("", "project", session(root))
      src = Enum.find(result.entries, &(&1.name == "src"))
      assert src.path == "src/"
      assert src.insert_text == "@src/"
    end

    test "home root: insert_text starts with @~/", %{root: _root} do
      result = FileAutocomplete.list_entries("", "home", session())
      if result.entries != [] do
        entry = hd(result.entries)
        assert String.starts_with?(entry.insert_text, "@~/")
      end
    end

    test "filesystem root: insert_text starts with @/", %{root: _root} do
      result = FileAutocomplete.list_entries("", "filesystem", session())
      entry = Enum.find(result.entries, &(&1.name == "etc"))
      assert entry.insert_text == "@/etc/"
      assert entry.path == "etc/"
    end
  end
end
```

- [ ] **Step 2: Run tests — expect all to fail (module does not exist)**

```bash
cd /Users/urielmaldonado/projects/eits/web
mix test test/eye_in_the_sky_web/live/dm_live/file_autocomplete_test.exs 2>&1 | head -30
```

Expected: `** (UndefinedFunctionError) function EyeInTheSkyWeb.DmLive.FileAutocomplete.list_entries/3 is undefined`

- [ ] **Step 3: Implement FileAutocomplete module**

```elixir
# lib/eye_in_the_sky_web/live/dm_live/file_autocomplete.ex
defmodule EyeInTheSkyWeb.DmLive.FileAutocomplete do
  @moduledoc """
  Server-side file listing for the DM composer @ autocomplete trigger.

  `list_entries/3` is the public API. It resolves the root, guards against
  path traversal, lists matching directory entries, and returns insertion-safe
  `insert_text` values that the client pastes directly into the textarea.
  """

  @excluded_dirs ~w(.git node_modules deps _build .elixir_ls .tmp)
  @max_entries 50

  @doc """
  Lists filesystem entries for the given partial path and root type.

  Returns `%{entries: [...], truncated: boolean}`. On any error (bad root,
  path traversal, permission denied), returns `%{entries: [], truncated: false}`.

  Each entry: `%{name: String.t(), path: String.t(), insert_text: String.t(), is_dir: boolean()}`.
  - `path` — root-relative path used for follow-up fetches (pass back as `partial`)
  - `insert_text` — exact string to insert into the textarea (includes `@` prefix)
  """
  @spec list_entries(String.t(), String.t(), map()) :: %{entries: list(), truncated: boolean()}
  def list_entries(partial, root_type, session) do
    case resolve_base(root_type, session) do
      {:ok, base_dir} ->
        {dir_part, file_prefix} = split_partial(partial)
        target = Path.expand(Path.join(base_dir, dir_part))

        if under_root?(target, base_dir) do
          case File.ls(target) do
            {:ok, names} -> build_result(names, target, dir_part, file_prefix, root_type)
            _ -> empty()
          end
        else
          empty()
        end

      _ ->
        empty()
    end
  end

  @doc """
  Returns true when `path` is the same as `root` or a direct descendant.
  Handles the filesystem root `/` correctly (avoids the `//` double-slash bug).
  """
  @spec under_root?(String.t(), String.t()) :: boolean()
  def under_root?(path, root) do
    expanded_path = Path.expand(path)
    expanded_root = Path.expand(root)

    cond do
      expanded_root == "/" ->
        String.starts_with?(expanded_path, "/")

      expanded_path == expanded_root ->
        true

      true ->
        String.starts_with?(expanded_path, expanded_root <> "/")
    end
  end

  # ---------------------------------------------------------------------------
  # Private
  # ---------------------------------------------------------------------------

  defp resolve_base("project", session) do
    path =
      (session[:git_worktree_path] || session.git_worktree_path)
      |> then(fn p -> if p && File.dir?(p), do: p, else: File.cwd!() end)

    {:ok, path}
  rescue
    _ -> {:error, :no_cwd}
  end

  defp resolve_base("home", _session), do: {:ok, Path.expand("~")}
  defp resolve_base("filesystem", _session), do: {:ok, "/"}
  defp resolve_base(_, _), do: {:error, :unknown_root}

  # "src/components/f" → {"src/components", "f"}
  # "src/components/"  → {"src/components", ""}
  # "foo"              → {"", "foo"}
  # ""                 → {"", ""}
  defp split_partial(partial) do
    case String.split(partial, "/") do
      [prefix] ->
        {"", prefix}

      parts ->
        file_prefix = List.last(parts)
        dir_part = parts |> Enum.drop(-1) |> Enum.join("/")
        {dir_part, file_prefix}
    end
  end

  defp build_result(names, target, dir_part, file_prefix, root_type) do
    at_root = dir_part == ""

    entries =
      names
      |> Enum.reject(fn name -> at_root && name in @excluded_dirs end)
      |> Enum.filter(&String.starts_with?(&1, file_prefix))
      |> Enum.map(fn name ->
        full_path = Path.join(target, name)
        is_dir = File.dir?(full_path)

        rel_path =
          if dir_part == "",
            do: name,
            else: "#{dir_part}/#{name}"

        rel_path = if is_dir, do: "#{rel_path}/", else: rel_path
        insert_text = build_insert_text(rel_path, root_type)

        %{name: name, path: rel_path, insert_text: insert_text, is_dir: is_dir}
      end)
      |> Enum.sort_by(&{!&1.is_dir, &1.name})

    if length(entries) > @max_entries do
      %{entries: Enum.take(entries, @max_entries), truncated: true}
    else
      %{entries: entries, truncated: false}
    end
  end

  defp build_insert_text(rel_path, "home"), do: "@~/#{rel_path}"
  defp build_insert_text(rel_path, "filesystem"), do: "@/#{rel_path}"
  defp build_insert_text(rel_path, _), do: "@#{rel_path}"

  defp empty, do: %{entries: [], truncated: false}
end
```

- [ ] **Step 4: Run tests — expect green**

```bash
mix test test/eye_in_the_sky_web/live/dm_live/file_autocomplete_test.exs
```

Expected: All tests pass.

- [ ] **Step 5: Run compile check**

```bash
mix compile --warnings-as-errors
```

Expected: No errors.

- [ ] **Step 6: Commit**

```bash
git add lib/eye_in_the_sky_web/live/dm_live/file_autocomplete.ex \
        test/eye_in_the_sky_web/live/dm_live/file_autocomplete_test.exs
git commit -m "feat: add FileAutocomplete helper for DM @ trigger"
```

---

## Task 2: Wire `list_files` in DmLive

**Files:**
- Modify: `lib/eye_in_the_sky_web/live/dm_live.ex`

- [ ] **Step 1: Add `handle_event("list_files", ...)` to DmLive**

Find the block of `handle_event` clauses in `lib/eye_in_the_sky_web/live/dm_live.ex` (after the `change_tab` clause, before or after `dm_setting_scope`). Add:

```elixir
@impl true
def handle_event("list_files", %{"partial" => partial, "root" => root}, socket) do
  session = socket.assigns.session
  result = EyeInTheSkyWeb.DmLive.FileAutocomplete.list_entries(partial, root, session)
  {:reply, result, socket}
end
```

- [ ] **Step 2: Compile to verify**

```bash
mix compile --warnings-as-errors
```

Expected: No errors.

- [ ] **Step 3: Commit**

```bash
git add lib/eye_in_the_sky_web/live/dm_live.ex
git commit -m "feat: handle list_files event in DmLive"
```

---

## Task 3: JS — Trigger Detection and File Autocomplete

**Files:**
- Modify: `assets/js/hooks/slash_command_popup.js`

Replace the `checkSlashTrigger` method and add three new methods: `startFileAutocomplete`, `renderFilePopup`, and `_fileSelect`. Also update `slashSelect` to branch on `this.fileMode`.

- [ ] **Step 1: Replace `checkSlashTrigger` with `@@`-first detection**

Replace the existing `checkSlashTrigger` method (lines ~101-148) with:

```js
checkSlashTrigger() {
  const val = this.el.value
  const cursor = this.el.selectionStart
  const textToCursor = val.slice(0, cursor)

  // 1. @@ agent autocomplete — must be checked before @ to avoid fallthrough
  const atAtMatch = textToCursor.match(/(^|[\s(])@@([^\s]*)$/)
  if (atAtMatch) {
    const query = atAtMatch[2]
    this.slashTriggerPos = cursor - query.length - 2  // position of first @
    this.slashTriggerChar = '@@'
    this.fileMode = false
    this.slashFilter(query, 'agent')
    return
  }

  // 2. @ file autocomplete — does not match @@ positions
  const atMatch = textToCursor.match(/(^|[\s(])@([^\s@]*)$/)
  if (atMatch) {
    const rawPartial = atMatch[2]
    this.slashTriggerPos = cursor - rawPartial.length - 1  // position of @
    this.slashTriggerChar = '@'
    this.fileMode = true

    // Determine root from leading characters
    let root, partial
    if (rawPartial.startsWith('~/')) {
      root = 'home'
      partial = rawPartial.slice(2)
    } else if (rawPartial.startsWith('/')) {
      root = 'filesystem'
      partial = rawPartial.slice(1)
    } else {
      root = 'project'
      partial = rawPartial
    }

    this._fileRoot = root
    this.startFileAutocomplete(partial, root)
    return
  }

  // 3. / slash commands (unchanged logic — check for /cmd trigger)
  let triggerPos = -1
  for (let i = cursor - 1; i >= 0; i--) {
    if (val[i] === '/') {
      const before = i === 0 ? '' : val[i - 1]
      if (i === 0 || before === ' ' || before === '\n') {
        triggerPos = i
      }
      break
    }
    if (val[i] === ' ' || val[i] === '\n') break
  }

  if (triggerPos === -1) {
    this.slashClose()
    return
  }

  const query = val.slice(triggerPos + 1, cursor)
  this.slashTriggerPos = triggerPos
  this.slashTriggerChar = '/'
  this.fileMode = false
  this.slashFilter(query, null)
},
```

- [ ] **Step 2: Add `startFileAutocomplete` method**

Add after `checkSlashTrigger`:

```js
startFileAutocomplete(partial, root) {
  this.fileRequestSeq = (this.fileRequestSeq || 0) + 1
  const seq = this.fileRequestSeq

  clearTimeout(this._fileDebounceTimer)
  this._fileDebounceTimer = setTimeout(() => {
    this.pushEvent('list_files', { root, partial }, (reply) => {
      if (seq !== this.fileRequestSeq) return  // stale — discard
      this.renderFilePopup(reply.entries, reply.truncated)
    })
  }, 150)
},
```

- [ ] **Step 3: Add `renderFilePopup` method**

Add after `startFileAutocomplete`:

```js
renderFilePopup(entries, truncated) {
  // Re-attach popup if LiveView's DOM patch removed it
  if (!document.contains(this.popup)) {
    const form = this.el.closest('form')
    if (form) {
      form.style.position = 'relative'
      form.appendChild(this.popup)
    }
  }

  this.popup.innerHTML = ''

  if (entries.length === 0) {
    // Empty state — keep popup open, show informational row
    const empty = document.createElement('div')
    empty.className = 'px-4 py-3 text-xs text-base-content/40 select-none text-center'
    empty.textContent = 'No matching files'
    this.popup.appendChild(empty)
    this.slashOrdered = []
    this.slashIndex = 0
    this.slashOpen = true
    this.popup.classList.remove('hidden')
    return
  }

  // Section header
  const header = document.createElement('div')
  header.className = 'px-3 py-1 text-xs font-semibold uppercase tracking-wider text-base-content/40 bg-base-content/[0.02] sticky top-0'
  header.textContent = 'Files'
  this.popup.appendChild(header)

  const ordered = []

  for (const [i, entry] of entries.entries()) {
    const idx = ordered.length
    ordered.push(entry)

    const row = document.createElement('button')
    row.type = 'button'
    row.dataset.slashIdx = idx
    row.className = 'w-full flex items-center gap-3 px-3 py-2 text-left transition-colors text-sm'

    const iconName = entry.is_dir ? 'folder' : 'document'
    const iconHtml = entry.is_dir
      ? '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor" class="size-4 text-base-content/40 shrink-0"><path d="M2 6a2 2 0 0 1 2-2h5l2 2h5a2 2 0 0 1 2 2v6a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2V6Z"/></svg>'
      : '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor" class="size-4 text-base-content/30 shrink-0"><path d="M3 3.5A1.5 1.5 0 0 1 4.5 2h6.879a1.5 1.5 0 0 1 1.06.44l4.122 4.12A1.5 1.5 0 0 1 17 7.622V16.5a1.5 1.5 0 0 1-1.5 1.5h-11A1.5 1.5 0 0 1 3 16.5v-13Z"/></svg>'

    row.innerHTML = `
      ${iconHtml}
      <span class="font-medium text-base-content truncate flex-1">${this._escapeHtml(entry.name)}${entry.is_dir ? '/' : ''}</span>
    `

    row.addEventListener('mouseenter', () => {
      this.slashIndex = idx
      this._updateFileActive()
    })
    row.addEventListener('mousedown', (e) => {
      e.preventDefault()
      this.slashIndex = idx
      this.slashSelect()
    })

    this.popup.appendChild(row)
  }

  if (truncated) {
    const footer = document.createElement('div')
    footer.className = 'px-3 py-1.5 text-xs text-base-content/30 border-t border-base-content/5 select-none'
    footer.textContent = 'Showing first 50 — keep typing to narrow'
    this.popup.appendChild(footer)
  }

  // Keyboard hint
  const hint = document.createElement('div')
  hint.className = 'px-3 py-1.5 text-xs text-base-content/30 border-t border-base-content/5 flex items-center gap-3 sticky bottom-0 bg-base-100'
  hint.innerHTML = '<kbd class="font-mono">↑↓</kbd> navigate &nbsp;<kbd class="font-mono">↵</kbd> or <kbd class="font-mono">Tab</kbd> select &nbsp;<kbd class="font-mono">Esc</kbd> dismiss'
  this.popup.appendChild(hint)

  this.slashOrdered = ordered
  this.slashIndex = 0
  this.slashOpen = true
  this.popup.classList.remove('hidden')

  this._updateFileActive()
},

_updateFileActive() {
  const rows = this.popup.querySelectorAll('button[data-slash-idx]')
  rows.forEach(row => {
    const active = parseInt(row.dataset.slashIdx) === this.slashIndex
    row.classList.toggle('bg-base-content/[0.06]', active)
    if (active) row.scrollIntoView?.({ block: 'nearest' })
  })
},

_escapeHtml(str) {
  return str
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
},
```

- [ ] **Step 4: Add `_fileSelect` method**

Add after `_escapeHtml`:

```js
_fileSelect() {
  const item = this.slashOrdered[this.slashIndex]
  if (!item) return

  const val = this.el.value
  const cursor = this.el.selectionStart
  const before = val.slice(0, this.slashTriggerPos)
  const after = val.slice(cursor)
  const newVal = before + item.insert_text + after
  this.el.value = newVal

  const pos = before.length + item.insert_text.length
  this.el.setSelectionRange(pos, pos)
  this.el.focus()

  if (item.is_dir) {
    // Fire input: checkSlashTrigger will detect the new @path/ and call startFileAutocomplete
    this.el.dispatchEvent(new Event('input', { bubbles: true }))
  } else {
    this.slashClose()
    this.el.dispatchEvent(new Event('input', { bubbles: true }))
  }
  this.autoResize && this.autoResize()
},
```

- [ ] **Step 5: Update `slashSelect` to branch on `fileMode`**

Replace the existing `slashSelect` method:

```js
slashSelect() {
  if (this.fileMode) {
    this._fileSelect()
    return
  }

  const item = (this.slashOrdered || this.slashFiltered)[this.slashIndex]
  if (!item) return

  if (this.enumAC.handleSelect()) return

  const val = this.el.value
  const cursor = this.el.selectionStart
  const prefix = val.slice(0, this.slashTriggerPos)
  const suffix = val.slice(cursor)

  const { text: insertion, selectRange } = this.slashBuildInsertion(item)
  const newVal = prefix + insertion + suffix
  this.el.value = newVal

  if (selectRange) {
    const base = prefix.length
    this.el.setSelectionRange(base + selectRange[0], base + selectRange[1])
  } else {
    const pos = prefix.length + insertion.length
    this.el.setSelectionRange(pos, pos)
  }
  this.el.focus()

  this.slashClose()
  this.autoResize && this.autoResize()
},
```

- [ ] **Step 6: Initialize `fileMode` in `mounted`**

In `mounted()`, add after `this.slashTriggerChar = '/'`:

```js
this.fileMode = false
this._fileRoot = 'project'
this.fileRequestSeq = 0
this._fileDebounceTimer = null
```

- [ ] **Step 7: Clean up file debounce timer in `slashClose`**

In `slashClose()`, add before the existing body:

```js
slashClose() {
  clearTimeout(this._fileDebounceTimer)
  this.fileMode = false
  this.slashOpen = false
  this.slashTriggerPos = -1
  this.slashTriggerChar = '/'
  this.slashOrdered = []
  this.enumAC.close()
  this.popup.classList.add('hidden')
  this.popup.innerHTML = ''
},
```

- [ ] **Step 8: Verify the full file builds cleanly**

```bash
cd /Users/urielmaldonado/projects/eits/web/assets
npx tsc --noEmit 2>&1 | head -30 || echo "No TS errors (JS file)"
```

(The file is plain JS so TypeScript won't flag it — just confirm it parses.)

- [ ] **Step 9: Commit**

```bash
git add assets/js/hooks/slash_command_popup.js
git commit -m "feat: add @ file autocomplete and remap @ agents to @@"
```

---

## Task 4: JS Tests

**Files:**
- Create: `assets/js/hooks/slash_command_popup_file.test.js`

- [ ] **Step 1: Write tests for trigger parsing and `_fileSelect`**

```js
// assets/js/hooks/slash_command_popup_file.test.js
import { describe, it, expect, beforeEach, vi } from 'vitest'
import { SlashCommandPopup } from './slash_command_popup.js'

function makeCtx(overrides = {}) {
  const form = document.createElement('form')
  form.style.position = 'relative'
  document.body.appendChild(form)

  const el = document.createElement('textarea')
  form.appendChild(el)

  const popup = document.createElement('div')
  popup.className = 'hidden'
  form.appendChild(popup)

  const ctx = {
    el,
    popup,
    slashItems: [],
    slashFiltered: [],
    slashOrdered: [],
    slashIndex: 0,
    slashOpen: false,
    slashTriggerPos: -1,
    slashTriggerChar: '/',
    fileMode: false,
    _fileRoot: 'project',
    fileRequestSeq: 0,
    _fileDebounceTimer: null,
    pushEventCalls: [],
    pushEvent(name, payload, cb) {
      this.pushEventCalls.push({ name, payload, cb })
    },
    enumAC: { handleSelect: () => false, close: () => {}, checkEnumContext: () => {} },
    slashFilter: vi.fn(),
    slashClose: vi.fn(),
    autoResize: vi.fn(),
    ...overrides,
  }

  // Bind methods from SlashCommandPopup onto ctx
  Object.assign(ctx, {
    startFileAutocomplete: SlashCommandPopup.startFileAutocomplete.bind(ctx),
    renderFilePopup: SlashCommandPopup.renderFilePopup.bind(ctx),
    _fileSelect: SlashCommandPopup._fileSelect.bind(ctx),
    _updateFileActive: SlashCommandPopup._updateFileActive.bind(ctx),
    _escapeHtml: SlashCommandPopup._escapeHtml.bind(ctx),
    checkSlashTrigger: SlashCommandPopup.checkSlashTrigger.bind(ctx),
    slashSelect: SlashCommandPopup.slashSelect.bind(ctx),
  })

  return ctx
}

describe('checkSlashTrigger — @@ agent trigger', () => {
  let ctx
  beforeEach(() => {
    document.body.innerHTML = ''
    ctx = makeCtx()
  })

  it('detects @@ at start of input', () => {
    ctx.el.value = '@@claude'
    ctx.el.setSelectionRange(8, 8)
    ctx.checkSlashTrigger()
    expect(ctx.slashFilter).toHaveBeenCalledWith('claude', 'agent')
    expect(ctx.fileMode).toBe(false)
  })

  it('detects @@ after space', () => {
    ctx.el.value = 'hello @@my-agent'
    ctx.el.setSelectionRange(16, 16)
    ctx.checkSlashTrigger()
    expect(ctx.slashFilter).toHaveBeenCalledWith('my-agent', 'agent')
  })

  it('sets slashTriggerPos to position of first @', () => {
    ctx.el.value = 'hello @@claude'
    ctx.el.setSelectionRange(14, 14)
    ctx.checkSlashTrigger()
    // "hello " = 6 chars, so first @ is at index 6
    expect(ctx.slashTriggerPos).toBe(6)
  })
})

describe('checkSlashTrigger — @ file trigger', () => {
  let ctx
  beforeEach(() => {
    document.body.innerHTML = ''
    ctx = makeCtx()
    // startFileAutocomplete uses setTimeout; capture calls
    ctx.startFileAutocomplete = vi.fn()
  })

  it('detects @ project-root trigger', () => {
    ctx.el.value = '@src/foo'
    ctx.el.setSelectionRange(8, 8)
    ctx.checkSlashTrigger()
    expect(ctx.startFileAutocomplete).toHaveBeenCalledWith('src/foo', 'project')
    expect(ctx.fileMode).toBe(true)
    expect(ctx._fileRoot).toBe('project')
  })

  it('detects @~/ as home root', () => {
    ctx.el.value = '@~/Documents/f'
    ctx.el.setSelectionRange(14, 14)
    ctx.checkSlashTrigger()
    expect(ctx.startFileAutocomplete).toHaveBeenCalledWith('Documents/f', 'home')
    expect(ctx._fileRoot).toBe('home')
  })

  it('detects @/ as filesystem root', () => {
    ctx.el.value = '@/etc/h'
    ctx.el.setSelectionRange(7, 7)
    ctx.checkSlashTrigger()
    expect(ctx.startFileAutocomplete).toHaveBeenCalledWith('etc/h', 'filesystem')
    expect(ctx._fileRoot).toBe('filesystem')
  })

  it('does not trigger @ when preceded by @', () => {
    ctx.el.value = '@@claude'
    ctx.el.setSelectionRange(8, 8)
    ctx.checkSlashTrigger()
    // @ branch should not fire — @@ should match first
    expect(ctx.slashFilter).toHaveBeenCalledWith('claude', 'agent')
    expect(ctx.startFileAutocomplete).not.toHaveBeenCalled()
  })

  it('sets slashTriggerPos to position of @', () => {
    ctx.el.value = 'send @src/f'
    ctx.el.setSelectionRange(11, 11)
    ctx.checkSlashTrigger()
    // "send " = 5 chars, @ at index 5
    expect(ctx.slashTriggerPos).toBe(5)
  })
})

describe('renderFilePopup', () => {
  let ctx
  beforeEach(() => {
    document.body.innerHTML = ''
    ctx = makeCtx()
  })

  it('renders empty state when no entries', () => {
    ctx.renderFilePopup([], false)
    expect(ctx.popup.textContent).toContain('No matching files')
    expect(ctx.slashOpen).toBe(true)
    expect(ctx.slashOrdered).toEqual([])
  })

  it('renders file entries and sets slashOrdered', () => {
    const entries = [
      { name: 'components', path: 'src/components/', insert_text: '@src/components/', is_dir: true },
      { name: 'router.ex', path: 'src/router.ex', insert_text: '@src/router.ex', is_dir: false },
    ]
    ctx.renderFilePopup(entries, false)
    expect(ctx.slashOrdered).toHaveLength(2)
    expect(ctx.slashOpen).toBe(true)
    expect(ctx.popup.classList.contains('hidden')).toBe(false)
  })

  it('shows truncated footer when truncated is true', () => {
    const entries = [
      { name: 'foo.ex', path: 'foo.ex', insert_text: '@foo.ex', is_dir: false }
    ]
    ctx.renderFilePopup(entries, true)
    expect(ctx.popup.textContent).toContain('Showing first 50')
  })
})

describe('_fileSelect', () => {
  let ctx
  beforeEach(() => {
    document.body.innerHTML = ''
    ctx = makeCtx()
    ctx.slashClose = vi.fn()
    ctx.startFileAutocomplete = vi.fn()
  })

  it('inserts insert_text for a file and closes popup', () => {
    ctx.el.value = 'hello @src/r'
    ctx.el.setSelectionRange(12, 12)
    ctx.slashTriggerPos = 6  // position of @
    ctx.slashOrdered = [
      { name: 'router.ex', path: 'src/router.ex', insert_text: '@src/router.ex', is_dir: false }
    ]
    ctx.slashIndex = 0
    ctx._fileSelect()
    expect(ctx.el.value).toBe('hello @src/router.ex')
    expect(ctx.slashClose).toHaveBeenCalled()
  })

  it('inserts insert_text for a directory and keeps popup open via input event', () => {
    ctx.el.value = '@src'
    ctx.el.setSelectionRange(4, 4)
    ctx.slashTriggerPos = 0
    ctx.slashOrdered = [
      { name: 'src', path: 'src/', insert_text: '@src/', is_dir: true }
    ]
    ctx.slashIndex = 0

    const inputEvents = []
    ctx.el.addEventListener('input', (e) => inputEvents.push(e))

    ctx._fileSelect()
    expect(ctx.el.value).toBe('@src/')
    expect(ctx.slashClose).not.toHaveBeenCalled()
    expect(inputEvents).toHaveLength(1)
  })

  it('does nothing when slashOrdered is empty', () => {
    ctx.slashOrdered = []
    ctx.slashIndex = 0
    ctx._fileSelect()
    expect(ctx.slashClose).not.toHaveBeenCalled()
  })
})
```

- [ ] **Step 2: Run tests — expect failures (methods not yet exported / hoisted correctly)**

```bash
cd /Users/urielmaldonado/projects/eits/web/assets
npx vitest run js/hooks/slash_command_popup_file.test.js 2>&1 | tail -30
```

Fix any import or binding issues before proceeding. Methods like `_fileSelect`, `renderFilePopup`, etc. must be exported as properties on the `SlashCommandPopup` object (they already are if you added them directly to the object literal).

- [ ] **Step 3: Run tests — expect green**

```bash
npx vitest run js/hooks/slash_command_popup_file.test.js
```

Expected: All tests pass.

- [ ] **Step 4: Run full JS test suite to confirm no regressions**

```bash
npx vitest run
```

Expected: All existing tests still pass.

- [ ] **Step 5: Run mix compile**

```bash
cd /Users/urielmaldonado/projects/eits/web
mix compile --warnings-as-errors
```

- [ ] **Step 6: Commit**

```bash
git add assets/js/hooks/slash_command_popup_file.test.js
git commit -m "test: JS unit tests for @ file autocomplete trigger and _fileSelect"
```

---

## Self-Review Notes

**Spec coverage check:**

| Spec requirement | Covered by |
|-----------------|-----------|
| `@` → file, `@@` → agent, `/` unchanged | Task 3 Step 1 (`checkSlashTrigger`) |
| `@@` detected before `@` | Task 3 Step 1 (order of checks) |
| Real-time pushEvent with debounce | Task 3 Step 2 (`startFileAutocomplete`) |
| Stale response guard (`fileRequestSeq`) | Task 3 Step 2 |
| Root resolution: project/home/filesystem | Task 1 (`resolve_base`), Task 3 Step 1 |
| `under_root?` with `/` fix | Task 1 (tested in `file_autocomplete_test.exs`) |
| Excluded dirs at root level | Task 1 (`build_result`) |
| Dotfiles shown | Task 1 (no filter on `.` prefix) |
| Dirs before files, alphabetical | Task 1 (`Enum.sort_by`) |
| Max 50, `truncated` flag | Task 1 |
| `insert_text` correct per root | Task 1 (`build_insert_text`), tested |
| `path` for refetch, `insert_text` for insertion | Task 3 Steps 4-5 |
| Directory selection: immediate refetch via input event | Task 3 Step 4 (`_fileSelect`) |
| File selection: insert + close | Task 3 Step 4 |
| Empty state: "No matching files" row | Task 3 Step 3 (`renderFilePopup`) |
| Truncated footer | Task 3 Step 3 |
| Keyboard nav works (↑↓ Enter Tab Esc) | Handled by existing `CommandHistory` keydown + `slashMove`/`slashSelect`/`slashClose` |
| `handle_event("list_files")` in DmLive | Task 2 |
| Tests for path safety, sorting, truncation, insert_text | Task 1 (ExUnit), Task 4 (vitest) |
