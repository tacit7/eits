# CodeMirror Edit Button — Agents, Skills, Prompts Pages

**Date:** 2026-07-01  
**Status:** Approved (post-review)

## Overview

Add an **Edit** button to the detail panel on the Agents, Skills, and Prompts pages. Clicking it replaces the current preview/raw content area with a full CodeMirror 6 editor. Ctrl+S writes changes back — to disk for agents and skills, to the DB for prompts. The header shows a Ctrl+S hint and a Cancel button. Cancel discards unsaved edits without confirmation (v1). A clickable Save button is out of scope for this iteration unless the CodeMirror hook is extended to expose editor content on demand (which would require JS dispatch plumbing around the `phx-update="ignore"` boundary).

## Scope

**In:**
- Agents page (`project_live/agents.ex`) — edits the agent YAML/MD file on disk via `agent.abs_path`
- Skills page (`project_live/skills.ex`) — edits the skill file on disk via `skill.abs_path` (field to be added)
- Prompts page (`project_live/prompts.ex`) — edits `prompt.prompt_text` in the DB
- YAML language support added to CM6 (`@codemirror/lang-yaml`)

**Out:**
- Mobile view (detail panel is desktop-only)
- Prompt metadata fields (name, slug, description, tags) — handled by `prompt_show.ex`
- Creating or deleting files
- Dirty-state confirmation on cancel or item switch (v1 does not track dirty state — unsaved edits are silently discarded)
- Clickable Save button (Ctrl+S only)
- Conflict detection: v1 uses last-write-wins and does not detect external file changes between load and save

## Architecture

### State: `@detail_tab`

All three pages already track `@detail_tab` with `:preview` and `:raw` atoms. We add a third value: `:edit`. The editor mounts when `@detail_tab == :edit` and unmounts when it transitions away.

No new assigns are needed — the content to edit comes from the already-loaded struct (`agent.content`, `skill.content`, `prompt.prompt_text`).

### Save event: `"file_changed"`

The existing `CodeMirrorHook` Ctrl+S keymap already fires `pushEvent("file_changed", { content })`. We use this exact event on all three pages. Each LiveView's `handle_event("file_changed", ...)` does the right thing for its data layer.

### ID stability

The editor div `id` is keyed on the selected item's ID/UUID (e.g. `"proj-agent-editor-#{agent.id}"`). When a different item is selected, the old editor is destroyed and a new one mounts. The `phx-update="ignore"` attribute prevents morphdom from touching the editor internals mid-session.

### Content encoding

Agent/skill files contain YAML frontmatter with `<`, `>`, `---` etc. that break HTML attribute embedding if passed raw. Content is encoded with `Base.encode64(content || "")` on the server before being placed in `data-content`. The `|| ""` guard handles nil content (empty files, unset DB fields). The hook already calls `atob(dataset.content)` on line 11 — no hook changes needed.

## Changes Required

### 1. YAML language package

```
npm install @codemirror/lang-yaml --prefix assets
```

Add to `assets/js/cm_lang.js`:
```js
case "yaml":
case "yml": {
  const { yaml } = await import("@codemirror/lang-yaml")
  return yaml()
}
```

Add to `assets/vite.config.mjs`:
- `optimizeDeps.include`: `"@codemirror/lang-yaml"`
- `resolve.dedupe`: `"@codemirror/lang-yaml"`

### 2. Skill struct — add `abs_path`

**`lib/eye_in_the_sky_web/live/overview_live/skills/skill.ex`**

```elixir
defstruct [:id, :slug, :filename, :path, :abs_path, :source, :description, :content, :size, :mtime]
```

**`lib/eye_in_the_sky_web/live/shared/skills_helpers.ex`**  
Populate `abs_path: path` in both `read_skill_entry/4` and `read_skills_dir_entry/4`, where `path` is already the local variable holding the absolute filesystem path.

### 3. Language detection helper

Private function added to all three LiveView pages (or extracted to a shared helper if preferred):

```elixir
defp edit_language(%{path: path}) when is_binary(path), do: lang_from_path(path)
defp edit_language(%{abs_path: path}) when is_binary(path), do: lang_from_path(path)
defp edit_language(_), do: "markdown"

defp lang_from_path(path) do
  case Path.extname(path) do
    ".yaml" -> "yaml"
    ".yml"  -> "yaml"
    ".json" -> "json"
    _       -> "markdown"  # .md, .markdown, unknown → Markdown mode
  end
end
```

Skills are usually `.md` files with YAML frontmatter — Markdown mode is correct for them. YAML mode is only used when the file extension is explicitly `.yaml`/`.yml`.

Prompts have no path, so call `edit_language(%{})` which falls through to `"markdown"`.

### 4. Path security — `open_path_allowed?/2`

**All write operations must validate the target path before calling `File.write/2`.**

Security contract:
- Expand the target path with `Path.expand/1`
- Expand all allowed roots with `Path.expand/1`
- The final expanded path must begin with an expanded allowed root followed by `/`
- Allowed roots for agents: `~/.claude/agents` and `project/.claude/agents`
- Allowed roots for skills: `~/.claude/skills`, `~/.claude/commands`, `project/.claude/skills`, `project/.claude/commands`

The `open_path_allowed?/2` function in agents.ex already implements this pattern. Skills needs the equivalent guard (either extract to a shared helper or implement inline mirroring the agents pattern).

### 5. Agents page (`project_live/agents.ex`)

**New handle_events:**

```elixir
def handle_event("edit_content", _, socket),
  do: {:noreply, assign(socket, :detail_tab, :edit)}

def handle_event("cancel_edit", _, socket),
  do: {:noreply, assign(socket, :detail_tab, :preview)}

def handle_event("file_changed", %{"content" => content}, socket) do
  case socket.assigns.selected_agent do
    %{abs_path: path, id: id} when is_binary(path) ->
      if open_path_allowed?(path, socket) do
        case File.write(path, content) do
          :ok ->
            socket =
              socket
              |> load_agents()
              |> reselect_agent(id)
              |> assign(:detail_tab, :preview)
              |> put_flash(:info, "Agent saved")
            {:noreply, socket}
          {:error, reason} ->
            {:noreply, put_flash(socket, :error, "Failed to save agent: #{inspect(reason)}")}
        end
      else
        {:noreply, put_flash(socket, :error, "Write not permitted for this path")}
      end
    _ ->
      {:noreply, put_flash(socket, :error, "No file path available")}
  end
end

# Reselects by id after list reload to keep the detail panel open with fresh content.
defp reselect_agent(socket, id) do
  selected = Enum.find(socket.assigns.agents, &(&1.id == id))
  assign(socket, :selected_agent, selected)
end
```

**Template changes:**
- Add `Edit` tab button next to Preview/Raw in the detail panel header
- When `@detail_tab == :edit`: replace tab buttons with a Ctrl+S hint + Cancel button
- Content area gains an `:edit` branch:

```heex
<%!-- detail panel header tab row --%>
<div class="flex items-center gap-1 mt-3">
  <%= if @detail_tab == :edit do %>
    <span class="text-[10px] text-base-content/40 mr-2">Ctrl+S to save</span>
    <button
      phx-click="cancel_edit"
      class="btn btn-ghost btn-xs"
    >
      Cancel
    </button>
  <% else %>
    <button phx-click="set_detail_tab" phx-value-tab="preview"
      class={"px-3 py-1 rounded text-xs font-medium " <>
        if(@detail_tab == :preview, do: "bg-base-content/8 text-base-content", else: "text-base-content/50 hover:text-base-content")}>
      Preview
    </button>
    <button phx-click="set_detail_tab" phx-value-tab="raw"
      class={"px-3 py-1 rounded text-xs font-medium " <>
        if(@detail_tab == :raw, do: "bg-base-content/8 text-base-content", else: "text-base-content/50 hover:text-base-content")}>
      Raw
    </button>
    <button phx-click="edit_content"
      class="px-3 py-1 rounded text-xs font-medium text-base-content/50 hover:text-base-content">
      Edit
    </button>
    <span class="ml-auto text-[10px] text-base-content/35 tabular-nums">
      {FileHelpers.format_size(@selected_agent.size)}
    </span>
  <% end %>
</div>

<%!-- detail panel content area --%>
<div class="flex-1 overflow-hidden">
  <%= if @detail_tab == :edit do %>
    <div
      id={"proj-agent-editor-#{@selected_agent.id}"}
      phx-hook="CodeMirror"
      phx-update="ignore"
      data-content={Base.encode64(@selected_agent.content || "")}
      data-lang={edit_language(@selected_agent)}
      class="h-full"
    ></div>
  <% else %>
    <div class="flex-1 overflow-y-auto">
      <%= if @detail_tab == :preview do %>
        <div
          id={"proj-agent-viewer-#{@selected_agent.id}"}
          class="dm-markdown px-6 py-4 text-sm text-base-content leading-relaxed"
          phx-hook="MarkdownMessage"
          data-raw-body={@selected_agent.content}
        ></div>
      <% else %>
        <pre class="px-6 py-4 text-xs font-mono text-base-content/75 whitespace-pre-wrap break-words leading-relaxed">{@selected_agent.content}</pre>
      <% end %>
    </div>
  <% end %>
</div>
```

**Edit button visibility:** Only rendered when `@selected_agent.abs_path` is a non-nil binary. If an agent has no absolute path, the Edit button is hidden.

### 6. Skills page (`project_live/skills.ex`)

Same pattern. Save handler **must include the path guard**:

```elixir
def handle_event("file_changed", %{"content" => content}, socket) do
  case socket.assigns.selected_skill do
    %{abs_path: path, id: id} when is_binary(path) ->
      if skill_write_allowed?(path, socket) do
        case File.write(path, content) do
          :ok ->
            socket =
              socket
              |> load_skills()
              |> reselect_skill(id)
              |> assign(:detail_tab, :preview)
              |> put_flash(:info, "Skill saved")
            {:noreply, socket}
          {:error, reason} ->
            {:noreply, put_flash(socket, :error, "Failed to save skill: #{inspect(reason)}")}
        end
      else
        {:noreply, put_flash(socket, :error, "Write not permitted for this path")}
      end
    _ ->
      {:noreply, put_flash(socket, :error, "No file path available")}
  end
end

defp skill_write_allowed?(path, socket) do
  expanded = Path.expand(path)
  user_skills = Path.expand("~/.claude/skills")
  user_commands = Path.expand("~/.claude/commands")

  project_roots =
    case socket.assigns[:project] do
      %{path: p} when is_binary(p) and p != "" ->
        [
          Path.expand(Path.join(p, ".claude/skills")),
          Path.expand(Path.join(p, ".claude/commands"))
        ]
      _ -> []
    end

  allowed = [user_skills, user_commands | project_roots]
  Enum.any?(allowed, fn root -> String.starts_with?(expanded, root <> "/") end)
end

defp reselect_skill(socket, id) do
  selected = Enum.find(socket.assigns.skills, &(&1.id == id))
  assign(socket, :selected_skill, selected)
end
```

Editor div id: `"proj-skill-editor-#{@selected_skill.id}"`

**Edit button visibility:** Only shown when `@selected_skill.abs_path` is a non-nil binary.

### 7. Prompts page (`project_live/prompts.ex`)

```elixir
def handle_event("edit_content", _, socket),
  do: {:noreply, assign(socket, :detail_tab, :edit)}

def handle_event("cancel_edit", _, socket),
  do: {:noreply, assign(socket, :detail_tab, :preview)}

def handle_event("file_changed", %{"content" => content}, socket) do
  case socket.assigns.selected_prompt do
    nil ->
      {:noreply, socket}
    prompt ->
      case Prompts.update_prompt(prompt, %{prompt_text: content}) do
        {:ok, updated} ->
          socket =
            socket
            |> load_prompts()
            |> assign(:selected_prompt, updated)
            |> assign(:detail_tab, :preview)
            |> put_flash(:info, "Prompt saved")
          {:noreply, socket}
        {:error, _changeset} ->
          # Generic for v1 — changeset errors on prompt_text are unlikely (plain text, no constraints)
          {:noreply, put_flash(socket, :error, "Failed to save prompt")}
      end
  end
end
```

Note: `load_prompts()` is called first, then `selected_prompt` is explicitly reassigned to `updated` — ensuring the detail panel shows the saved struct, not whatever `load_prompts` may have left in the assign.

Language: `"markdown"` (hardcoded via `edit_language(%{})`).  
Editor div id: `"proj-prompt-editor-#{@selected_prompt.uuid}"`

### 8. `codemirror.js` — no changes

The existing Ctrl+S keymap fires `pushEvent("file_changed", { content })`. This is exactly what we need.

## UI Behavior

| State | Header area shows | Content area shows |
|-------|------------------|-------------------|
| `:preview` | Preview ● / Raw / Edit tabs | Rendered markdown |
| `:raw` | Preview / Raw ● / Edit tabs | `<pre>` text |
| `:edit` | "Ctrl+S to save" hint + Cancel button (tabs hidden) | CM6 editor, full height |

- Edit button uses same `px-3 py-1 rounded text-xs font-medium` styling as Preview/Raw, without active highlight (it's a mode-switch, not a persistent tab)
- When `@detail_tab == :edit`, the tab row is replaced with the hint + Cancel so there's no visual confusion about current state
- Selecting a different item from the list while in `:edit` mode silently discards edits (v1 behavior — `select_*` events assign `:preview` and mount a new editor for the new item)

## Security Summary

- All disk writes gated by path allow-list validation before `File.write/2`
- All paths normalized with `Path.expand/1` before comparison
- Skills uses `skill_write_allowed?/2` mirroring the agents pattern
- No write path is derived from user input — only from the server-side loaded struct's `abs_path` field

## Edge Cases

- **Nil content**: `Base.encode64(content || "")` prevents crashes on empty files or unset DB fields
- **Missing abs_path**: Edit button hidden; save handler pattern-matches on `%{abs_path: path} when is_binary(path)` and falls through to an error otherwise
- **Switching items while editing**: Silently discards edits (v1). `select_*` events reset `detail_tab` to `:preview`
- **Imports in-flight on save**: Hook guard handles this — `_view` nil means save is a no-op; generation counter prevents stale mounts
- **File write race**: Last-write-wins. No mtime comparison in v1
- **Prompt changeset errors**: Generic flash message in v1; changeset errors on plain `prompt_text` are unlikely
