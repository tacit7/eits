# EITS Settings Redesign — Design Spec

**Date:** 2026-03-15
**Status:** Draft

## Overview

Redesign the settings page (`/settings`) from a flat vertical-section layout to a tabbed layout with six distinct tabs. Simultaneously fix the broken settings page, add CodeMirror 6 as a site-wide file editor, surface env-var credential status in the UI, and add an `EITS_WORKFLOW` toggle.

---

## Section 1: Settings Page Architecture

### Tab Layout

The existing flat-section settings page is replaced with a tab-based layout. Tab state is driven by a socket assign (`active_tab`) defaulting to `:general`. Switching tabs uses `phx-click="set_tab"` with `push_patch` so the active tab is reflected in the URL as a query param (`/settings?tab=editor`), making tabs bookmarkable.

| Tab | Key | Contents |
|-----|-----|----------|
| General | `:general` | Default model, CLI timeout, TTS voice/rate |
| Editor | `:editor` | Preferred editor selection, CodeMirror info |
| Auth & Keys | `:auth` | Env-var status display, EITS key regenerate |
| Workflow | `:workflow` | EITS_WORKFLOW enable/disable toggle |
| Pricing | `:pricing` | Token pricing table (unchanged) |
| System | `:system` | Debug logging, DB info (unchanged) |

### Tab Routing

`mount/3` initializes `active_tab: :general` before `handle_params/3` runs, so the first render always has this assign. `handle_params/3` then reads the query param and updates it:

```elixir
@valid_tabs ~w(general editor auth workflow pricing system)

def mount(_params, _session, socket) do
  # ... existing mount logic ...
  socket = assign(socket, :active_tab, :general)
  {:ok, socket}
end

def handle_params(%{"tab" => tab}, _uri, socket) do
  active = if tab in @valid_tabs, do: String.to_atom(tab), else: :general
  {:noreply, assign(socket, :active_tab, active)}
end

def handle_params(_params, _uri, socket) do
  {:noreply, assign(socket, :active_tab, :general)}
end
```

`phx-click="set_tab"` events call `push_patch(socket, to: ~p"/settings?tab=#{tab}")`. The route is mounted as `:index` action with no `:show` variant. Tab value is validated against `@valid_tabs` before `String.to_atom/1` — unknown values fall back to `:general`.

### Storage

No new DB tables or schemas. All new settings use the existing `meta` key-value table via the `Settings` context (`settings.<key>` prefix). New keys added to `@defaults` in `settings.ex`.

### Breaking Fix

The settings page has a known runtime crash. Fix it as a standalone pre-task before adding tabs. No design decisions required — this is a standard bug investigation and fix.

---

## Section 2: Editor Integration

### Preferred Editor Setting

New setting key: `preferred_editor`, default: `"code"`.

Options in the Editor tab UI:
- VS Code (`code`)
- Cursor (`cursor`)
- vim (`vim`)
- nano (`nano`)
- Custom (free-text input for any arbitrary command)

**Security note on custom editor:** `System.cmd/3` takes the executable as a binary and args as a separate list, so shell injection via the file path argument is not a concern. A custom `preferred_editor` value is executed as a system command with no sandboxing. This is an intentional power-user feature — EITS is a local dev tool.

Stored as a string in the `meta` table like all other settings.

### Opening Files in External Editor

**Browser UI:** File open is triggered via a LiveView event (`phx-click="open_in_editor" phx-value-path={path}`), handled by `handle_event("open_in_editor", %{"path" => path}, socket)` in the LiveView. The handler fires a background task:

```elixir
def handle_event("open_in_editor", %{"path" => path}, socket) when byte_size(path) > 0 do
  editor = Settings.get("preferred_editor")
  Task.start(fn -> System.cmd(editor, [path], stderr_to_stdout: true) end)
  {:noreply, put_flash(socket, :info, "Opening in #{editor}...")}
end
```

**REST endpoint** (for external/CLI callers): `POST /api/v1/editor/open`

**Router pipeline:** Uses the existing authenticated `:api` pipeline (Bearer token required). This endpoint is for external callers. Browser UI uses the LiveView event path above.

**Request:**
```
POST /api/v1/editor/open
Authorization: Bearer <EITS_API_KEY>
Content-Type: application/json

{ "path": "/absolute/path/to/file" }
```

**Response (200 OK):**
```json
{ "ok": true }
```

**Response (422) — missing path:**
```json
{ "error": "path is required" }
```

**Response (500) — command failed:**
```json
{ "error": "editor command failed" }
```

### CodeMirror 6

**npm packages** added to `assets/package.json`:

```
codemirror
@codemirror/lang-javascript
@codemirror/lang-css
@codemirror/lang-html
@codemirror/lang-markdown
@codemirror/legacy-modes
@codemirror/language
@codemirror/theme-one-dark
codemirror-lang-elixir
```

Note:
- `codemirror-lang-elixir` is a community package (not `@codemirror/` scope) — used for `.ex`/`.exs` files
- Shell/bash highlighting uses `@codemirror/legacy-modes` with the `StreamLanguage` adapter from `@codemirror/language`: `StreamLanguage.define(shell)` where `shell` is imported from `@codemirror/legacy-modes/src/shell`
- File extensions not covered by any package fall back to plain text mode

**esbuild:** No build config changes required.

**JS Hook (`CodeMirrorHook`)** registered in `assets/js/app.js`:

1. Reads initial content from `data-content` attribute (base64-encoded)
2. Decodes via `atob(el.dataset.content)` in JS
3. Infers language from `data-lang` attribute
4. Initializes CodeMirror with decoded content and language extension
5. On save (`Cmd+S` / `Ctrl+S`): calls `this.pushEvent("file_changed", {content: view.state.doc.toString()})`

**Initial load flow:**

1. LiveView reads file using `File.read/1` (not the bang variant) on mount
2. On `{:ok, content}`: assigns `file_content: Base.encode64(content)` and `file_lang: infer_lang(path)`
3. On `{:error, reason}`: assigns `file_error: inspect(reason)` and renders an error state instead of the editor
4. Renders `<div phx-hook="CodeMirror" data-content={@file_content} data-lang={@file_lang}>`
5. JS hook decodes and initializes

**Save flow:**

1. User presses `Cmd+S` / `Ctrl+S`
2. Hook calls `this.pushEvent("file_changed", {content: ...})`
3. LiveView `handle_event("file_changed", %{"content" => content}, socket)` writes to `socket.assigns.edit_path`
4. `File.write/2` used (not bang) — error surfaced as flash if write fails

**Path security:** The file path is set server-side at mount time and stored as `edit_path` in the socket. The client sends only content, never the path. No path traversal risk from client input.

### `FileEditorComponent`

A function component (not a live component) that renders the hook `<div>` with the correct data attributes. LiveView hooks are owned by the parent LiveView; `pushEvent` targets the parent's `handle_event/3` directly. The component is a rendering helper only.

**Required assigns:**

| Assign | Type | Required | Description |
|--------|------|----------|-------------|
| `file_content` | `string` (base64) | yes | File content, `Base.encode64`-encoded |
| `file_lang` | `string` | yes | Language identifier for CodeMirror (`"elixir"`, `"javascript"`, `"shell"`, `"text"`, etc.) |
| `file_error` | `string \| nil` | no | If set, renders an error state instead of the editor |

The parent LiveView must set `edit_path` in its own socket assigns before rendering this component. The component does not receive or render the path — path is used only in the parent's `handle_event`.

CodeMirror is available site-wide. Config browser pages (`/config`, `/projects/:id/config`) use `FileEditorComponent` for in-browser editing. The Editor tab in Settings only configures `preferred_editor`.

---

## Section 3: Auth & API Keys

The Auth tab is a read-only status panel — no credentials are stored in the DB.

### Anthropic API Key

Displays status of `ANTHROPIC_API_KEY` environment variable:
- If set: `Set (****abcd)` — last 4 chars revealed
- If not set: `Not configured` — note: "Add `ANTHROPIC_API_KEY=<value>` to your `.env` file and restart the server."

No editing, no DB storage.

### EITS REST API Key

Same masking pattern for `EITS_API_KEY`.

Includes a "Regenerate" button that:
1. Generates: `:crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)`
2. Assigns as ephemeral socket assign `generated_api_key`
3. Replaces the masked status display with the generated key in a copy-ready input and notice: "Copy this key now — it will not be shown again. Add it to `.env` as `EITS_API_KEY=<value>` and restart the server."
4. Shows a `Pending restart` badge in place of the normal env-var status while `generated_api_key` is set in the socket
5. Does not store the key in DB

**Ephemeral state:** Key lives only in the socket assign. Navigating away or reconnecting clears it permanently. The UI makes this explicit. After restart, the normal masked status reflects the new active key.

### OAuth Token

Out of scope.

---

## Section 4: Workflow

### EITS_WORKFLOW Toggle

New setting key: `eits_workflow_enabled`, default: `"true"` (stored as string; read via `Settings.get_boolean/1`).

Displayed as a toggle in the Workflow tab: "Enable EITS hook workflow."

**Convention mapping:**
- `EITS_WORKFLOW=1` (env var) == `enabled: true` (REST API) == enabled
- `EITS_WORKFLOW=0` (env var) == `enabled: false` (REST API) == disabled
- DB setting `eits_workflow_enabled=true` == `enabled: true` (REST API) == enabled

**Precedence:** Env var takes priority. If `EITS_WORKFLOW` is set, it is used directly. If not set, the hook scripts fall back to the REST API.

**New unauthenticated endpoint for hook scripts:**

```
GET /api/v1/settings/eits_workflow_enabled
```

**Router pipeline:** Added to an open (unauthenticated) route group. Hook scripts run locally and do not carry Bearer tokens.

**Response (200 OK):**
```json
{ "enabled": true }
```

**Bash fallback pattern** used in all hook scripts:

```bash
EITS_WORKFLOW="${EITS_WORKFLOW:-}"
if [ -z "$EITS_WORKFLOW" ]; then
  ENABLED=$(curl -sf "${EITS_URL}/settings/eits_workflow_enabled" | jq -r '.enabled')
  [ "$ENABLED" = "false" ] && exit 0
elif [ "$EITS_WORKFLOW" = "0" ]; then
  exit 0
fi
```

**All 11 hook scripts receive this pattern** (replacing any existing `EITS_WORKFLOW` guard or adding where missing, so all scripts have identical, consistent workflow-check behavior):

- `eits-pre-tool-use.sh`
- `eits-post-tool-use.sh`
- `eits-pre-compact.sh`
- `eits-post-commit.sh`
- `eits-session-compact.sh`
- `eits-session-end.sh`
- `eits-session-resume.sh`
- `eits-session-stop.sh`
- `eits-session-startup.sh`
- `eits-prompt-submit.sh`
- `eits-agent-working.sh`

---

## Architecture Summary

### New Settings Keys

| Key | Storage | Default | Description |
|-----|---------|---------|-------------|
| `preferred_editor` | string | `"code"` | External editor command |
| `eits_workflow_enabled` | string `"true"`/`"false"` | `"true"` | Hook workflow on/off; read via `get_boolean/1` |

### New Files

| File | Purpose |
|------|---------|
| `assets/js/hooks/codemirror.js` | CodeMirror 6 LiveView hook |
| `lib/eye_in_the_sky_web_web/components/file_editor_component.ex` | `FileEditorComponent` function component |
| `lib/eye_in_the_sky_web_web/controllers/api/editor_controller.ex` | `POST /api/v1/editor/open` (external/CLI callers) |

### Modified Files

| File | Change |
|------|--------|
| `lib/eye_in_the_sky_web_web/live/overview_live/settings.ex` | Tabbed layout, `handle_params/3`, `mount/3` update, new event handlers, breaking bug fix |
| `lib/eye_in_the_sky_web/settings.ex` | Add `preferred_editor`, `eits_workflow_enabled` to `@defaults` |
| `lib/eye_in_the_sky_web_web/router.ex` | `POST /api/v1/editor/open` (auth pipeline); `GET /api/v1/settings/eits_workflow_enabled` (open pipeline) |
| `lib/eye_in_the_sky_web_web/controllers/api/` | New settings controller action for workflow endpoint |
| `assets/package.json` | Add CodeMirror 6 packages |
| `assets/js/app.js` | Register `CodeMirrorHook` |
| `priv/scripts/*.sh` | Replace existing guards and add where missing — all 11 scripts get unified bash fallback pattern |

### Out of Scope

- Encryption of values in the `meta` table
- OAuth token management
- WebAuthn or auth method changes
- Workflow state (kanban) configuration
- Mix task invocation from the UI
