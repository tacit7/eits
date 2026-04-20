# Channel Chat — Discord-style Refresh

**Date:** 2026-04-20
**Scope:** `AgentMessagesPanel.svelte` only — frontend-only, no backend changes.

---

## Goal

Make the channel chat feel like a polished messaging app (Slack/Discord) rather than a log viewer. Three targeted changes: message grouping, better input bar, and collapsed token metadata.

---

## 1. Message Grouping

Messages are visually grouped when consecutive messages come from the same sender in a short window. Only the first message in a group shows the full header (avatar + name + timestamp). Subsequent messages show body only, indented to align with the first message's text column.

### Grouping Identity

Define a normalized sender key:
- User messages: `"user"`
- Agent/session messages: `"session:${session_id}"`
- Other senders: fallback to `sender_role`

Messages group only when **all** of the following are true:
- Neither message is a system message
- Sender keys match
- Messages are on the same calendar date
- Time gap is ≤ 5 minutes
- Both timestamps are valid

### Implementation

Derive a view model before rendering:

```ts
$: renderedMessages = messages.map((message, index) => ({
  message,
  grouped: isGrouped(message, messages[index - 1]),
  startsNewDate: isNewDate(message, messages[index - 1])
}))
```

Grouping helper (uses `inserted_at` — the actual field in this component):

```ts
const GROUP_WINDOW_MS = 5 * 60 * 1000

function isSystemMessage(m) {
  return m.sender_role === 'system'
}

function senderKey(m) {
  if (!m) return null
  if (m.sender_role === 'user') return 'user'
  if (m.session_id) return `session:${m.session_id}`
  return m.sender_role ?? null
}

function sameCalendarDay(a, b) {
  const da = new Date(a), db = new Date(b)
  return da.getFullYear() === db.getFullYear()
    && da.getMonth() === db.getMonth()
    && da.getDate() === db.getDate()
}

function isGrouped(message, prev) {
  if (!message || !prev) return false
  if (isSystemMessage(message) || isSystemMessage(prev)) return false
  const key = senderKey(message), prevKey = senderKey(prev)
  if (!key || key !== prevKey) return false
  if (!sameCalendarDay(message.inserted_at, prev.inserted_at)) return false
  const t = new Date(message.inserted_at).getTime()
  const pt = new Date(prev.inserted_at).getTime()
  if (Number.isNaN(t) || Number.isNaN(pt)) return false
  return t - pt <= GROUP_WINDOW_MS
}
```

### Hover behavior

On hover of a grouped (no-header) message, show a muted timestamp right-aligned on that message row. Implemented via `opacity-0 group-hover:opacity-100` — no layout shift.

### Group break conditions (summary)

- Different normalized sender key
- > 5 minutes since last message from that sender
- System message (current or previous)
- Different calendar date / date separator
- Missing or invalid timestamps

---

## 2. Input Bar (Textarea)

Replace the current single-line `<input>` with an auto-growing `<textarea>`.

### Sizing

- Min height: ~40px (1 line). Max height: 144px (~6 lines).
- Auto-grows using `scrollHeight`:

```ts
function resizeTextarea(node) {
  node.style.height = 'auto'
  node.style.height = `${Math.min(node.scrollHeight, 144)}px`
}
```

Run on: input event, after submit clear, on mount. Set `overflow-y: auto` once max height is reached.

### Interaction Rules

Priority order (strict):

1. If autocomplete is open and has an active item, `Enter` selects the active suggestion.
2. If autocomplete is closed, `Enter` submits the message.
3. `Shift+Enter` always inserts a newline.
4. `Escape` closes autocomplete.
5. Arrow keys navigate autocomplete while open.
6. `Enter` does **not** submit while `event.isComposing` is true (IME input in progress).

Submit behavior:

```ts
if (event.key === 'Enter' && !event.shiftKey && !event.isComposing) {
  event.preventDefault()
  submit()
}
```

After submit: clear value, reset to one-line height, keep focus.

Empty or whitespace-only messages do not submit.

### Autocomplete Compatibility

Existing `@` mention and `/` slash autocomplete logic stays intact — only the element type changes from `<input>` to `<textarea>`. Cursor position handling for autocomplete insertion must be verified to work with multiline text.

---

## 3. Token Metadata (Collapsed, Per-Message)

Token metadata (`$cost`, `N in`, `N out`, `N turns`) remains **per message** — no aggregation.

- **Default:** hidden (`opacity-0`).
- **On hover:** visible at low opacity (`opacity-100`, `text-base-content/20`, `text-[10px]`).
- **First message in a group:** metadata appears in the header row on hover, right-aligned.
- **Grouped child messages:** metadata appears right-aligned on that message's own row on hover.
- **No layout shift:** keep metadata mounted in the DOM, toggle opacity only. Use `absolute` positioning or reserved space.

Example pattern:
```html
<div class="absolute right-0 top-0 opacity-0 group-hover:opacity-100 transition-opacity">
  <!-- token pills -->
</div>
```

---

## 4. Mobile / Touch Behavior

Desktop-first for this pass. Hover-only timestamp and metadata behavior is **out of scope for mobile/touch**. The existing component has no touch fallback and this refresh does not add one.

---

## 5. What Doesn't Change

- Avatar size and type (provider icon / user dot)
- Delete button on hover
- Date separators (still rendered; also force group breaks)
- System message rendering (standalone, never grouped)
- All PubSub / LiveView event handling
- `@all`, `@mention`, `/slash` autocomplete behavior

---

## 6. Files Touched

- `assets/svelte/components/tabs/AgentMessagesPanel.svelte` — all changes land here.

---

## 7. Success Criteria

- Consecutive messages from the same sender show no repeated header.
- Messages sent across midnight do not group across the date separator.
- System messages always render standalone.
- Input textarea auto-grows; `Enter` submits, `Shift+Enter` newlines.
- Enter does not submit during IME composition.
- Autocomplete `Enter` selection fires before submit logic.
- Autocomplete opens correctly after multiline text (cursor position preserved).
- Token pills invisible by default; appear faintly on hover per-message.
- No layout shift when token metadata becomes visible.
- Messages with missing/invalid timestamps do not group.
- Code blocks remain readable inside grouped messages.
- Long messages maintain text-column indentation alignment.
