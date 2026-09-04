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
//   push(event, payload)    pushEvent to the page LiveView, or — for events
//                           owned by Rail (its own live_render'd LiveView) —
//                           bridged via a `tauri:rail-action` CustomEvent
//   flash(msg)              info toast via phx:flash
//   prompt(opts)            DaisyUI text-input dialog; resolves trimmed
//                           value or null on cancel
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
  // Project rows live in the ProjectSwitcher popup, which is part of Rail's
  // own live_render'd LiveView — actions push through the ctx.push() Rail
  // bridge (see hooks/context_menu.js), not the page LiveView. Rename/open
  // terminal/open editor all resolve the project's path server-side; the
  // client never sends a path back for a mutating or shell-launching action.
  project: (d) => [
    { label: 'Open', icon: 'hero-arrow-up-right', run: (c) => c.navigate(`/projects/${d.ctxId}`) },
    {
      label: 'Open in New Window',
      icon: 'hero-arrow-top-right-on-square',
      tauri: true,
      run: (c) => c.push('open_in_window', { project_id: d.ctxId }),
    },
    { sep: true },
    {
      label: 'Rename…',
      icon: 'hero-pencil-square',
      run: async (c) => {
        const name = await c.prompt({ title: 'Rename project', value: d.ctxName, placeholder: 'Project name' })
        if (name) c.push('rename_project', { project_id: d.ctxId, name })
      },
    },
    { label: 'Copy project path', icon: 'hero-document-duplicate', run: (c) => c.copy(d.ctxPath || '') },
    {
      label: 'Open in Terminal',
      icon: 'hero-command-line',
      run: (c) => c.push('open_project_terminal', { project_id: d.ctxId }),
    },
    {
      label: 'Open in Editor',
      icon: 'hero-code-bracket',
      run: (c) => c.push('open_project_in_editor', { project_id: d.ctxId }),
    },
    { sep: true },
    {
      label: 'Delete project',
      icon: 'hero-trash',
      danger: true,
      run: (c) => c.push('delete_project', { project_id: d.ctxId }),
    },
  ],

  // File/directory rows in the rail's file explorer tree — also part of
  // Rail's own live_render'd LiveView, so actions bridge through ctx.push()
  // same as project. Rename is deliberately scoped to files, not
  // directories (see FileTree.rename/3) — kept out of the menu for dirs.
  file: (d) => {
    const isDir = d.ctxIsDir === 'true'
    return [
      ...(isDir
        ? []
        : [
            { label: 'Open', icon: 'hero-arrow-up-right', run: (c) => c.push('file_open', { path: d.ctxPath }) },
            {
              label: `Open in ${d.ctxEditorLabel || 'External Editor'}`,
              icon: 'hero-code-bracket',
              run: (c) => c.push('open_file_in_editor', { path: d.ctxPath }),
            },
          ]),
      {
        label: 'Reveal in Finder',
        icon: 'hero-folder-open',
        run: (c) => c.push('reveal_file', { path: d.ctxPath }),
      },
      { sep: true },
      { label: 'Copy path', icon: 'hero-document-duplicate', run: (c) => c.copy(d.ctxAbsPath || '') },
      {
        label: 'Copy relative path',
        icon: 'hero-document-duplicate',
        run: (c) => c.copy(d.ctxPath || ''),
      },
      ...(isDir
        ? []
        : [
            { sep: true },
            {
              label: 'Rename…',
              icon: 'hero-pencil-square',
              run: async (c) => {
                const name = await c.prompt({ title: 'Rename', value: d.ctxName, placeholder: 'New name' })
                if (name) c.push('rename_file', { path: d.ctxPath, name })
              },
            },
          ]),
    ]
  },

  // Agent-definition and skill/command rows on the Agents/Skills list pages
  // (overview + project scoped). These pages are standalone LiveViews, not
  // nested inside Rail, so actions push directly — no rail bridge needed.
  // Duplicate/Delete are scoped to bare .md files; a skill backed by a
  // directory (SKILL.md + sibling reference files) can't be safely
  // duplicated/deleted from a single menu item — see
  // DefinitionFileActions moduledoc. No "Set as default" — no such concept
  // exists for agent/skill definitions in this codebase.
  definition_file: (d) => {
    const isDirBacked = d.ctxIsDir === 'true'
    return [
      {
        label: 'Edit',
        icon: 'hero-pencil-square',
        run: (c) => c.push('open_in_editor', { editor: d.ctxEditor, path: d.ctxAbsPath }),
      },
      {
        label: 'Export/Copy config',
        icon: 'hero-document-duplicate',
        run: (c) => c.copy(d.ctxContent || ''),
      },
      ...(isDirBacked
        ? []
        : [
            { sep: true },
            {
              label: 'Duplicate',
              icon: 'hero-square-2-stack',
              run: (c) => c.push('duplicate_definition_file', { path: d.ctxAbsPath }),
            },
            {
              label: 'Delete',
              icon: 'hero-trash',
              danger: true,
              run: (c) => c.push('delete_definition_file', { path: d.ctxAbsPath }),
            },
          ]),
    ]
  },

  // Channel rows live in the rail flyout (Rail's own live_render'd
  // LiveView) — actions bridge through ctx.push() same as project/file.
  // No "Mute" — no such concept exists on the channel schema.
  channel: (d) => [
    { label: 'Open', icon: 'hero-arrow-up-right', run: (c) => c.navigate(`/chat?channel_id=${d.ctxId}`) },
    {
      label: 'Rename…',
      icon: 'hero-pencil-square',
      run: async (c) => {
        const name = await c.prompt({ title: 'Rename channel', value: d.ctxName, placeholder: 'Channel name' })
        if (name) c.push('rename_channel', { channel_id: d.ctxId, name })
      },
    },
    { label: 'Copy channel ID', icon: 'hero-document-duplicate', run: (c) => c.copy(String(d.ctxId)) },
    { sep: true },
    {
      label: 'Delete channel',
      icon: 'hero-trash',
      danger: true,
      run: (c) => c.push('delete_channel', { channel_id: d.ctxId }),
    },
  ],

  // Team rows on the Teams list page (standalone LiveView, not nested in
  // Rail) — actions push directly, no rail bridge. No Rename/Duplicate — no
  // such handlers exist for teams anywhere in the codebase; "Manage
  // members/agents" is the same destination as Open (team_show.ex has no
  // separate members route), so it isn't a distinct menu item here.
  team: (d) => [
    { label: 'Open', icon: 'hero-arrow-up-right', run: (c) => c.navigate(d.ctxPath) },
    { label: 'Copy team ID', icon: 'hero-document-duplicate', run: (c) => c.copy(String(d.ctxId)) },
    { sep: true },
    {
      label: 'Delete team',
      icon: 'hero-trash',
      danger: true,
      run: (c) => c.push('delete_team', { id: d.ctxId }),
    },
  ],

  // Prompt rows on the Prompts list pages (overview + project scoped,
  // standalone LiveViews — direct pushEvent, no rail bridge). "Open" reuses
  // the page's own inline select_prompt toggle; both pages' handlers only
  // require their own key ("id" on overview, "uuid" on project) and Elixir
  // map pattern matching ignores the extra key, so sending both is safe on
  // either page. "Open full editor" only renders when the row has a real
  // detail-page path (global prompts with no project_id have none).
  prompt: (d) => [
    { label: 'Open', icon: 'hero-arrow-up-right', run: (c) => c.push('select_prompt', { id: d.ctxId, uuid: d.ctxUuid }) },
    ...(d.ctxPath
      ? [
          {
            label: 'Open full editor',
            icon: 'hero-arrow-top-right-on-square',
            run: (c) => c.navigate(d.ctxPath),
          },
        ]
      : []),
    { sep: true },
    { label: 'Copy slug', icon: 'hero-document-duplicate', run: (c) => c.copy(d.ctxSlug || '') },
    {
      label: 'Duplicate',
      icon: 'hero-square-2-stack',
      run: (c) => c.push('duplicate_prompt', { uuid: d.ctxUuid }),
    },
    { sep: true },
    {
      label: 'Deactivate',
      icon: 'hero-trash',
      danger: true,
      run: (c) => c.push('deactivate_prompt', { uuid: d.ctxUuid }),
    },
  ],

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
      // Triggers the page's inline edit-in-place rename — the SAME flow as the
      // "…" menu (project_live/sessions handle_event("rename_session") sets
      // editing_session_id). Routed to the page LiveView, not the Rail LC, so
      // it is NOT in context_menu.js's railEvents list. session_id stays a
      // string so the page's ControllerHelpers.parse_int/1 handles it.
      label: 'Rename…',
      icon: 'hero-pencil-square',
      run: (c) => c.push('rename_session', { session_id: d.ctxId }),
    },
    {
      label: 'Archive',
      icon: 'hero-archive-box',
      run: (c) => c.push('archive_session', { session_id: Number(d.ctxId) }),
    },
    { sep: true },
    { label: 'Copy session ID', icon: 'hero-document-duplicate', run: (c) => c.copy(String(d.ctxId)) },
    {
      label: 'Copy link',
      icon: 'hero-link',
      run: (c) => c.copy(`eits://dm/${d.ctxUuid || d.ctxId}`),
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
    { label: 'Copy link', icon: 'hero-document-duplicate', run: (c) => c.copy(`eits://tasks/${d.ctxId}`) },
    ...(d.ctxSessionUuid
      ? [{ label: 'Chat with agent', icon: 'hero-chat-bubble-left-ellipsis', run: (c) => c.navigate(`/dm/${d.ctxSessionUuid}`) }]
      : []),
    { sep: true },
    {
      label: 'Delete task',
      icon: 'hero-trash',
      danger: true,
      run: (c) => c.push('delete_task', { task_id: d.ctxId }),
    },
  ],

  // Note items push the notes page's EXISTING events (toggle_star / delete_note,
  // both keyed on note_id — see live/shared/notes_helpers.ex), so no new server
  // code. The menu only opens where notes_list.ex renders data-ctx="note" rows,
  // i.e. the notes page, which is exactly where those handlers live.
  note: (d) => [
    { label: 'Open', icon: 'hero-arrow-up-right', run: (c) => c.navigate(`/notes/${d.ctxId}/edit`) },
    {
      label: d.ctxStarred === 'true' ? 'Unstar' : 'Star',
      icon: 'hero-star',
      run: (c) => c.push('toggle_star', { note_id: d.ctxId }),
    },
    { sep: true },
    { label: 'Copy note ID', icon: 'hero-document-duplicate', run: (c) => c.copy(String(d.ctxId)) },
    { sep: true },
    {
      label: 'Delete note',
      icon: 'hero-trash',
      danger: true,
      run: (c) => c.push('delete_note', { note_id: d.ctxId }),
    },
  ],
}

/** Resolve the item list for a trigger element, filtering tauri-only items
 *  in the browser. Returns null for unknown types (menu must not open). */
export function itemsFor(type, dataset, isTauri) {
  const builder = REGISTRY[type]
  if (!builder) return null
  const items = builder(dataset).filter((it) => !it.tauri || isTauri)
  // disclosure leading/trailing/doubled separators after filtering
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
