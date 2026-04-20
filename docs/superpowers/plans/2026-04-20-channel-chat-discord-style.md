# Channel Chat Discord-style Refresh — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `AgentMessagesPanel.svelte` look and feel like Discord/Slack — message grouping, auto-growing textarea composer, and collapsed token metadata.

**Architecture:** Pure Svelte component change. Grouping helpers extracted to `assets/svelte/utils/messageGrouping.js` for testability; the component imports and uses them. Template switches from `{#each messages}` to `{#each renderedMessages}` using a derived view model. Input changes from `<input>` to `<textarea>` with `scrollHeight` resize. Token metadata moves from an always-visible row to an opacity-toggled absolute overlay.

**Tech Stack:** Svelte 4, Tailwind CSS, Vitest (unit tests for grouping helpers), existing `autoScroll` Svelte action, existing `formatTime`/`formatDateRelative` utils.

---

## File Map

| Action | File | Purpose |
|--------|------|---------|
| Create | `assets/svelte/utils/messageGrouping.js` | Pure grouping helpers — `messageTime`, `isSystemMessage`, `senderKey`, `sameCalendarDay`, `isNewDate`, `isGrouped` |
| Create | `assets/svelte/utils/messageGrouping.test.js` | Vitest unit tests for all helpers |
| Modify | `assets/svelte/components/tabs/AgentMessagesPanel.svelte` | Import helpers, add view model, update template, replace input with textarea, collapse metadata |

---

## Task 1: Grouping Helpers Module

**Files:**
- Create: `assets/svelte/utils/messageGrouping.js`
- Create: `assets/svelte/utils/messageGrouping.test.js`

- [ ] **Step 1.1: Create the helpers file**

```js
// assets/svelte/utils/messageGrouping.js

export const GROUP_WINDOW_MS = 5 * 60 * 1000

export function messageTime(message) {
  if (!message?.inserted_at) return null
  const time = new Date(message.inserted_at).getTime()
  return Number.isNaN(time) ? null : time
}

export function isSystemMessage(message) {
  return message?.sender_role === 'system' || message?.type === 'system'
}

export function senderKey(message) {
  if (!message || isSystemMessage(message)) return null
  if (message.sender_role === 'user') return 'user'
  if (message.session_id) return `session:${message.session_id}`
  return null
}

export function sameCalendarDay(a, b) {
  const at = messageTime(a)
  const bt = messageTime(b)
  if (at === null || bt === null) return false
  const da = new Date(at), db = new Date(bt)
  return da.getFullYear() === db.getFullYear()
    && da.getMonth() === db.getMonth()
    && da.getDate() === db.getDate()
}

export function isNewDate(message, prev) {
  if (!message) return false
  if (!prev) return true
  return !sameCalendarDay(message, prev)
}

export function isGrouped(message, prev) {
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

- [ ] **Step 1.2: Write the test file**

```js
// assets/svelte/utils/messageGrouping.test.js
import { describe, it, expect } from 'vitest'
import {
  messageTime,
  isSystemMessage,
  senderKey,
  sameCalendarDay,
  isNewDate,
  isGrouped,
  GROUP_WINDOW_MS,
} from './messageGrouping.js'

// Helpers
const msg = (overrides) => ({
  sender_role: 'agent',
  session_id: 42,
  inserted_at: '2026-04-20T10:00:00Z',
  ...overrides,
})

describe('messageTime', () => {
  it('returns null for missing inserted_at', () => {
    expect(messageTime({})).toBe(null)
    expect(messageTime(null)).toBe(null)
  })

  it('returns null for invalid date string', () => {
    expect(messageTime({ inserted_at: 'not-a-date' })).toBe(null)
  })

  it('returns epoch ms for valid ISO string', () => {
    const t = messageTime({ inserted_at: '2026-04-20T10:00:00Z' })
    expect(typeof t).toBe('number')
    expect(t).toBeGreaterThan(0)
  })
})

describe('isSystemMessage', () => {
  it('returns true for sender_role system', () => {
    expect(isSystemMessage({ sender_role: 'system' })).toBe(true)
  })

  it('returns true for type system', () => {
    expect(isSystemMessage({ sender_role: 'agent', type: 'system' })).toBe(true)
  })

  it('returns false for agent message', () => {
    expect(isSystemMessage(msg())).toBe(false)
  })

  it('returns false for null', () => {
    expect(isSystemMessage(null)).toBe(false)
  })
})

describe('senderKey', () => {
  it('returns "user" for user messages', () => {
    expect(senderKey({ sender_role: 'user' })).toBe('user')
  })

  it('returns session key for agent with session_id', () => {
    expect(senderKey(msg({ session_id: 99 }))).toBe('session:99')
  })

  it('returns null for agent without session_id', () => {
    expect(senderKey({ sender_role: 'agent' })).toBe(null)
  })

  it('returns null for system messages', () => {
    expect(senderKey({ sender_role: 'system' })).toBe(null)
  })

  it('returns null for null input', () => {
    expect(senderKey(null)).toBe(null)
  })
})

describe('sameCalendarDay', () => {
  it('returns true for same UTC day', () => {
    const a = { inserted_at: '2026-04-20T10:00:00Z' }
    const b = { inserted_at: '2026-04-20T23:59:00Z' }
    expect(sameCalendarDay(a, b)).toBe(true)
  })

  it('returns false for different days', () => {
    const a = { inserted_at: '2026-04-20T10:00:00Z' }
    const b = { inserted_at: '2026-04-21T10:00:00Z' }
    expect(sameCalendarDay(a, b)).toBe(false)
  })

  it('returns false when either timestamp is invalid', () => {
    const a = { inserted_at: 'bad' }
    const b = { inserted_at: '2026-04-20T10:00:00Z' }
    expect(sameCalendarDay(a, b)).toBe(false)
  })
})

describe('isNewDate', () => {
  it('returns true when there is no previous message', () => {
    expect(isNewDate(msg(), null)).toBe(true)
    expect(isNewDate(msg(), undefined)).toBe(true)
  })

  it('returns false when same day', () => {
    const a = msg({ inserted_at: '2026-04-20T10:00:00Z' })
    const b = msg({ inserted_at: '2026-04-20T11:00:00Z' })
    expect(isNewDate(b, a)).toBe(false)
  })

  it('returns true when different day', () => {
    const a = msg({ inserted_at: '2026-04-20T10:00:00Z' })
    const b = msg({ inserted_at: '2026-04-21T10:00:00Z' })
    expect(isNewDate(b, a)).toBe(true)
  })

  it('returns false for null message', () => {
    expect(isNewDate(null, msg())).toBe(false)
  })
})

describe('isGrouped', () => {
  it('groups same sender within 5 minutes', () => {
    const a = msg({ inserted_at: '2026-04-20T10:00:00Z' })
    const b = msg({ inserted_at: '2026-04-20T10:04:00Z' })
    expect(isGrouped(b, a)).toBe(true)
  })

  it('does not group messages > 5 minutes apart', () => {
    const a = msg({ inserted_at: '2026-04-20T10:00:00Z' })
    const b = msg({ inserted_at: '2026-04-20T10:06:00Z' })
    expect(isGrouped(b, a)).toBe(false)
  })

  it('does not group different session ids', () => {
    const a = msg({ session_id: 1 })
    const b = msg({ session_id: 2 })
    expect(isGrouped(b, a)).toBe(false)
  })

  it('does not group across midnight', () => {
    const a = msg({ inserted_at: '2026-04-20T23:58:00Z' })
    const b = msg({ inserted_at: '2026-04-21T00:01:00Z' })
    expect(isGrouped(b, a)).toBe(false)
  })

  it('does not group system messages', () => {
    const a = msg()
    const b = msg({ sender_role: 'system' })
    expect(isGrouped(b, a)).toBe(false)
  })

  it('does not group when prev is system', () => {
    const a = msg({ sender_role: 'system' })
    const b = msg()
    expect(isGrouped(b, a)).toBe(false)
  })

  it('does not group negative deltas', () => {
    const a = msg({ inserted_at: '2026-04-20T10:05:00Z' })
    const b = msg({ inserted_at: '2026-04-20T10:00:00Z' })
    expect(isGrouped(b, a)).toBe(false)
  })

  it('does not group agent without session_id', () => {
    const a = { sender_role: 'agent', inserted_at: '2026-04-20T10:00:00Z' }
    const b = { sender_role: 'agent', inserted_at: '2026-04-20T10:01:00Z' }
    expect(isGrouped(b, a)).toBe(false)
  })

  it('returns false when either message is null', () => {
    expect(isGrouped(null, msg())).toBe(false)
    expect(isGrouped(msg(), null)).toBe(false)
  })
})
```

- [ ] **Step 1.3: Set up vitest symlinks in the worktree**

```bash
# From the project root (or worktree if working in one)
cd assets
# If in a worktree, node_modules won't exist — symlink from main:
# ln -sf ../../../../assets/node_modules node_modules
# ln -sf ../../../../assets/vitest.config.mjs vitest.config.mjs
# ln -sf ../../../../assets/package.json package.json
```

- [ ] **Step 1.4: Run the tests — verify all pass**

```bash
cd assets && npx vitest run svelte/utils/messageGrouping.test.js
```

Expected: all tests pass (green).

- [ ] **Step 1.5: Commit**

```bash
git add assets/svelte/utils/messageGrouping.js assets/svelte/utils/messageGrouping.test.js
git commit -m "feat: add message grouping helpers with tests"
```

---

## Task 2: Derived View Model + Grouped Rendering

**Files:**
- Modify: `assets/svelte/components/tabs/AgentMessagesPanel.svelte`

The current template iterates `{#each messages as message, idx}`. We replace this with a derived view model and iterate `{#each renderedMessages as row, idx}`.

- [ ] **Step 2.1: Import grouping helpers at top of `<script>` block**

Find the existing imports section (lines 1-4) and add after the existing imports:

```svelte
<script>
  import { formatTime, formatDateRelative } from '../../utils/datetime.js'
  import { autoScroll } from '../../actions/autoScroll.js'
  import { isGrouped, isNewDate } from '../../utils/messageGrouping.js'
  // ... rest of existing script
```

- [ ] **Step 2.2: Add the derived view model reactive declaration**

Find the existing reactive declarations section (around `$: workingMembers = ...`) and add after it:

```js
$: renderedMessages = (messages || []).map((message, index) => ({
  message,
  grouped: isGrouped(message, (messages || [])[index - 1]),
  startsNewDate: isNewDate(message, (messages || [])[index - 1]),
}))
```

- [ ] **Step 2.3: Replace the `{#each messages ...}` block with `{#each renderedMessages ...}`**

Locate (around line 319):
```svelte
{#each messages as message, idx}
  <!-- Date separator -->
  {#if idx === 0 || formatDateRelative(messages[idx - 1].inserted_at) !== formatDateRelative(message.inserted_at)}
```

Replace the entire `{#each messages ...}` block (ending at the matching `{/each}`) with:

```svelte
{#each renderedMessages as { message, grouped, startsNewDate }}
  <!-- Date separator -->
  {#if startsNewDate}
    <div class="flex items-center gap-3 my-4">
      <div class="flex-1 h-px bg-base-content/5"></div>
      <span class="text-xs uppercase tracking-wider font-medium text-base-content/25 whitespace-nowrap">{formatDateRelative(message.inserted_at)}</span>
      <div class="flex-1 h-px bg-base-content/5"></div>
    </div>
  {/if}

  <!-- Message -->
  <div
    class="group relative py-1 px-2 -mx-2 rounded-lg transition-colors {message.sender_role === 'system' ? '' : grouped ? 'hover:bg-base-content/[0.02]' : message.sender_role === 'agent' ? 'bg-primary/[0.03]' : 'hover:bg-base-content/[0.02]'}"
  >
    {#if message.sender_role === 'system'}
      <!-- System message — unchanged -->
      <div class="flex items-center gap-2 text-xs text-base-content/30 italic px-1">
        <span class="w-1 h-1 rounded-full bg-base-content/20 flex-shrink-0"></span>
        <span class="flex-1">{message.body}</span>
        <button
          class="opacity-0 group-hover:opacity-100 text-base-content/20 hover:text-error transition-all cursor-pointer"
          on:click={() => live.pushEvent('delete_message', { id: String(message.id) })}
          title="Delete message"
        >
          <svg class="w-3 h-3" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M3 6h18"/><path d="M19 6v14c0 1-1 2-2 2H7c-1 0-2-1-2-2V6"/><path d="M8 6V4c0-1 1-2 2-2h4c1 0 2 1 2 2v2"/></svg>
        </button>
      </div>
    {:else if grouped}
      <!-- Grouped message: no header, indented to text column -->
      <div class="flex items-start gap-2.5 pr-16">
        <!-- Spacer matching avatar width -->
        <div class="w-4 flex-shrink-0"></div>
        <div class="min-w-0 flex-1">
          <p class="text-sm leading-relaxed text-base-content/85 whitespace-pre-wrap break-words">{message.body}</p>
          <!-- Token metadata for grouped child — opacity-toggled, no layout shift -->
          {#if message.sender_role === 'agent' && message.metadata && message.metadata.total_cost_usd}
            <div class="absolute right-2 top-1/2 -translate-y-1/2 opacity-0 group-hover:opacity-100 transition-opacity flex gap-1 pointer-events-none">
              <span class="font-mono text-[10px] text-base-content/20">${message.metadata.total_cost_usd.toFixed(4)}</span>
              {#if message.metadata.usage?.input_tokens}<span class="font-mono text-[10px] text-base-content/20">{message.metadata.usage.input_tokens}in</span>{/if}
              {#if message.metadata.usage?.output_tokens}<span class="font-mono text-[10px] text-base-content/20">{message.metadata.usage.output_tokens}out</span>{/if}
            </div>
          {/if}
          <!-- Grouped timestamp on hover -->
          <div class="absolute right-2 bottom-1 opacity-0 group-hover:opacity-100 transition-opacity pointer-events-none">
            <span class="text-[10px] text-base-content/20">{formatTime(message.inserted_at)}</span>
          </div>
        </div>
      </div>
    {:else}
      <!-- First message in group: full header -->
      <div class="flex items-start gap-2.5">
        <!-- Sender icon -->
        {#if message.sender_role === 'user'}
          <div class="w-4 h-4 rounded-full mt-1 flex-shrink-0 bg-success/20 flex items-center justify-center">
            <div class="w-1.5 h-1.5 rounded-full bg-success"></div>
          </div>
        {:else}
          <img src={getProviderIcon(message)} class="w-4 h-4 mt-1 flex-shrink-0" alt={message.provider || 'Agent'} />
        {/if}

        <div class="min-w-0 flex-1">
          <div class="flex items-baseline gap-2 flex-wrap pr-16">
            <span class="text-[11px] text-base-content/25">{formatTime(message.inserted_at)}</span>

            {#if message.sender_role === 'user'}
              <span class="text-[13px] font-semibold text-base-content/70">You</span>
            {:else if message.session_id}
              {@const agent = activeAgents.find(a => a.id === message.session_id)}
              <button
                class="text-[13px] font-semibold text-primary/80 hover:text-primary transition-colors cursor-pointer"
                on:click={() => navigateToDm(message.session_id)}
                title="Session #{message.session_id}"
              >
                {agent?.name || message.session_name || `@${message.session_id}`}
              </button>
            {:else}
              <span class="text-[13px] font-semibold text-primary/80">{message.provider || 'Agent'}</span>
            {/if}

            {#if message.number}
              <span class="font-mono text-xs text-base-content/20">#{message.number}</span>
            {/if}
            <button
              class="opacity-0 group-hover:opacity-100 ml-auto text-base-content/20 hover:text-error transition-all cursor-pointer"
              on:click={() => live.pushEvent('delete_message', { id: String(message.id) })}
              title="Delete message"
            >
              <svg class="w-3 h-3" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M3 6h18"/><path d="M19 6v14c0 1-1 2-2 2H7c-1 0-2-1-2-2V6"/><path d="M8 6V4c0-1 1-2 2-2h4c1 0 2 1 2 2v2"/></svg>
            </button>
          </div>

          <p class="mt-1 text-sm leading-relaxed text-base-content/85 whitespace-pre-wrap break-words">{message.body}</p>

          <!-- Token metadata — opacity-toggled, no layout shift -->
          {#if message.sender_role === 'agent' && message.metadata && message.metadata.total_cost_usd}
            <div class="absolute right-2 top-2 opacity-0 group-hover:opacity-100 transition-opacity flex gap-1 pointer-events-none">
              <span class="font-mono text-[10px] text-base-content/20">${message.metadata.total_cost_usd.toFixed(4)}</span>
              {#if message.metadata.usage?.input_tokens}<span class="font-mono text-[10px] text-base-content/20">{message.metadata.usage.input_tokens}in</span>{/if}
              {#if message.metadata.usage?.output_tokens}<span class="font-mono text-[10px] text-base-content/20">{message.metadata.usage.output_tokens}out</span>{/if}
              {#if message.metadata.duration_ms}<span class="font-mono text-[10px] text-base-content/20">{(message.metadata.duration_ms / 1000).toFixed(1)}s</span>{/if}
              {#if message.metadata.num_turns}<span class="font-mono text-[10px] text-base-content/20">{message.metadata.num_turns}t</span>{/if}
            </div>
          {/if}
        </div>
      </div>
    {/if}
  </div>
{/each}
```

- [ ] **Step 2.4: Verify the app compiles — check for Svelte errors**

```bash
cd /path/to/worktree && mix compile 2>&1 | tail -20
```

Expected: no errors (Svelte compile errors surface here via Vite watcher if Phoenix is running, or check `assets/` directly).

Also quickly check assets compile:
```bash
cd assets && npx vite build --mode development 2>&1 | tail -20
```

Expected: Build succeeded.

- [ ] **Step 2.5: Commit**

```bash
git add assets/svelte/components/tabs/AgentMessagesPanel.svelte
git commit -m "feat: message grouping — skip headers for consecutive same-sender messages"
```

---

## Task 3: Replace Input with Auto-growing Textarea

**Files:**
- Modify: `assets/svelte/components/tabs/AgentMessagesPanel.svelte`

- [ ] **Step 3.1: Add `tick` import and `textareaEl` variable + `resizeTextarea` + `clearComposer`**

At the top of the `<script>` block, add to the imports line:

```svelte
<script>
  import { tick } from 'svelte'
  import { formatTime, formatDateRelative } from '../../utils/datetime.js'
  // ... rest
```

Find where `let inputElement` is declared (it's in the variable declarations section near the top). Add alongside it:

```js
let inputElement     // keep for backward compat if referenced elsewhere
let textareaEl
```

Add these two functions in the script block (after the existing helper functions, before `handleSubmit`):

```js
function resizeTextarea(node) {
  if (!node) return
  node.style.height = 'auto'
  node.style.height = `${Math.min(node.scrollHeight, 144)}px`
}

async function clearComposer() {
  inputValue = ''
  await tick()
  resizeTextarea(textareaEl)
  textareaEl?.focus()
}
```

- [ ] **Step 3.2: Update `handleSubmit` to call `clearComposer`**

Find `handleSubmit` (currently around line 281):

```js
function handleSubmit(e) {
  const body = inputValue.trim()

  if (body) {
    live.pushEvent('send_channel_message', {
      channel_id: activeChannelId,
      body: body
    })

    messageHistory.unshift(body)
    if (messageHistory.length > 50) {
      messageHistory = messageHistory.slice(0, 50)
    }

    historyIndex = -1
    currentDraft = ''
    inputValue = ''
    shouldAutoScroll = true
  }
}
```

Replace with:

```js
async function handleSubmit(e) {
  const body = inputValue.trim()

  if (body) {
    live.pushEvent('send_channel_message', {
      channel_id: activeChannelId,
      body: body
    })

    messageHistory.unshift(body)
    if (messageHistory.length > 50) {
      messageHistory = messageHistory.slice(0, 50)
    }

    historyIndex = -1
    currentDraft = ''
    shouldAutoScroll = true
    await clearComposer()
  }
}
```

- [ ] **Step 3.3: Update `handleInputKeydown` to add Enter-submit logic**

The existing `handleInputKeydown` ends after the `ArrowUp/Down` message history navigation block. After those blocks, add a new block at the end of the function:

```js
// Enter to submit (when no autocomplete is active)
if (e.key === 'Enter' && !e.shiftKey && !e.isComposing) {
  e.preventDefault()
  handleSubmit()
  return
}
```

The full function priority is already correct (slash autocomplete → @ autocomplete → history → **submit**). This block only fires when none of the earlier checks returned.

- [ ] **Step 3.4: Replace `<input>` with `<textarea>` in the template**

Find the composer `<input>` element (around line 469):

```svelte
<input
  type="text"
  bind:value={inputValue}
  bind:this={inputElement}
  on:input={handleInputChange}
  on:keydown={handleInputKeydown}
  placeholder="Message agents... @id to mention, /skill for commands"
  class="input input-sm w-full bg-base-200/50 border-base-content/8 placeholder:text-base-content/25 focus:border-primary/30 focus:bg-base-100 transition-colors text-base h-10"
  autocomplete="off"
/>
```

Replace with:

```svelte
<textarea
  bind:value={inputValue}
  bind:this={textareaEl}
  on:input={(e) => { handleInputChange(e); resizeTextarea(textareaEl) }}
  on:keydown={handleInputKeydown}
  placeholder="Message agents... @id to mention, /skill for commands"
  class="input input-sm w-full bg-base-200/50 border-base-content/8 placeholder:text-base-content/25 focus:border-primary/30 focus:bg-base-100 transition-colors text-base resize-none overflow-y-auto leading-relaxed"
  style="min-height: 40px; max-height: 144px;"
  autocomplete="off"
  rows="1"
></textarea>
```

- [ ] **Step 3.5: Add `onMount` to resize textarea on initial render**

Find any existing `onMount` call, or add it. Import `onMount` from svelte if not already imported:

```svelte
<script>
  import { tick, onMount } from 'svelte'
```

Add at the bottom of the script block (or inside an existing `onMount`):

```js
onMount(() => {
  resizeTextarea(textareaEl)
})
```

- [ ] **Step 3.6: Compile and visually verify**

```bash
mix compile 2>&1 | tail -10
```

Expected: no errors.

Load the app at `http://localhost:5001`, navigate to a channel, and verify:
- Textarea renders as one line
- Typing wraps and expands up to ~6 lines
- Enter sends the message
- Shift+Enter inserts a newline
- `@` mention autocomplete still works
- `/` slash autocomplete still works

- [ ] **Step 3.7: Commit**

```bash
git add assets/svelte/components/tabs/AgentMessagesPanel.svelte
git commit -m "feat: replace input with auto-growing textarea composer"
```

---

## Task 4: Final Compile Check + PR

**Files:**
- No new changes — verification only

- [ ] **Step 4.1: Run full compile with warnings-as-errors**

```bash
mix compile --warnings-as-errors 2>&1
```

Expected: no errors, no warnings that would block merge.

- [ ] **Step 4.2: Run grouping tests one final time**

```bash
cd assets && npx vitest run svelte/utils/messageGrouping.test.js
```

Expected: all pass.

- [ ] **Step 4.3: Manual checklist**

Verify in the browser (`http://localhost:5001`):

- [ ] Two consecutive agent messages from the same agent — second shows no avatar/header
- [ ] Two messages from different agents — both show full header
- [ ] System message between two agent messages — all three show full headers
- [ ] Date separator appears when a new calendar day starts
- [ ] Token cost pills are invisible by default; appear on hover
- [ ] Textarea grows as you type; resets to one line after send
- [ ] `@all` and `@name` autocomplete still opens and inserts correctly
- [ ] `/skill` autocomplete still opens and inserts correctly
- [ ] Enter with slash autocomplete open → selects item, does not submit
- [ ] Enter with @ autocomplete open → selects mention, does not submit

- [ ] **Step 4.4: Push and open PR**

```bash
git push origin <branch-name>
gh pr create --title "feat: discord-style channel chat refresh" --body "$(cat <<'EOF'
## Summary
- Message grouping: consecutive same-sender messages skip the avatar/header (5-min window, same-day, non-system only)
- Input replaced with auto-growing textarea; Enter submits, Shift+Enter newlines, IME-safe
- Token metadata collapsed to opacity-0 by default, appears on group hover — no layout shift
- Grouping helpers extracted to `assets/svelte/utils/messageGrouping.js` with full vitest coverage

## Test plan
- [ ] Unit tests pass: `cd assets && npx vitest run svelte/utils/messageGrouping.test.js`
- [ ] Consecutive same-sender messages group (no repeated header)
- [ ] System messages always standalone
- [ ] Token metadata invisible by default, visible on hover
- [ ] Textarea grows/resets; autocomplete unaffected
EOF
)"
```
