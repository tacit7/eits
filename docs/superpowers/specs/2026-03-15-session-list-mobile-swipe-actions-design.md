# Session List Mobile Swipe Actions — Design Spec

**Date:** 2026-03-15
**Status:** Approved

## Problem

The session list pages (`/` and `/projects/:id/sessions`) have no mobile-friendly way to perform common row-level actions. On desktop, action buttons are revealed on hover. On mobile, hover doesn't exist, so these actions are inaccessible or buried.

The three actions users need on mobile: favorite a session, rename it, and archive it.

## Solution

Swipe-left gesture on session rows reveals a compact action panel. Behavior validated via interactive mockup — **Option B selected**: 53px-wide buttons, 160px total reveal.

## Gesture Behavior

- Swipe left ≥35% of 160px (56px) → snaps open
- Swipe right ≥35% while open → snaps closed
- Release below threshold → snaps back to previous state (open or closed)
- Tap while row is open → closes, does NOT navigate
- Tap while row is closed → navigates to DM page (normal `phx-click` fires)
- Opening one row auto-closes any other open row
- Tap outside any open row → closes it

Gesture detection distinguishes tap from swipe by tracking horizontal delta. If `|dx| < 10px && |dy| < 10px && duration < 300ms` → tap. If `|dx| > 8px && |dx| > |dy|` during `touchmove` → swipe. This prevents false triggers on vertical scroll.

## Action Panel

Three buttons, left-to-right, each 53px wide:

| Button | Color | Action | Event |
|--------|-------|--------|-------|
| Fav | Rose `#f43f5e` | Bookmark session | Uses existing `BookmarkAgent` hook |
| Rename | Indigo `#6366f1` | Edit session name inline | New `rename_session` event |
| Archive | Amber `#f59e0b` | Archive session | Existing `archive_session` event |

## Rename Flow

1. Tap Rename → fires `phx-click="rename_session"` with `session_id`
2. LiveView sets `editing_session_id` assign
3. Session row re-renders with `<input>` replacing the name text, pre-filled with current name, auto-focused
4. Submit on Enter → fires `save_session_name` via `phx-submit` on the input's wrapping form. Blur also triggers a save via `phx-blur` on the input, unless a swipe-close is in progress. To avoid a race condition between blur firing synchronously and the hook setting state, the `SwipeRow` hook uses an in-memory JS flag (`this.isClosing = true`) set before it begins the close animation. The inline input's `phx-blur` handler checks this flag via a `data-swipe-target` reference to the hook element — if `isClosing` is true, blur is treated as a cancel, not a save.
5. ESC → fires `cancel_rename`, reverts to display mode
6. Backend: `Sessions.update_session_name(session, name)` — adds this function if not present

## Components Affected

### `assets/js/hooks/swipe_row.js` (new)

`SwipeRow` Phoenix hook. Attached via `phx-hook="SwipeRow"` on each row wrapper. Manages touch state, applies `translateX` transforms, snaps open/closed, coordinates single-open-row invariant across all instances on the page.

Uses the existing `createSwipeDetector` and `TOUCH_DEVICE` utilities from `assets/js/hooks/touch_gesture.js`. Only activates when `TOUCH_DEVICE` is true — no-ops on desktop.

The hook must:
- Store `maxReveal = 160` (px)
- Track `startX`, `startY`, `startTime`, `dragging`, `isOpen` per instance
- Remove CSS transition during active drag, restore on `touchend`
- Emit a custom DOM event `swiperow:open` when opening so other instances can close themselves
- Set `data-closing` attribute during close animation so the inline rename input's blur handler can detect a swipe-close and skip saving
- Handle `phx-update="stream"` — LiveView may patch rows; hook must re-attach on `mounted` and `updated`

### `lib/eye_in_the_sky_web_web/components/session_card.ex`

Both `session_live/index.ex` and `project_live/sessions.ex` render rows via the shared `session_row/1` component in this file — confirmed by reading the source. All swipe UI changes go here.

- Wrap row content in a `relative overflow-hidden` container
- Add action panel div (absolutely positioned, right edge) with three buttons — hidden on `md+` via `md:hidden` to avoid visual noise on desktop where hover-reveal buttons already exist
- Add `phx-hook="SwipeRow"` to the outer wrapper
- Accept new `editing_session_id` attr; when `@editing_session_id == @session.id`, render `<input>` instead of the name `<span>`
- Action buttons fire `phx-click` events with `phx-value-session-id`

### `lib/eye_in_the_sky_web_web/live/session_live/index.ex`

- Add `assign(:editing_session_id, nil)`
- Add handlers: `rename_session`, `save_session_name`, `cancel_rename`
- Add `archive_session` handler (currently missing from this page)
- Favorite: delegate to `BookmarkAgent` JS hook — no LiveView change needed

### `lib/eye_in_the_sky_web_web/live/project_live/sessions.ex`

- Add `assign(:editing_session_id, nil)`
- Add handlers: `rename_session`, `save_session_name`, `cancel_rename`
- `archive_session` already exists
- Favorite: already handled by `BookmarkAgent` hook

### `lib/eye_in_the_sky_web/sessions.ex`

- Add `update_session_name(session, name)` if not already present

## CSS / Tailwind

Row wrapper needs: `relative overflow-hidden group`
Action panel: `absolute right-0 top-0 bottom-0 flex`
Action buttons: `w-[53px] flex flex-col items-center justify-center gap-1 text-white text-[9px] font-bold uppercase tracking-wide border-none`

The row content div gets `will-change: transform` and `transition: transform 0.25s cubic-bezier(0.25,0.46,0.45,0.94)` applied via JS (not CSS class) so the transition is removed during active drag.

## Out of Scope

- Desktop swipe (hook only activates on touch devices — check `'ontouchstart' in window`)
- Swipe-to-delete (destructive action requires confirmation; archive is safer)
- Swipe on DM page message rows

## Files to Create/Modify

```
assets/js/hooks/swipe_row.js              (new)
assets/js/app.js                          (register SwipeRow — import + Hooks.SwipeRow = SwipeRow)
lib/.../components/session_card.ex        (modify)
lib/.../live/session_live/index.ex        (modify)
lib/.../live/project_live/sessions.ex     (modify)
lib/.../sessions/sessions.ex              (modify — add update_session_name if missing)
```
