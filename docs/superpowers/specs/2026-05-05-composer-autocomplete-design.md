# Composer Autocomplete: File (`@`) and Agent (`@@`) — Design Spec

**Date:** 2026-05-05  
**Scope:** DM composer textarea in `DmLive` / `DmComposer` hook

---

## Summary

Add two new autocomplete triggers to the DM composer:

- `@` → file autocomplete (real-time, server-fetched)
- `@@` → agent name autocomplete (client-side, existing `slash_items`)

The existing `/` trigger for slash commands and skills is unchanged.

---

## Trigger Mapping

| Trigger | Behavior | Data source |
|---------|----------|-------------|
| `@` | File path autocomplete | Server `list_files` pushEvent |
| `@@` | Agent name autocomplete | Client-side `slash_items` filtered by `type === "agent"` |
| `/` | Slash commands, skills, prompts | Client-side `slash_items` (unchanged) |

**Detection order:** `@@` is checked before `@`. A `@@` match must not fall through to `@`.

### Trigger regex

```js
// @@ — agent autocomplete
/(^|[\s(])@@([^\s]*)$/

// @ — file autocomplete (does NOT match @@ positions)
/(^|[\s(])@([^\s@]*)$/
```

Trigger is only active when the match ends at the current cursor position.

---

## File Root Resolution

The character(s) immediately after `@` determine the root directory used for listing.

| User input | `root` sent to server | Resolved base |
|------------|----------------------|---------------|
| `@~/…` | `"home"` | `Path.expand("~")` |
| `@/…` | `"filesystem"` | `"/"` |
| `@anything-else` | `"project"` | `session.working_directory` or app project root fallback |

The server rejects any `root` value not in `["project", "home", "filesystem"]` and returns an empty result set. No error, no explanation — just empty.

---

## Client → Server Payload

Event name: `"list_files"`

```json
{
  "root": "project",
  "partial": "src/components/f"
}
```

`partial` is the path fragment after the root prefix (stripped of `~/` or `/` when those are the root tokens).

---

## Server: `handle_event("list_files", ...)`

Location: delegated to new `EyeInTheSkyWeb.DmLive.FileAutocomplete` helper module.

### Algorithm

1. Validate `root` is one of `"project"`, `"home"`, `"filesystem"`. Return empty on unknown.
2. Resolve base dir:
   - `"project"` → `session.working_directory` if set; else app project root
   - `"home"` → `Path.expand("~")`
   - `"filesystem"` → `"/"`
3. Split `partial` into `{dir_part, file_prefix}`:
   - `"src/components/f"` → `{"src/components", "f"}`
   - `"src/components/"` → `{"src/components", ""}`
   - `"foo"` → `{"", "foo"}`
4. Join base dir + `dir_part` and resolve with `Path.expand/1`.
5. **Path traversal guard** — segment-aware comparison:

```elixir
defp under_root?(path, root) do
  expanded_path = Path.expand(path)
  expanded_root = Path.expand(root)
  expanded_path == expanded_root or
    String.starts_with?(expanded_path, expanded_root <> "/")
end
```

Return empty if resolved dir does not satisfy `under_root?(resolved_dir, base_dir)`.

Note on symlinks: `Path.expand/1` does not resolve symlinks. Symlink hardening via `File.realpath/1` is post-MVP.

6. List the resolved directory with `File.ls/1`. On any error, return empty.
7. Filter entries whose name starts with `file_prefix` (case-sensitive).
8. **Exclude junk directories** when `dir_part` is empty (i.e., user is at root level):

```elixir
@excluded_dirs ~w(.git node_modules deps _build .elixir_ls .tmp priv/static/assets)
```

Once a user explicitly navigates into an excluded dir (e.g. `@node_modules/`), they get what they asked for.

9. Sort: directories first, then files, alphabetically within each group.
10. Limit to 50 entries. Set `truncated: true` if more existed.
11. Build insertion-safe paths — relative to the selected root, never raw absolute server paths (exception: `filesystem` root, where absolute paths are correct by definition).

### Response shape

```elixir
{:reply,
 %{
   entries: [
     %{name: "components", path: "src/components/", is_dir: true},
     %{name: "router.ex",  path: "src/router.ex",   is_dir: false}
   ],
   truncated: false
 },
 socket}
```

---

## Client: JS Changes (`slash_command_popup.js`)

### Trigger detection (`checkSlashTrigger`)

Check in this order:
1. `@@` pattern → `slashFilter(query, 'agent')` (existing client-side path, no changes)
2. `@` pattern (must not match a `@@` position) → `startFileAutocomplete(partial, root)`
3. `/` pattern (unchanged)
4. None matched → `slashClose()`

### `startFileAutocomplete(partial, root)`

```js
startFileAutocomplete(partial, root) {
  this.fileRequestSeq = (this.fileRequestSeq || 0) + 1
  const seq = this.fileRequestSeq

  clearTimeout(this._fileDebounceTimer)
  this._fileDebounceTimer = setTimeout(() => {
    this.pushEvent("list_files", { root, partial }, (reply) => {
      if (seq !== this.fileRequestSeq) return  // stale — discard
      this.renderFilePopup(reply.entries, reply.truncated)
    })
  }, 150)
}
```

### `renderFilePopup(entries, truncated)`

Renders into `this.popup` (same DOM node as slash popup). Dirs show a folder icon; files show a document icon. If `truncated`, append a non-selectable footer: _"Showing first 50 — keep typing to narrow"_.

### Directory selection

1. Insert `@{entry.path}` (already ends with `/`) at trigger position.
2. Update `this.slashTriggerPos`.
3. **Immediately** call `startFileAutocomplete(entry.path, currentRoot)` — do not wait for next input event.
4. Popup stays open; content refreshes with children.

### File selection

Insert `@{entry.path}` and call `slashClose()`.

### Debounce and stale-response guard

- 150ms debounce before sending `list_files`.
- `fileRequestSeq` incremented on every new call. Reply discarded if `seq !== this.fileRequestSeq`.

### Spaces in paths (MVP limitation)

Trigger parsing stops at whitespace. Paths with spaces may appear in results and be inserted, but will not be re-detected as an active trigger during subsequent edits. Post-MVP fix: quoted path syntax `@"docs/my file.md"`.

---

## Security

- Server lists entries only — never reads file contents.
- Path traversal prevented via segment-aware `under_root?/2`.
- Unknown root values return empty silently.
- Any `File.ls` error returns empty silently.
- `path` in response is insertion-safe; absolute host paths are not leaked for `project` or `home` roots.
- Result count capped at 50.

---

## Out of Scope (MVP)

- Symlink traversal hardening (`File.realpath/1`)
- Quoted path syntax for space-containing paths
- Fuzzy/ranked matching (prefix filter only, like tab completion)
- `.gitignore`-aware filtering
- Multi-`@` mentions in one message (each trigger detected at cursor position independently)

---

## Files to Change

| File | Change |
|------|--------|
| `assets/js/hooks/slash_command_popup.js` | Updated trigger detection; `startFileAutocomplete`, `renderFilePopup`; directory-select immediate refetch; debounce + seq guard |
| `lib/eye_in_the_sky_web/live/dm_live.ex` | New `handle_event("list_files", ...)` clause |
| `lib/eye_in_the_sky_web/live/dm_live/file_autocomplete.ex` | New helper: `list_entries/3`, `under_root?/2` |
