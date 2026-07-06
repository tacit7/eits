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
    expect(web.some((i) => i.label === 'Open worktree in Finder')).toBe(false)
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
