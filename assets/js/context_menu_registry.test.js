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

  it('project Rename… awaits the ctx-menu prompt then pushes rename_project', async () => {
    const item = itemsFor('project', { ctxId: '7', ctxName: 'eits-web' }, false).find((i) => i.label === 'Rename…')
    const c = mockCtx()
    c.prompt = async () => 'new-name'
    await item.run(c)
    expect(c.calls.push).toEqual([['rename_project', { project_id: '7', name: 'new-name' }]])
  })

  it('project Rename… pushes nothing when the prompt is cancelled', async () => {
    const item = itemsFor('project', { ctxId: '7', ctxName: 'eits-web' }, false).find((i) => i.label === 'Rename…')
    const c = mockCtx()
    await item.run(c)
    expect(c.calls.push).toEqual([])
  })

  it('Copy project path copies data-ctx-path', () => {
    expect(run('project', { ctxId: '7', ctxPath: '/Users/x/proj' }, 'Copy project path').copy).toEqual([
      '/Users/x/proj',
    ])
  })

  it('project Delete pushes delete_project keyed on project_id', () => {
    expect(run('project', { ctxId: '7' }, 'Delete project').push).toEqual([['delete_project', { project_id: '7' }]])
  })

  it('Open in New Window is tauri-only for projects', () => {
    const web = itemsFor('project', { ctxId: '7' }, false)
    const app = itemsFor('project', { ctxId: '7' }, true)
    expect(web.some((i) => i.label === 'Open in New Window')).toBe(false)
    expect(app.some((i) => i.label === 'Open in New Window')).toBe(true)
  })

  it('file: directories have no Open/Open-in-editor/Rename, files do', () => {
    const dir = itemsFor('file', { ctxPath: 'src', ctxIsDir: 'true' }, false)
    const file = itemsFor('file', { ctxPath: 'src/app.js', ctxIsDir: undefined }, false)
    expect(dir.some((i) => i.label === 'Open')).toBe(false)
    expect(dir.some((i) => i.label === 'Open in External Editor')).toBe(false)
    expect(dir.some((i) => i.label === 'Rename…')).toBe(false)
    expect(file.some((i) => i.label === 'Open')).toBe(true)
    expect(file.some((i) => i.label === 'Open in External Editor')).toBe(true)
    expect(file.some((i) => i.label === 'Rename…')).toBe(true)
  })

  it('file Open pushes file_open keyed on relative path', () => {
    expect(run('file', { ctxPath: 'src/app.js' }, 'Open').push).toEqual([['file_open', { path: 'src/app.js' }]])
  })

  it('file Copy path copies the absolute path, Copy relative path copies the relative one', () => {
    const dataset = { ctxPath: 'src/app.js', ctxAbsPath: '/proj/src/app.js' }
    expect(run('file', dataset, 'Copy path').copy).toEqual(['/proj/src/app.js'])
    expect(run('file', dataset, 'Copy relative path').copy).toEqual(['src/app.js'])
  })

  it('file Rename… awaits the prompt then pushes rename_file', async () => {
    const item = itemsFor('file', { ctxPath: 'src/app.js', ctxName: 'app.js' }, false).find(
      (i) => i.label === 'Rename…'
    )
    const c = mockCtx()
    c.prompt = async () => 'app2.js'
    await item.run(c)
    expect(c.calls.push).toEqual([['rename_file', { path: 'src/app.js', name: 'app2.js' }]])
  })

  it('directory Reveal in Finder pushes reveal_file keyed on its own path', () => {
    expect(run('file', { ctxPath: 'src', ctxIsDir: 'true' }, 'Reveal in Finder').push).toEqual([
      ['reveal_file', { path: 'src' }],
    ])
  })

  it('definition_file: directory-backed skills have no Duplicate/Delete, bare files do', () => {
    const dirBacked = itemsFor('definition_file', { ctxAbsPath: '/s/SKILL.md', ctxIsDir: 'true' }, false)
    const bareFile = itemsFor('definition_file', { ctxAbsPath: '/a/reviewer.md', ctxIsDir: undefined }, false)
    expect(dirBacked.some((i) => i.label === 'Duplicate')).toBe(false)
    expect(dirBacked.some((i) => i.label === 'Delete')).toBe(false)
    expect(bareFile.some((i) => i.label === 'Duplicate')).toBe(true)
    expect(bareFile.some((i) => i.label === 'Delete')).toBe(true)
    // Edit/Export are present regardless of dir-backing
    expect(dirBacked.some((i) => i.label === 'Edit')).toBe(true)
    expect(dirBacked.some((i) => i.label === 'Export/Copy config')).toBe(true)
  })

  it('definition_file Edit pushes open_in_editor with the dataset editor + abs path', () => {
    expect(
      run('definition_file', { ctxAbsPath: '/a/reviewer.md', ctxEditor: 'code' }, 'Edit').push
    ).toEqual([['open_in_editor', { editor: 'code', path: '/a/reviewer.md' }]])
  })

  it('definition_file Export/Copy config copies the full raw content', () => {
    expect(run('definition_file', { ctxAbsPath: '/a/reviewer.md', ctxContent: '---\nname: x\n---' }, 'Export/Copy config').copy).toEqual([
      '---\nname: x\n---',
    ])
  })

  it('definition_file Duplicate/Delete push keyed on abs path', () => {
    const dataset = { ctxAbsPath: '/a/reviewer.md' }
    expect(run('definition_file', dataset, 'Duplicate').push).toEqual([
      ['duplicate_definition_file', { path: '/a/reviewer.md' }],
    ])
    expect(run('definition_file', dataset, 'Delete').push).toEqual([
      ['delete_definition_file', { path: '/a/reviewer.md' }],
    ])
  })

  it('channel Open navigates to /chat?channel_id=', () => {
    expect(run('channel', { ctxId: '5' }, 'Open').navigate).toEqual(['/chat?channel_id=5'])
  })

  it('channel Rename… awaits the prompt then pushes rename_channel', async () => {
    const item = itemsFor('channel', { ctxId: '5', ctxName: 'general' }, false).find((i) => i.label === 'Rename…')
    const c = mockCtx()
    c.prompt = async () => 'renamed'
    await item.run(c)
    expect(c.calls.push).toEqual([['rename_channel', { channel_id: '5', name: 'renamed' }]])
  })

  it('channel Delete pushes delete_channel keyed on channel_id', () => {
    expect(run('channel', { ctxId: '5' }, 'Delete channel').push).toEqual([['delete_channel', { channel_id: '5' }]])
  })

  it('team Open navigates to the precomputed ctx path', () => {
    expect(run('team', { ctxId: '9', ctxPath: '/projects/1/teams/9' }, 'Open').navigate).toEqual([
      '/projects/1/teams/9',
    ])
  })

  it('team Delete pushes delete_team keyed on id', () => {
    expect(run('team', { ctxId: '9' }, 'Delete team').push).toEqual([['delete_team', { id: '9' }]])
  })

  it('prompt: Open full editor only appears when ctxPath is present', () => {
    const withPath = itemsFor('prompt', { ctxId: '1', ctxUuid: 'u1', ctxPath: '/projects/1/prompts/u1' }, false)
    const withoutPath = itemsFor('prompt', { ctxId: '1', ctxUuid: 'u1' }, false)
    expect(withPath.some((i) => i.label === 'Open full editor')).toBe(true)
    expect(withoutPath.some((i) => i.label === 'Open full editor')).toBe(false)
  })

  it('prompt Open pushes select_prompt with both id and uuid', () => {
    expect(run('prompt', { ctxId: '1', ctxUuid: 'u1' }, 'Open').push).toEqual([
      ['select_prompt', { id: '1', uuid: 'u1' }],
    ])
  })

  it('prompt Copy slug copies data-ctx-slug', () => {
    expect(run('prompt', { ctxUuid: 'u1', ctxSlug: 'my-prompt' }, 'Copy slug').copy).toEqual(['my-prompt'])
  })

  it('prompt Duplicate/Deactivate push keyed on uuid', () => {
    const dataset = { ctxUuid: 'u1' }
    expect(run('prompt', dataset, 'Duplicate').push).toEqual([['duplicate_prompt', { uuid: 'u1' }]])
    expect(run('prompt', dataset, 'Deactivate').push).toEqual([['deactivate_prompt', { uuid: 'u1' }]])
  })

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
    expect(run('session', S, 'Copy deeplink').copy).toEqual(['eits://dm/uuid-abc'])
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
