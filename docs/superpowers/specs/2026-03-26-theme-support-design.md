# Theme Support Design

**Date:** 2026-03-26
**Status:** Approved

## Overview

Add a theme picker to the Settings page (General tab, Appearance section). Themes are stored in both the `Settings` DB (server-authoritative) and `localStorage` (instant apply, no flash). Available themes are the existing custom `dark` and `light` plus four Catppuccin flavors via `@catppuccin/daisyui`.

## Architecture

### Theme storage

| Location | Key | Default |
|----------|-----|---------|
| `Settings` DB (`meta` table) | `"theme"` | `"dark"` |
| Browser `localStorage` | `"theme"` | — |

DB is the fallback when localStorage is absent (new device, cleared storage). Both are written on every change.

### Available themes

| Value | Label | Type |
|-------|-------|------|
| `dark` | Dark | Custom (Claude.ai palette) |
| `light` | Light | Custom (Pampas palette) |
| `catppuccin-latte` | Latte | Catppuccin (light) |
| `catppuccin-frappe` | Frappé | Catppuccin (mid-dark) |
| `catppuccin-macchiato` | Macchiato | Catppuccin (dark) |
| `catppuccin-mocha` | Mocha | Catppuccin (darkest) |

Existing `[data-theme="dark"]` and `[data-theme="light"]` CSS overrides are untouched. Catppuccin themes use their own DaisyUI palette.

### Theme application flow

1. **Server render:** `root.html.heex` sets `data-theme` on `<html>` from `Settings.get("theme") || "dark"` — correct theme before JS runs, no flash on first load.
2. **Client init:** Inline script in `<head>` checks `localStorage.getItem("theme")`. If found, overrides `data-theme` immediately. If absent, keeps the server-rendered value.
3. **On change:** Settings LiveView `save_setting` event saves to DB, then calls `push_event("apply_theme", %{theme: value})`. A JS hook listener in `app.js` updates `document.documentElement.setAttribute("data-theme", theme)` and `localStorage.setItem("theme", theme)`.

## Components

### `assets/package.json`
Add `"@catppuccin/daisyui"` to `devDependencies`.

### `assets/css/app.css`
After the existing `@plugin "daisyui"` block, add:
```css
@plugin "@catppuccin/daisyui";
```

### `lib/eye_in_the_sky/settings.ex`
Add to `@defaults`:
```elixir
"theme" => "dark"
```

### `lib/eye_in_the_sky_web/components/layouts/root.html.heex`
- Change `<html lang="en">` to `<html lang="en" data-theme={EyeInTheSky.Settings.get("theme") || "dark"}>`
- Update inline `<script>` to only override if localStorage has a value:
  ```js
  const saved = localStorage.getItem("theme");
  if (saved) document.documentElement.setAttribute("data-theme", saved);
  ```

### `lib/eye_in_the_sky_web/live/overview_live/settings.ex`
- Add `@themes` list constant
- Add Appearance section at the top of the General tab render with a theme picker (select or visual swatches)
- In `handle_event("save_setting", ...)`: after saving, push a client event when key is `"theme"`:
  ```elixir
  |> push_event("apply_theme", %{theme: value})
  ```

### `assets/js/app.js`
Add event listener:
```js
window.addEventListener("phx:apply_theme", ({ detail }) => {
  document.documentElement.setAttribute("data-theme", detail.theme);
  localStorage.setItem("theme", detail.theme);
});
```

## Error handling

- `Settings.get("theme")` already falls back to `@defaults` if DB is unavailable — no additional handling needed.
- Invalid theme values are benign: DaisyUI silently falls back to its default.

## Testing

- Navigate to Settings > General, change theme — verify `data-theme` on `<html>` updates immediately.
- Reload page — verify theme persists (from localStorage and server render).
- Clear localStorage, reload — verify DB value is used.
- Verify all 6 theme names render visually distinct UI.
