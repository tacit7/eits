# Channel Chat — Discord-style Refresh

**Date:** 2026-04-20
**Scope:** `AgentMessagesPanel.svelte` only — frontend-only, no backend changes.

---

## Goal

Make the channel chat feel like a polished messaging app (Slack/Discord) rather than a log viewer. Three targeted changes: message grouping, better input bar, and collapsed token metadata.

---

## 1. Message Grouping

**Rule:** Consecutive messages from the same `session_id` (or same `sender_role` for user messages) sent within 5 minutes of each other are grouped. Only the first message in a group shows the full header (avatar + name + timestamp). Subsequent messages in the group show body only, indented to align with the first message's text column.

**Hover behavior:** A muted timestamp appears inline on the right edge of each grouped message on hover, so the time is still accessible without cluttering every line.

**Group break conditions:**
- Different sender
- More than 5 minutes since last message from that sender
- A system message between two agent messages (system messages always render standalone)
- A date separator

**Implementation:** Add a `isGrouped(message, prevMessage)` helper that returns true when both conditions are met. Pass `isGrouped` as a derived boolean into the message render block.

---

## 2. Input Bar

Replace the current single-line `<input>` with a `<textarea>`:
- Min height: 1 line (~40px). Max height: ~6 lines (~144px). Auto-grows with content via `rows` or a resize observer.
- `Enter` submits. `Shift+Enter` inserts a newline.
- Existing `@` mention autocomplete and `/` slash autocomplete stay fully intact — only the element type changes.
- Styling: rounded border (`rounded-xl`), slightly more padding, matches the Discord composer look.

---

## 3. Token Metadata (Collapsed)

The cost/token pills (`$0.00xx`, `N in`, `N out`, `N turns`) currently render as a full row below every agent message. New behavior:
- Hidden by default.
- On message group hover, the pills appear inline on the far right of the header row, at very low opacity (`text-base-content/20`, `text-[10px]`).
- No dedicated row. No layout shift.

---

## 4. What Doesn't Change

- Avatar size and type (provider icon / user dot) — unchanged.
- Delete button on hover — unchanged.
- Date separators — unchanged.
- System message rendering — unchanged.
- All PubSub / LiveView event handling — no backend changes.
- `@all`, `@mention`, `/slash` autocomplete behavior — unchanged.

---

## Files Touched

- `assets/svelte/components/tabs/AgentMessagesPanel.svelte` — all changes land here.

---

## Success Criteria

- Consecutive messages from the same sender show no repeated header.
- Input textarea auto-grows; Enter submits, Shift+Enter newlines.
- Token pills are invisible by default, appear faintly on hover.
- Existing autocomplete (@ and /) still works correctly.
- No regressions on system messages or date separators.
