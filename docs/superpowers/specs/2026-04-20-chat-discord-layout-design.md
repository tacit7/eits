# Chat Page — Discord-style Layout

**Date:** 2026-04-20
**Scope:** Chat page layout only — no backend changes, no message rendering changes.

---

## Goal

Remove the main application sidebar from the chat page entirely. Replace it with a self-contained Discord/Slack-style layout: a narrow channel list panel on the left, a back button to return to the previous page, and the existing message feed filling the rest.

---

## What Changes

### 1. Chat route — new layout

The `/chat` route currently uses the default root layout which renders the main sidebar. It must switch to a layout that renders **no sidebar** — the chat page owns its full viewport.

Implementation: add a `layout: false` or a dedicated `chat_layout.html.heex` that omits the sidebar component. The top nav bar (if present) should also be removed — chat is full-screen.

### 2. Channel sidebar (inside the chat page)

A new fixed-width left panel (≈200px) renders inside `ChatLive`. It contains:

- **Back button** at the top — `hero-arrow-left` icon + "Back" text. Uses the same inline pattern already established in `canvas_live.ex`: `onclick="history.length > 1 ? history.back() : window.location.href = '/'"`. No new hook needed. Styled as a small ghost button (`btn btn-ghost btn-xs`).
- **"Channels" section header** with a `+` button to create a new channel (existing inline form behavior).
- **Channel list** — one row per channel, `#name` format, active channel highlighted. Same click-to-navigate behavior as the current sidebar list.

The channel list is **removed from the main sidebar** (`chat_section.ex`). It lives only here.

### 3. Main sidebar — channels removed

`chat_section.ex` / `SidebarLive` still renders the "Chat" nav item for non-chat pages. The channel sub-list (`expanded_chat` tree) is removed. Clicking "Chat" in the sidebar navigates to `/chat` and the sidebar item stays as a single link — no expandable channel tree.

### 4. Message feed

No changes. `AgentMessagesPanel.svelte` and `ChannelHeader` render exactly as they do today inside the right-side pane.

---

## Layout Structure

```
┌──────────────────────────────────────────────────────┐
│  ← Back      │  # general                            │
│  ─────────── │  ─────────────────────────────────── │
│  CHANNELS +  │  [messages]                           │
│  # general   │                                       │
│  # agents    │                                       │
│  # work-queue│                                       │
│  # plan-rev  │                                       │
│              │  [composer]                           │
└──────────────┴───────────────────────────────────────┘
  200px                    flex-1
```

---

## Back Button Behavior

Reuse the pattern from `canvas_live.ex` verbatim:

```heex
<button
  onclick="history.length > 1 ? history.back() : window.location.href = '/'"
  class="btn btn-ghost btn-xs px-1.5 text-base-content/50 hover:text-base-content"
  aria-label="Go back"
  title="Go back"
>
  <.icon name="hero-arrow-left" class="w-4 h-4" />
  <span class="text-xs ml-1">Back</span>
</button>
```

No new JS hook needed. Falls back to `/` if no browser history.

---

## What Does NOT Change

- `ChatLive` event handlers, PubSub subscriptions, message loading
- `AgentMessagesPanel.svelte` — no modifications
- `ChannelHeader` component
- Channel creation logic (`create_channel` event)
- URL structure (`/chat?channel_id=X`)
- All other sidebar behavior on non-chat pages

---

## Success Criteria

- Navigating to `/chat` shows no main sidebar.
- Channel list appears in the left panel of the chat page.
- Clicking a channel navigates correctly, active state updates.
- Back button returns user to previous page; falls back to `/` if no history.
- Navigating away from `/chat` to any other page shows the normal sidebar (without channel list).
- No regressions in message sending, @mention, /slash, PubSub updates.
