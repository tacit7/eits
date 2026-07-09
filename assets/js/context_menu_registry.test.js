import { describe, it, expect } from 'vitest'
import { itemsFor, clampPosition } from './context_menu_registry'

describe('itemsFor', () => {
  it('returns null for unknown types', () => {
    expect(itemsFor('bogus', {}, true)).toBeNull()
  })
  it('filters tauri-only items in browser and collapses separators', () => {
    const web = itemsFor('session', { ctxId: '1', ctxUuid: 'u', ctxWorktree: '/x' }, false)
    const app = itemsFor('session', { ctxId: '1', ctxUuid: 'u', ctxWorktree: '/x' }, true)
    expect(web.some((i) => i.label === 'Open in New Window')).toBe(false)
    expect(app.some((i) => i.label === 'Open in New Window')).toBe(true)
    // server-side reveal works in the browser too — present in BOTH
    expect(web.some((i) => i.label === 'Open worktree in Finder')).toBe(true)
    // no doubled separators after filtering
    web.forEach((it, ix) => { if (it.sep) expect(web[ix + 1]?.sep).not.toBe(true) })
    expect(web[0].sep).not.toBe(true)
    expect(web[web.length - 1].sep).not.toBe(true)
  })
  it('omits worktree item when no worktree data attr', () => {
    const app = itemsFor('session', { ctxId: '1' }, true)
    expect(app.some((i) => i.label === 'Open worktree in Finder')).toBe(false)
  })
  it('task submenu carries the 4 workflow states in position order', () => {
    const items = itemsFor('task', { ctxId: '9' }, false)
    const move = items.find((i) => i.label === 'Move to')
    expect(move.children.map((c) => c.label)).toEqual(['To Do', 'In Progress', 'In Review', 'Done'])
  })
  it('note star label follows data-ctx-starred', () => {
    expect(itemsFor('note', { ctxId: '1', ctxStarred: 'true' }, false).some((i) => i.label === 'Unstar')).toBe(true)
    expect(itemsFor('note', { ctxId: '1' }, false).some((i) => i.label === 'Star')).toBe(true)
  })
})

// Records every ctx call so we can assert the exact event + payload an item
// pushes. This is the seam that silently breaks selections (wrong event name,
// wrong payload key/type, or an item that pushes nothing).
function mockCtx() {
  const calls = { push: [], copy: [], navigate: [], flash: [], invoke: [] }
  return {
    calls,
    push: (e, p) => calls.push.push([e, p]),
    copy: (t) => calls.copy.push(t),
    navigate: (p) => calls.navigate.push(p),
    flash: (m) => calls.flash.push(m),
    invoke: (cmd, a) => calls.invoke.push([cmd, a]),
    prompt: async () => null,
  }
}
const run = (type, dataset, label, isTauri = false) => {
  const item = itemsFor(type, dataset, isTauri).find((i) => i.label === label)
  const c = mockCtx()
  item.run(c)
  return c.calls
}

describe('item action contract (event + payload)', () => {
  const S = { ctxId: '42', ctxUuid: 'uuid-abc', ctxName: 'foo' }

  it('session Rename pushes rename_session with the string id and NO prompt', () => {
    // Must match the page "…" menu (inline edit) — a bare session_id, routed to
    // the page LiveView. Regression guard for the prompt+extra.name version.
    expect(run('session', S, 'Rename…').push).toEqual([['rename_session', { session_id: '42' }]])
  })

  it('session has no "Mark as unread" item', () => {
    expect(itemsFor('session', S, false).some((i) => i.label === 'Mark as unread')).toBe(false)
  })

  it('Copy session ID copies the numeric id, not the uuid', () => {
    expect(run('session', S, 'Copy session ID').copy).toEqual(['42'])
  })

  it('Copy deeplink still uses the uuid', () => {
    expect(run('session', S, 'Copy deeplink').copy).toEqual(['eits://sessions/uuid-abc'])
  })

  it('session Archive pushes archive_session with a numeric session_id', () => {
    expect(run('session', S, 'Archive').push).toEqual([['archive_session', { session_id: 42 }]])
  })

  it('task Move-to child pushes move_task with a stringified state_id', () => {
    const items = itemsFor('task', { ctxId: 't1' }, false)
    const inProgress = items.find((i) => i.label === 'Move to').children.find((c) => c.label === 'In Progress')
    const c = mockCtx()
    inProgress.run(c)
    expect(c.calls.push).toEqual([['move_task', { task_id: 't1', state_id: '2' }]])
  })

  it('note Delete pushes delete_note keyed on note_id', () => {
    expect(run('note', { ctxId: 'n7' }, 'Delete note').push).toEqual([['delete_note', { note_id: 'n7' }]])
  })
})

describe('clampPosition', () => {
  it('keeps menu at cursor when it fits', () => {
    expect(clampPosition(100, 100, 220, 300, 1280, 800)).toEqual({ left: 100, top: 100 })
  })
  it('flips left/up near edges', () => {
    expect(clampPosition(1200, 700, 220, 300, 1280, 800)).toEqual({ left: 980, top: 400 })
  })
  it('never goes negative', () => {
    expect(clampPosition(2, 2, 5000, 5000, 1280, 800)).toEqual({ left: 4, top: 4 })
  })
})
