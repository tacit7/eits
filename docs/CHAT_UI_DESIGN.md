# Chat UI Design

Design reference for the EITS chat surface. Covers the channel chat page (`/chat`) and the DM session page (`/dm/:session_id`). These are distinct surfaces but share message rendering conventions.

Last reviewed: 2026-04-29.

---

## Surface Purpose

The chat surface is an **operational communication layer** for human-to-agent and agent-to-agent coordination. It is not a general-purpose messaging product.

Primary user jobs:
- Send instructions and commands to one or more agents in a channel
- Monitor agent activity and review agent outputs
- Search conversation history for specific decisions or outputs
- Start and follow threads on specific messages
- Add and remove agents from a channel

This surface behaves as a hybrid of **chat**, **technical discussion feed**, and **agent command interface**. Design decisions should optimize for that combination — not for social chat (Slack/Discord patterns), not for log viewers, not for email-style threads.

---

## Page Archetype

**Communication surface within an Operational Workspace.**

Consequences:
- The header carries live context (channel identity, active agent counts) — it does not navigate or filter
- The conversation body is the primary content and should dominate the vertical space
- The composer is an instruction input, not just a text field — it must handle multi-line, @mentions, and /commands
- The sidebar is navigation — lean, keyboard-accessible, minimal chrome
- Controls are discoverable on demand (hover, ⌘-shortcut), not persistent chrome

---

## Architecture Overview

```
/chat                              /dm/:session_id
───────────────────────────────    ───────────────────────────────
ChatLive (LiveView)                DmLive (LiveView)
  └─ AgentMessagesPanel.svelte       └─ DmPage component (HEEx)
       └─ ThreadPanel.svelte              └─ messages_tab.ex (HEEx)
                                               └─ dm_message_components.ex
```

`AgentMessagesPanel` is a Svelte component (`ssr={false}`). It owns message rendering, composer, @mention autocomplete, /slash autocomplete, inline search, and thread panel integration.

`dm_message_components.ex` is a HEEx component tree. It owns tool call widgets, thinking blocks, markdown (via `MarkdownMessage` JS hook), token metrics, and file attachments.

---

## Message Rendering Rules

### Text width

Always constrain agent and user message bodies:

```svelte
<!-- Channel chat (AgentMessagesPanel) -->
<div class="max-w-[720px]">...</div>

<!-- DM (messages_tab.ex) -->
<div class="max-w-[78%] flex flex-col">...</div>
```

Never render full-width text blocks. Line length above ~80 characters degrades readability for dense technical content.

### Markdown (agent messages)

Agent messages are parsed as Markdown. Pipeline:

```js
marked.setOptions({ gfm: true, breaks: true })
const html = marked.parse(body)
const clean = DOMPurify.sanitize(html, DOMPURIFY_CONFIG)
```

DOMPurify allowlist (do not expand without security review):

```js
ALLOWED_TAGS: ['p', 'strong', 'em', 'b', 'i', 'code', 'pre', 'ul', 'ol', 'li',
               'br', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'blockquote', 'a',
               'span', 'hr', 'del', 's']
ALLOWED_ATTR: ['class', 'href', 'target', 'rel']
```

`{@html}` injection is the only way to render parsed markdown in Svelte. DOMPurify is mandatory before injection. Do not bypass it.

### Markdown typography rules

Code within message bodies must be visually subordinate to prose. These rules apply to `.message-body`:

| Element | Treatment |
|---|---|
| `p` | `margin-bottom: 0.4em`; last-child removes margin |
| `ol` / `ul` | `padding-left: 1.4em`; `margin: 0.3em 0 0.5em` |
| `li` | `line-height: 1.55`; nested lists get `margin: 0.15em 0` |
| `code` (inline) | `font-size: 0.8em`; `bg: rgba(127,127,127,0.1)`; `border-radius: 3px` |
| `pre` | `font-size: 0.8em`; `overflow-x: auto`; `bg: rgba(127,127,127,0.07)` |
| `h1` / `h2` | `font-size: 1.05–1.1em`, `font-weight: 600` — not document headings |
| `h3–h6` | `font-weight: 600`, minimal size increase |
| `blockquote` | `border-left: 2px solid rgba(127,127,127,0.25)`; `opacity: 0.75` |

Heading sizes inside message bodies are deliberately restrained. Agent messages are not documents — headings should serve as section breaks, not page titles.

### User messages

User message bodies are escaped (no markdown) and rendered with `whitespace-pre-wrap`. @mentions are highlighted via regex after HTML escaping — not before, to prevent XSS.

```js
function renderBody(body) {
  const escaped = escapeHtml(body)
  return escaped.replace(/@(all|\d+)/g, (match, token) => {
    const label = token === 'all' ? '@all' : `@${token}`
    return `<span class="inline-flex items-center px-1 py-0.5 rounded text-xs font-mono font-semibold bg-primary/10 text-primary">${label}</span>`
  })
}
```

### System messages

System messages (e.g., "Agent joined the channel") are subordinate to all content:

```
border-l-2 border-base-content/[0.08] pl-3 italic text-[11px] text-base-content/25 py-1
```

No icon, no identity line. Hover reveals delete only.

---

## Message Row Structure

### Channel chat (`AgentMessagesPanel`)

```
[group row]  class="group px-2 -mx-2 rounded-lg transition-colors py-4"
  [icon 16px]  provider image or user SVG, mt-1 flex-shrink-0
  [identity row]  flex items-baseline gap-2
    [name]  text-[13px] font-semibold  (agent = clickable DM link)
    [timestamp]  text-[11px] text-base-content/25
    [#number]  text-[11px] text-base-content/[0.15], opacity-0 group-hover:opacity-100
    [hover actions]  opacity-0 group-hover:opacity-100 ml-auto
  [body wrapper]  max-w-[720px]
    [.message-body]  mt-1 text-sm leading-relaxed text-base-content/85
  [metadata row]  mt-2 flex flex-nowrap gap-x-1.5 (agent only, when cost present)
  [reactions]  mt-2 flex flex-wrap gap-1 (when present)
  [thread reply count]  mt-2 (when > 0)
```

### Agent message visual distinction

Agent messages carry a left border to distinguish them from user messages at a glance:

```
border-l-2 border-primary/30       (resting)
border-l-2 border-primary/50       (hover target)
```

Do not use lower opacity values — below 25% the border is invisible in most themes.

### Turn boundary spacing

When the sender role changes between adjacent messages (user → agent or agent → user), that boundary should have more vertical separation than consecutive same-sender messages. Currently this is handled via uniform `py-4` per message — this is an open improvement item (see Known Issues).

### DM surface (`messages_tab.ex`)

The DM surface uses a **bubble chat layout** — user messages right-aligned with a bubble, agent messages left-aligned as bare text. This is appropriate for 1:1 sessions.

```
[group row]  class="group flex items-end gap-1.5"
  [bubble or bare text]  max-w-[78%]
  [hover reveal row]  opacity-0 group-hover:opacity-100
    [LocalTime timestamp]
    [copy button]  data-copy-btn, data-copy-text={body}
```

Message list spacing: `space-y-3`. Scroll container: `py-4`.

---

## Identity and Sender Clarity

### Agent names

Agent sender names in the channel are rendered as clickable buttons that navigate to the agent's DM page:

```svelte
<button
  class="text-[13px] font-semibold text-primary/80 hover:text-primary transition-colors"
  on:click={() => navigateToDm(message.session_id)}
>
  {agent?.name || message.session_name || `@${message.session_id}`}
</button>
```

Fallback chain: `activeAgents` lookup by session_id → `message.session_name` → `@{session_id}`. Never fall back to "Agent" as a generic label.

### Provider icons

Provider icons are 16px images (`mt-1 flex-shrink-0`):

| Provider | Icon |
|---|---|
| `claude` / default | `/images/claude.svg` |
| `openai` / `codex` | `/images/openai.svg` |
| `gemini` | `/images/gemini.svg` |

Use `DmHelpers.provider_icon/1` on the server (HEEx). Use `getProviderIcon(message)` in Svelte.

### Timestamps

Format: `formatTime(inserted_at)` (time only, e.g., "10:32 AM"). Full date is in the date separator, not on each message.

In the DM surface, timestamps use `phx-hook="LocalTime"` with `data-utc` for server-rendered timezone conversion. The channel surface formats time client-side in Svelte.

---

## Metadata and Instrumentation

Token cost and usage metrics appear below agent message bodies:

```
mt-2 flex flex-nowrap gap-x-1.5 min-w-0 overflow-hidden
```

Individual chips:

```
inline-flex items-center px-2 py-0.5 rounded-md bg-base-content/[0.04]
text-[11px] font-mono tabular-nums
```

Chip content and color:

| Metric | Label | Color |
|---|---|---|
| `total_cost_usd` | `$0.0034` | `text-primary/50` |
| `input_tokens` | `1234 in` | `text-base-content/35` |
| `output_tokens` | `567 out` | `text-base-content/35` |
| `duration_ms` | `1.3s` | `text-base-content/35` |
| `num_turns` | `4 turns` | `text-base-content/25` |

Rules:
- **Always `flex-nowrap`** — wrapping breaks the subordinate visual hierarchy
- **Always `tabular-nums`** — prevents layout shift as numbers change
- **Always `font-mono`** — metrics are data, not prose
- Cost chip is slightly more prominent (`text-primary/50`) — it is the most operationally relevant value
- Metadata renders only for agent messages when `total_cost_usd` is present
- Add `title="..."` attributes on all chips for accessibility

---

## Actions and Affordances

### Hover actions (channel chat)

Revealed on `group-hover:opacity-100` in the identity row:

| Action | Icon | Event |
|---|---|---|
| Copy message | clipboard icon | `navigator.clipboard.writeText(body)` |
| Delete message | trash icon | `live.pushEvent('delete_message', { id })` |

**Missing (open items):** Reply in thread, reaction picker, overflow menu. See Known Issues.

Delete is currently at equal visual weight to Copy. This should be corrected — delete is destructive and must be separated or moved to an overflow menu.

### Hover actions (DM surface)

Revealed on `group-hover:opacity-100` in the timestamp row:

| Action | Pattern |
|---|---|
| Copy message | `data-copy-btn` + `data-copy-text={body}` |

The `data-copy-btn` global click handler in `app.js` handles all copy actions across the app. Use this pattern — do not write per-component clipboard calls in HEEx.

### Thread affordances

**Opening a thread:** Triggered by `live.pushEvent('open_thread', { message_id })`. The thread panel (`ThreadPanel.svelte`) slides in as a right-column sibling of the main chat column.

**Visible entry point:** The `thread_reply_count` button appears below the message body when `message.thread_reply_count > 0`. There is currently no hover affordance to *start* a new thread — this is an open issue.

**Closing a thread:** `live.pushEvent('close_thread', {})` → `push_patch` removes `thread_id` from the URL.

### Reactions

Existing reactions render as pill buttons below the message body:

```svelte
{#if message.reactions && message.reactions.length > 0}
  <div class="mt-2 flex flex-wrap gap-1">
    {#each message.reactions as reaction}
      <button on:click={() => live.pushEvent('toggle_reaction', { message_id, emoji: reaction.emoji })}>
        {reaction.emoji} <span>{reaction.count}</span>
      </button>
    {/each}
  </div>
{/if}
```

There is currently no reaction picker — users can only toggle reactions that already exist on a message. This is an open issue.

---

## Composer

### Channel chat

Single-line `<input type="text">` with @mention and /slash autocomplete. The input is a known limitation — multi-line instructions are unsupported. See Known Issues.

Submit: `Enter`. No `Shift+Enter` newline support with a single-line input.

Keyboard shortcuts:
- `⌘F` — open inline search
- `↑` / `Ctrl+P` — cycle message history (last 50 sent)
- `↓` / `Ctrl+N` — cycle forward through history

### @mention autocomplete

Triggered by `@` in the input. Options scoped to current channel members. Falls back to `activeAgents` for display info.

Each option shows: `@{session_id}` / `{name}` / `{provider} / {model}`.

`@all` is prepended as a broadcast option.

### /slash autocomplete

Triggered by `/` at start of input or after a space. Items grouped by type:

| Type | Badge color | Inserted as |
|---|---|---|
| `skill` | `bg-primary/10 text-primary` | `/slug ` |
| `command` | `bg-secondary/10 text-secondary` | `/slug ` |
| `agent` | `bg-accent/10 text-accent` | `@slug ` |
| `prompt` | `bg-warning/10 text-warning` | `/slug ` |

### DM composer

Single-line input inside the `DmPage` component. The DM surface handles `send_message` via `phx-submit`, not via Svelte `live.pushEvent`.

---

## Inline Search

Available in the channel chat. Not currently implemented in the DM surface.

**Trigger:** `⌘F` (or clicking the search trigger row). Opens a search bar above the message list.

**Behavior:** Client-side substring filter on `message.body`. Filtered messages replace the full list reactively via `$: filteredMessages`.

**Limitations:**
- Client-side only — searches only loaded messages (last 100)
- No match highlighting within message bodies
- No server-side full-text search integration (PgSearch exists but is not wired here)

**Closing:** `Esc` or the X button.

---

## Channel Sidebar (Flyout)

Rendered by `chat_content/1` in `flyout.ex`.

Channel rows:

```
px-3 py-2 text-sm flex items-center gap-2
  [#]  text-[13px] text-base-content/25 (inactive) or text-primary/60 (active)
  [name]  truncate flex-1; font-semibold text-base-content/85 when unread
  [unread dot]  w-1.5 h-1.5 rounded-full bg-primary (when unread > 0 and not active)
```

Active state: `text-primary bg-primary/8 font-medium`.

Unread counts flow through: `ChatLive.load_channel_assigns` → `Phoenix.LiveView.send_update(Rail)` → `Rail.update/2` → `flyout/1` → `chat_content/1`. After new messages: `PubSubHandlers` recalculates and repeats the `send_update`.

---

## Channel Header

`ChannelHeader` (`channel_header.ex`) renders above the message area.

Current structure:
- Floating card (`rounded-xl border shadow-sm mb-3 max-w-6xl mx-auto`)
- Channel name + `#` sigil + description
- Agent status count badges (`N active`, `N running`) — visible when counts are non-zero
- Always-on green pulse dot (a known issue — see below)
- Members toggle (expands inline member panel)
- New Agent button

**Known layout issue:** The `max-w-6xl mx-auto` constraint on the header does not match the unconstrained message body below it. Their left edges misalign on wide viewports.

---

## Working Indicator

When channel members are actively processing, a status row appears above the composer:

```svelte
{#if workingMembers.length > 0}
  <div class="flex items-center gap-2 text-xs text-base-content/40">
    <!-- three bouncing dots + "X is working" -->
  </div>
{/if}
```

`workingMembers` is computed from `channelMembers` filtered by `workingAgents` (a map of `session_id → true` maintained via `agent:working` PubSub topic).

The bouncing-dots animation is a consumer chat pattern. The preferred replacement is `<.status_dot status={:working}>` from `core_components.ex` (see Known Issues).

---

## Thread Panel

`ThreadPanel.svelte` renders as a 360px right-column sibling of the main chat column when `activeThread` is non-null.

Structure:
- Header: "Thread" label + close button
- Parent message (read-only, with markdown rendering)
- Reply count label
- Reply list (with markdown rendering)
- Reply composer (`<textarea>`, `⌘↵` to send)

The thread panel uses `marked` + `DOMPurify` with the same config as `AgentMessagesPanel`. The `.thread-body` scoped CSS mirrors `.message-body`.

Thread state is URL-driven: `?channel_id=N&thread_id=M`. Opening/closing is a `push_patch`.

---

## Known Issues (Open)

These are confirmed design problems without implemented fixes as of the last audit.

### High priority

| Issue | Description |
|---|---|
| **No thread-start affordance** | Threads are only enterable when `thread_reply_count > 0`. There is no hover action to start a new thread. |
| **Delete at equal weight to Copy** | Both appear in the hover action row with the same visual weight. Delete must be moved to an overflow menu. |
| **Single-line composer** | `<input type="text">` cannot handle multi-line agent instructions. Needs `<textarea>` with auto-resize. |
| **`flex-wrap` on identity row** | Hover actions (using `ml-auto`) can wrap to a new line on narrow viewports. Actions should be `absolute`-positioned relative to the group row. |
| **Header misalignment** | `max-w-6xl mx-auto` header does not align with the unconstrained message body. The card treatment should be replaced with a flush `border-b` bar. |

### Medium priority

| Issue | Description |
|---|---|
| **Always-on pulse dot** | The green pulse dot in the channel header is always visible regardless of agent activity. It carries no signal value. |
| **No turn-boundary spacing** | Human→Agent and Agent→Human transitions are visually identical to consecutive same-sender messages. |
| **No reaction picker** | Reactions are view-only for any emoji not already present. No way to add a first reaction. |
| **Composer hardcoded colors** | `oklch(97% 0.005 80)` and `hsl(60,2.1%,18.4%)` bypass DaisyUI tokens. Broken in non-default themes. |
| **Working indicator pattern** | Three bouncing dots is a consumer typing indicator. Replace with `<.status_dot status={:working}>` per the existing component. |
| **Search match highlighting** | Inline search filters messages but does not highlight the matched term within the message body. |

### Later / optional

| Issue | Description |
|---|---|
| **Channel keyboard shortcuts** | No `⌘1–⌘9` to jump between channels. |
| **Members panel as popover** | Current inline expansion in the header card is layout-fragile. A positioned popover is more stable. |
| **Message grouping by sender** | Consecutive messages from the same sender repeat the full identity line unnecessarily. |
| **Inspect message action** | No way to view raw message body, delivery timestamp, or full metadata without DB access. |

---

## Design Constraints

These apply to all work on this surface:

1. **DaisyUI tokens only.** Never use hardcoded hex, `oklch`, or `hsl` values in component styles. Use `bg-base-100`, `text-base-content/N`, `border-base-content/N`, etc.

2. **No `transition-all` on stream items.** LiveView `stream_insert` reinsertion causes CSS transitions to replay from initial state, producing visible flicker. Use specific transition properties (`transition-colors`, `transition-opacity`).

3. **`{@html}` requires DOMPurify.** Any `{@html}` injection in Svelte must go through `DOMPurify.sanitize()` with an explicit allowlist. No exceptions.

4. **No `fetch()` to `/api/v1` from Svelte.** All Svelte→server communication uses `live.pushEvent(...)`. See `feedback_no_fetch_api.md` in agent memory.

5. **`live` is auto-injected by LiveSvelte.** Do not pass `live` in props. Declare `export let live` in the component script and use it directly.

6. **Message body max-width is non-negotiable.** Full-width prose is unreadable. `max-w-[720px]` for channel chat; `max-w-[78%]` for DM bubbles.

7. **Metadata is always subordinate to body.** Token/cost chips must be visually lighter than body text. They are instrumentation, not content.
