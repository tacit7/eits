# Channel Chat — Discord-style Refresh

**Date:** 2026-04-20
**Scope:** `AgentMessagesPanel.svelte` only — frontend-only, no backend changes.

---

## Goal

Make the channel chat feel like a polished messaging app (Slack/Discord) rather than a log viewer. Three targeted changes: message grouping, better input bar, and collapsed token metadata.

---

## Implementation Constraints

Do not modify `DmLive`, LiveView event names, PubSub behavior, message loading, schemas, or backend code. This is a Svelte component refresh only. All changes land in `assets/svelte/components/tabs/AgentMessagesPanel.svelte`.

---

## 1. Message Grouping

Messages are visually grouped when consecutive messages come from the same sender within a 5-minute window. Only the first message in a group shows the full header (avatar + name + timestamp). Subsequent messages show body only, indented to align with the first message's text column.

### Grouping Identity

Define a normalized sender key:
- User messages: `"user"`
- Agent/session messages: `"session:${session_id}"` — only when `session_id` is present
- Messages without a recognized identity (no `session_id`, not user): **not grouped** — return `null`

Agent/session messages require `session_id` to group. If `session_id` is missing, they render ungrouped.

Messages group only when **all** of the following are true:
- Neither message is a system message
- Both sender keys are non-null and match
- Messages are on the same calendar date
- Time delta is ≥ 0 and ≤ 5 minutes
- Both timestamps are valid

### View Model

Derive a view model before rendering:

```ts
$: renderedMessages = messages.map((message, index) => ({
  message,
  grouped: isGrouped(message, messages[index - 1]),
  startsNewDate: isNewDate(message, messages[index - 1])
}))
```

### Helper Functions

```ts
const GROUP_WINDOW_MS = 5 * 60 * 1000

function messageTime(message) {
  if (!message?.inserted_at) return null
  const time = new Date(message.inserted_at).getTime()
  return Number.isNaN(time) ? null : time
}

function isSystemMessage(message) {
  return message?.sender_role === 'system' || message?.type === 'system'
}

function senderKey(message) {
  if (!message || isSystemMessage(message)) return null
  if (message.sender_role === 'user') return 'user'
  if (message.session_id) return `session:${message.session_id}`
  return null
}

function sameCalendarDay(a, b) {
  const at = messageTime(a)
  const bt = messageTime(b)
  if (at === null || bt === null) return false
  const da = new Date(at), db = new Date(bt)
  return da.getFullYear() === db.getFullYear()
    && da.getMonth() === db.getMonth()
    && da.getDate() === db.getDate()
}

function isNewDate(message, prev) {
  if (!message) return false
  if (!prev) return true
  return !sameCalendarDay(message, prev)
}

function isGrouped(message, prev) {
  if (!message || !prev) return false
  if (isSystemMessage(message) || isSystemMessage(prev)) return false
  const key = senderKey(message)
  const prevKey = senderKey(prev)
  if (!key || key !== prevKey) return false
  if (!sameCalendarDay(message, prev)) return false
  const time = messageTime(message)
  const prevTime = messageTime(prev)
  if (time === null || prevTime === null) return false
  const delta = time - prevTime
  return delta >= 0 && delta <= GROUP_WINDOW_MS
}
```

Messages are assumed to render oldest-to-newest. Negative deltas fail the `delta >= 0` check and never group.

### Hover Behavior (Grouped Messages)

On hover of a grouped (no-header) message, show a muted timestamp right-aligned on that message row. Implemented via `opacity-0 group-hover:opacity-100` — no layout shift.

### Group Break Conditions (Summary)

- Different or null sender key
- > 5 minutes since last message from that sender, or negative delta
- System message (current or previous)
- Different calendar date / date separator
- Missing or invalid timestamps

---

## 2. Input Bar (Textarea)

Replace the current single-line `<input>` with an auto-growing `<textarea>`.

### Svelte Binding

```svelte
<textarea
  bind:this={textareaEl}
  bind:value={inputValue}
  on:input={() => resizeTextarea(textareaEl)}
  on:keydown={handleInputKeydown}
/>
```

### Sizing

Min height: ~40px (1 line). Max height: 144px (~6 lines). Auto-grows using `scrollHeight`:

```ts
function resizeTextarea(node) {
  if (!node) return
  node.style.height = 'auto'
  node.style.height = `${Math.min(node.scrollHeight, 144)}px`
}
```

Run on: input event, on mount. Set `overflow-y: auto` once max height is reached.

After submit, use Svelte's `tick()` to wait for DOM update before resizing:

```ts
import { tick } from 'svelte'

async function clearComposer() {
  inputValue = ''
  await tick()
  resizeTextarea(textareaEl)
  textareaEl?.focus()
}
```

### Interaction Rules (Priority Order)

1. If slash autocomplete is open and has an active item, `Enter` selects the active suggestion — delegate to existing `selectSlashItem`.
2. If `@` mention autocomplete is open and has an active item, `Enter` selects the active mention — delegate to existing `selectAutocomplete`.
3. If autocomplete is closed, `Enter` submits the message.
4. `Shift+Enter` always inserts a newline (do not intercept).
5. `Escape` closes autocomplete.
6. Arrow keys navigate autocomplete while open.
7. `Enter` does **not** submit while `event.isComposing` is true (IME input in progress).

Submit check:
```ts
if (event.key === 'Enter' && !event.shiftKey && !event.isComposing) {
  event.preventDefault()
  handleSubmit()
}
```

**Use the existing autocomplete state and selection handlers. Do not introduce a second autocomplete state machine.** The existing `showSlashAutocomplete`, `showAutocomplete`, `selectedSlashIndex`, `selectedAutocompleteIndex`, `selectSlashItem`, and `selectAutocomplete` variables and functions must be reused as-is. The only change is that the keydown handler now also guards against submit when autocomplete is open.

Empty or whitespace-only messages do not submit.

---

## 3. Token Metadata (Collapsed, Per-Message)

Token metadata (`$cost`, `N in`, `N out`, `N turns`) remains **per message** — no aggregation.

- **Default:** hidden (`opacity-0`).
- **On group hover:** visible at low opacity (`opacity-100`, `text-base-content/20`, `text-[10px]`).
- **First message in a group:** metadata appears in the header row on hover, right-aligned.
- **Grouped child messages:** metadata appears right-aligned on that message's own row on hover.
- **No layout shift:** keep metadata mounted in the DOM, toggle opacity only.

Any row or header using absolutely positioned metadata must have a `relative` parent container. Grouped child message rows must reserve enough right padding to prevent hover metadata from overlapping message text.

Example pattern:
```html
<div class="relative group ...">
  <!-- message content -->
  <div class="absolute right-0 top-0 opacity-0 group-hover:opacity-100 transition-opacity flex gap-1">
    <!-- token pills -->
  </div>
</div>
```

---

## 4. Streaming Behavior

Streaming/live response content must not be grouped with persisted messages unless it is already represented as a normal message object in `messages`. This refresh must not change existing stream rendering behavior.

---

## 5. Mobile / Touch Behavior

Desktop-first for this pass. Hover-only timestamp and metadata behavior is **out of scope for mobile/touch**. The existing component has no touch fallback and this refresh does not add one.

---

## 6. What Doesn't Change

- Avatar size and type (provider icon / user dot)
- Delete button on hover
- Date separators (still rendered; also force group breaks)
- System message rendering (standalone, never grouped)
- All PubSub / LiveView event handling
- Stream/live output rendering
- `@all`, `@mention`, `/slash` autocomplete state, handlers, and behavior

---

## 7. Success Criteria

- Consecutive messages from the same sender show no repeated header.
- Messages sent across midnight do not group across the date separator.
- System messages always render standalone.
- Agent messages without `session_id` render ungrouped.
- Input textarea auto-grows; `Enter` submits, `Shift+Enter` newlines.
- `Enter` does not submit during IME composition.
- Autocomplete `Enter` selection fires before submit logic.
- Autocomplete opens correctly after multiline text (cursor position preserved).
- `@` and `/` autocomplete behave identically to before.
- Token pills invisible by default; appear faintly on hover per-message.
- No layout shift when token metadata becomes visible.
- Messages with missing/invalid timestamps do not group.
- Negative time deltas never produce a grouped message.
- Streaming output rendering is unchanged.
- Code blocks remain readable inside grouped messages.
- Long messages maintain text-column indentation alignment.
