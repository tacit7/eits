# Debugging: Vite + LiveView "Cannot bind multiple views"

Quick reference for future agents debugging LiveView errors in the Vite-built EITS app.

## The Error

```
Error: Cannot bind multiple views to the same DOM element.
```

LiveView hooks don't mount. Message bodies render as empty divs (the `MarkdownMessage` hook never fires).

## Root Cause Pattern

The app module (`app.js`) loads and executes **more than once**. ES modules cache by full URL, so `app.js?vsn=d` and `app.js` (no query string) are treated as separate modules. Each execution calls `liveSocket.connect()`, which calls `joinRootViews()`, which tries to bind a view to the same DOM element.

## How to Diagnose

### Step 1: Check resource loads

Open Chrome DevTools console and run:

```js
performance.getEntriesByType('resource')
  .filter(e => e.name.includes('app-'))
  .map(e => e.name + ' | ' + e.initiatorType)
```

If you see the same JS file loaded with different URLs (e.g., with and without `?vsn=d`), that's the double load.

### Step 2: Check script tags in HTML

```js
document.querySelectorAll('script[src*="app"]').length
```

Should be 1. If 2+, check for duplicate root layout rendering.

### Step 3: Check the Vite manifest for circular imports

```python
import json
m = json.load(open('priv/static/.vite/manifest.json'))
for k, v in m.items():
    imports = v.get('imports', [])
    if 'js/app.js' in imports:
        print(f'CIRCULAR: {k} statically imports js/app.js')
```

If any chunk statically imports `js/app.js`, Vite code splitting created a circular dependency.

### Step 4: Set a breakpoint

In Chrome DevTools Sources tab, find the app JS file, search for "Cannot bind multiple views", set a breakpoint. Reload. Check the Call Stack to see what triggered the second `connect()`.

## Known Causes

### 1. Vite code splitting circular imports

Vite's Rollup bundler may put shared code in the app entry chunk. When a lazy-loaded chunk (e.g., highlight.js) statically imports the app entry, the app executes again.

**Fix**: Use `inlineDynamicImports: true` in `vite.config.mjs` to disable code splitting:

```js
build: {
  rollupOptions: {
    output: { inlineDynamicImports: true },
  },
}
```

Tradeoff: larger single bundle (~3.7MB) but no circular imports.

**Better fix (when phoenix_vite is fixed)**: Use `manualChunks` to put `node_modules` in a vendor chunk. But phoenix_vite currently renders imported chunks as `<script type="module">` tags instead of `<link rel="modulepreload">`, which causes them to execute independently.

### 2. phoenix_vite renders imported chunks as scripts

`PhoenixVite.Components.assets` calls `reference_for_file` for imported chunks with `rel="modulepreload"`. But `reference_for_file` renders `.js` files as `<script>` tags, ignoring the `rel` attribute. This causes chunks to execute as standalone modules.

**Status**: Upstream phoenix_vite bug. Monitor https://hex.pm/packages/phoenix_vite for fixes.

### 3. Double root layout rendering

If a LiveView explicitly sets `layout: {MyAppWeb.Layouts, :root}` in its `mount/3` return, Phoenix wraps it in the root layout **again**. This produces nested `<html>` documents with duplicate script tags.

**Fix**: Remove explicit `layout:` from LiveView mount. Phoenix applies the root layout automatically.

**Check**: `curl -s http://localhost:5001/page | grep -c '<html'` — should be 1.

### 4. UMD vendor files in ESM context

Files in `assets/vendor/` using UMD wrappers (like topbar.js) break in Vite's ESM bundling. `this` is `undefined` in ES modules, so `this.topbar = topbar` fails.

**Fix**: Install from npm instead: `cd assets && npm install topbar`. Change import from `"../vendor/topbar"` to `"topbar"`.

## Verification Checklist

After fixing, verify all of these:

```bash
# 1. Manifest has no circular imports
python3 -c "
import json; m = json.load(open('priv/static/.vite/manifest.json'))
for k,v in m.items():
  if 'js/app.js' in v.get('imports',[]): print(f'CIRCULAR: {k}')
print('OK' if not any('js/app.js' in v.get('imports',[]) for v in m.values()) else 'FAIL')
"

# 2. Only one script tag for app.js in HTML
curl -s http://localhost:5001/auth/login | grep -c 'script.*src.*app'
# Expected: 1

# 3. Only one <html> tag
curl -s http://localhost:5001/auth/login | grep -c '<html'
# Expected: 1

# 4. In browser: only one resource load for app JS
# Run in console: performance.getEntriesByType('resource').filter(e => e.name.includes('app-')).length
# Expected: 1
```

## Related Files

- `assets/vite.config.mjs` — build config, inlineDynamicImports setting
- `assets/js/app.js` — liveSocket.connect() call, topbar import
- `lib/eye_in_the_sky_web/components/layouts/root.html.heex` — PhoenixVite.Components.assets
- `lib/eye_in_the_sky_web/live/auth_live.ex` — layout setting (removed)
- `deps/phoenix_vite/lib/phoenix_vite/components.ex` — reference_for_file bug
