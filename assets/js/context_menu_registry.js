// Context menu registry — one entry per entity type (`data-ctx` value).
//
// Each builder receives the trigger element's dataset (data-ctx-* attrs,
// camelCased by the DOM: data-ctx-id -> d.ctxId) and returns the item list.
// Item shape:
//   { label, icon, run(ctx) }            — plain action
//   { tauri: true }                      — rendered only under data-env="tauri"
//   { danger: true }                     — red + inline "Really? ✓/✕" confirm
//   { sep: true }                        — separator
//   { label, icon, children: [items] }   — submenu
//
// `ctx` (passed to run) provides:
//   navigate(path)          live navigation
//   invoke(cmd, args)       Tauri command (no-op outside the desktop app)
//   copy(text)              clipboard (Tauri bridge in-app, navigator.clipboard else)
//   push(event, payload)    dispatch a `ctx-action` CustomEvent for the
//                           pushEvent bridge (same protocol as the legacy
//                           native rail menu's tauri:session-action)
//   flash(msg)              info toast via phx:flash
//
// Keep builders pure: read dataset, return items. No DOM work here.

// Workflow states (see lib/CLAUDE.md — position order, not id order)
const TASK_STATES = [
  { id: 1, name: 'To Do', color: '#6B7280' },
  { id: 2, name: 'In Progress', color: '#3B82F6' },
  { id: 4, name: 'In Review', color: '#F59E0B' },
  { id: 3, name: 'Done', color: '#10B981' },
]

export const REGISTRY = {
  session: (d) => [
    { label: 'Open', icon: 'hero-arrow-up-right', run: (c) => c.navigate(`/dm/${d.ctxId}`) },
    {
      label: 'Open in New Window',
      icon: 'hero-arrow-top-right-on-square',
      tauri: true,
      run: (c) => c.invoke('open_window', { path: `/dm/${d.ctxId}` }),
    },
    { sep: true },
    {
      label: 'Rename…',
      icon: 'hero-pencil-square',
      run: async (c) => {
        const name = await c.prompt({
          title: 'Rename session',
          value: d.ctxName || '',
          placeholder: 'Session name',
        })
        if (name) {
          c.push('rename_session', { session_id: Number(d.ctxId), extra: { name } })
        }
      },
    },
    {
      label: 'Archive',
      icon: 'hero-archive-box',
      run: (c) => c.push('archive_session', { session_id: Number(d.ctxId) }),
    },
    { label: 'Mark as unread', icon: 'hero-envelope', run: (c) => c.flash('Coming soon') },
    { sep: true },
    { label: 'Copy session ID', icon: 'hero-document-duplicate', run: (c) => c.copy(d.ctxUuid || d.ctxId) },
    {
      label: 'Copy deeplink',
      icon: 'hero-link',
      run: (c) => c.copy(`eits://sessions/${d.ctxUuid || d.ctxId}`),
    },
    ...(d.ctxWorktree
      ? [
          {
            // Server-side reveal (System.cmd open/explorer/xdg-open) — the
            // Phoenix server always runs on the user's machine, so this works
            // in the browser too, not just the desktop app.
            label: 'Open worktree in Finder',
            icon: 'hero-folder-open',
            run: (c) => c.push('open_worktree', { session_id: Number(d.ctxId) }),
          },
        ]
      : []),
    { sep: true },
    { label: 'DM this session', icon: 'hero-chat-bubble-left-right', run: (c) => c.navigate(`/dm/${d.ctxId}`) },
  ],

  // Task items push the pages' EXISTING events (open_task_detail/move_task/
  // delete_task — all uuid-or-id tolerant via get_task_by_uuid_or_id!), so any
  // page with task cards works with zero new server code. data-ctx-id carries
  // the task uuid.
  task: (d) => [
    { label: 'Open', icon: 'hero-arrow-up-right', run: (c) => c.push('open_task_detail', { task_id: d.ctxId }) },
    { sep: true },
    {
      label: 'Move to',
      icon: 'hero-arrow-right',
      children: TASK_STATES.map((s) => ({
        label: s.name,
        dot: s.color,
        run: (c) => c.push('move_task', { task_id: d.ctxId, state_id: String(s.id) }),
      })),
    },
    { sep: true },
    { label: 'Copy task ID', icon: 'hero-document-duplicate', run: (c) => c.copy(d.ctxIntId || d.ctxId) },
    { sep: true },
    {
      label: 'Delete task',
      icon: 'hero-trash',
      danger: true,
      run: (c) => c.push('delete_task', { task_id: d.ctxId }),
    },
  ],

  note: (d) => [
    { label: 'Open', icon: 'hero-arrow-up-right', run: (c) => c.navigate(`/notes/${d.ctxId}/edit`) },
    {
      label: d.ctxStarred === 'true' ? 'Unstar' : 'Star',
      icon: 'hero-star',
      run: (c) => c.push('ctx_toggle_star_note', { note_id: Number(d.ctxId) }),
    },
    { sep: true },
    { label: 'Copy note ID', icon: 'hero-document-duplicate', run: (c) => c.copy(String(d.ctxId)) },
    { sep: true },
    {
      label: 'Delete note',
      icon: 'hero-trash',
      danger: true,
      run: (c) => c.push('ctx_delete_note', { note_id: Number(d.ctxId) }),
    },
  ],
}

/** Resolve the item list for a trigger element, filtering tauri-only items
 *  in the browser. Returns null for unknown types (menu must not open). */
export function itemsFor(type, dataset, isTauri) {
  const builder = REGISTRY[type]
  if (!builder) return null
  const items = builder(dataset).filter((it) => !it.tauri || isTauri)
  // collapse leading/trailing/doubled separators after filtering
  const out = []
  for (const it of items) {
    if (it.sep && (out.length === 0 || out[out.length - 1].sep)) continue
    out.push(it)
  }
  while (out.length && out[out.length - 1].sep) out.pop()
  return out.length ? out : null
}

/** Viewport-clamped menu position. Pure — unit-tested. */
export function clampPosition(x, y, menuW, menuH, vw, vh, pad = 4) {
  let left = x
  let top = y
  if (left + menuW + pad > vw) left = Math.max(pad, x - menuW)
  if (top + menuH + pad > vh) top = Math.max(pad, y - menuH)
  return { left, top }
}
