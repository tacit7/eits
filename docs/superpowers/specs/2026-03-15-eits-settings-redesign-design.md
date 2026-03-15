# EITS Settings Redesign — Design Spec

**Date:** 2026-03-15
**Status:** Approved

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

### Storage

No new DB tables or schemas. All new settings use the existing `meta` key-value table via the `Settings` context (`settings.<key>` prefix). New keys added to `@defaults` in `settings.ex`.

### Breaking Fix

Identify and fix the current runtime error causing the settings page to break before adding tabs. The flat layout is structurally sound in the code; the bug is likely a missing function clause or bad pattern match on nil — confirmed during implementation.

---

## Section 2: Editor Integration

### Preferred Editor Setting

New setting key: `preferred_editor`, default: `"code"`.

Options in the Editor tab UI:
- VS Code (`code`)
- Cursor (`cursor`)
- vim (`vim`)
- nano (`nano`)
- Custom (free-text input for any command)

Stored as a string in the `meta` table like all other settings.

### External Editor Shell-Out

New REST endpoint: `POST /api/v1/editor/open`

Request body:
```json
{ "path": "/absolute/path/to/file" }
```

The server reads `Settings.get("preferred_editor")` and runs `System.cmd(editor, [path])` detached. Since EITS runs locally, this opens the file in the user's local editor (e.g., `code /path/to/file` opens VS Code). File browser and config browser pages call this endpoint when the user clicks an "Edit" button.

### CodeMirror 6

Added as an npm package (`codemirror`, `@codemirror/lang-elixir`, `@codemirror/lang-javascript`, `@codemirror/lang-shell`, etc.) in `assets/package.json`. A Phoenix LiveView JS hook (`CodeMirrorHook`) initializes an editor on any `<div phx-hook="CodeMirror">`. Content syncs back via `pushEvent("file_changed", %{content: ...})` to the LiveView, which persists via `File.write/2`.

A reusable `FileEditorComponent` wraps the hook and handles:
- Language auto-detection from file extension
- Dirty state tracking (unsaved indicator)
- Save button (`Cmd+S` / `Ctrl+S` keybinding via CodeMirror)

CodeMirror is available site-wide — not scoped to the settings page. The config browser pages (`/config`, `/projects/:id/config`) use it to allow in-browser file editing as an alternative to opening externally.

The Editor tab in Settings only configures the `preferred_editor` preference. CodeMirror is always available regardless of this setting.

---

## Section 3: Auth & API Keys

The Auth tab is a read-only status panel — no credentials are stored in the DB.

### Anthropic API Key

Displays status of `ANTHROPIC_API_KEY` environment variable:
- If set: `Set (****abcd)` (last 4 chars of the key)
- If not set: `Not configured` with a note to add it to `.env`

No editing, no DB storage. Env var is the source of truth.

### EITS REST API Key

Displays status of `EITS_API_KEY` environment variable with the same masking pattern. Includes a "Regenerate" button that:
1. Runs `mix eits.gen.api_key` via `System.cmd`
2. Displays the generated key once in the UI for the user to copy to their `.env`
3. Does not store the key in DB

### OAuth Token

Dropped. Not needed.

---

## Section 4: Workflow

### EITS_WORKFLOW Toggle

New setting key: `eits_workflow_enabled`, default: `"true"`.

Displayed as a toggle in the Workflow tab with description: "Enable EITS hook workflow (pre-tool-use, post-commit, session-start, etc.)."

**Precedence:** The `EITS_WORKFLOW` env var takes priority if set. Hook scripts check env var first, then fall back to the REST API (`GET /api/v1/settings/eits_workflow_enabled`). This preserves backward compatibility — existing env-var-based toggles continue working.

---

## Architecture Summary

### New Settings Keys

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `preferred_editor` | string | `"code"` | External editor command |
| `eits_workflow_enabled` | boolean | `"true"` | Hook workflow on/off |

### New Files

| File | Purpose |
|------|---------|
| `assets/js/hooks/codemirror.js` | CodeMirror 6 LiveView hook |
| `lib/eye_in_the_sky_web_web/components/file_editor_component.ex` | Reusable file editor component |

### Modified Files

| File | Change |
|------|--------|
| `lib/eye_in_the_sky_web_web/live/overview_live/settings.ex` | Tabbed layout, new event handlers, bug fix |
| `lib/eye_in_the_sky_web/settings.ex` | Add new keys to `@defaults` |
| `lib/eye_in_the_sky_web_web/router.ex` | Add `POST /api/v1/editor/open` route |
| `lib/eye_in_the_sky_web_web/controllers/api/` | New `EditorController` |
| `assets/package.json` | Add CodeMirror 6 packages |
| `assets/js/app.js` | Register CodeMirrorHook |
| `priv/scripts/*.sh` | Add DB-backed workflow check fallback |

### Out of Scope

- Encryption of values in the `meta` table
- OAuth token management
- WebAuthn or auth method changes
- Workflow state (kanban) configuration
