// Tests for CommandPalette.openCommand (palette:open-command event handler).
//
// vi.mock is hoisted before imports, so './palette_commands/index.js' is
// replaced with a factory stub before CommandPalette loads it. Each test
// sets getCommands.mockReturnValue([...]) to control which commands are
// visible, then calls the REAL hook.openCommand — no implementation
// is duplicated here.

import { describe, it, expect, beforeEach, vi } from 'vitest'

vi.mock('./palette_commands/index.js', () => ({
  getCommands: vi.fn(() => []),
}))

import { CommandPalette } from './command_palette.js'
import { getCommands } from './palette_commands/index.js'

// jsdom does not implement scrollIntoView
beforeEach(() => {
  HTMLElement.prototype.scrollIntoView = vi.fn()
  vi.clearAllMocks()
})

// ---------------------------------------------------------------------------
// Fixture commands
// ---------------------------------------------------------------------------

const canvasAddCmd = {
  id: 'canvas-add-session',
  label: 'Add Session to Canvas...',
  type: 'submenu',
  when: () => true,
  commands: () => Promise.resolve([]),
}

const hiddenCmd = {
  id: 'hidden-cmd',
  label: 'Hidden',
  type: 'callback',
  when: () => false,
  fn: vi.fn(),
}

// ---------------------------------------------------------------------------
// Helper — minimal hook wired to the real CommandPalette prototype
// ---------------------------------------------------------------------------

function makeHook() {
  const el = document.createElement('dialog')
  el.showModal = vi.fn()
  el.close = vi.fn()

  const input = document.createElement('input')
  const results = document.createElement('div')

  const hook = Object.create(CommandPalette)
  hook.el = el
  hook.input = input
  hook.results = results
  hook.stack = []
  hook.activeIndex = 0
  hook.visibleItems = []

  // Stub render/updateBreadcrumb — not under test here
  hook.render = vi.fn()
  hook.updateBreadcrumb = vi.fn()

  // Spy on activate so we can assert call args without triggering DOM mutations
  vi.spyOn(hook, 'activate').mockImplementation(async (cmd) => {
    if (cmd.type === 'submenu') {
      hook.stack.push({ id: cmd.id, label: cmd.label, commands: [] })
    }
  })

  return hook
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

describe('CommandPalette.openCommand — real implementation', () => {
  it('falls back to open() when commandId is undefined', async () => {
    getCommands.mockReturnValue([canvasAddCmd])
    const hook = makeHook()
    vi.spyOn(hook, 'open')

    await hook.openCommand(undefined)

    expect(hook.open).toHaveBeenCalledOnce()
    expect(hook.activate).not.toHaveBeenCalled()
    // getCommands should NOT be called — early return before it
    expect(getCommands).not.toHaveBeenCalled()
  })

  it('falls back to open() when commandId is null', async () => {
    getCommands.mockReturnValue([canvasAddCmd])
    const hook = makeHook()
    vi.spyOn(hook, 'open')

    await hook.openCommand(null)

    expect(hook.open).toHaveBeenCalledOnce()
    expect(hook.activate).not.toHaveBeenCalled()
    expect(getCommands).not.toHaveBeenCalled()
  })

  it('calls open() then activate() with the matching command', async () => {
    getCommands.mockReturnValue([canvasAddCmd])
    const hook = makeHook()
    vi.spyOn(hook, 'open')

    await hook.openCommand('canvas-add-session')

    expect(hook.open).toHaveBeenCalledOnce()
    expect(getCommands).toHaveBeenCalledWith(hook)
    expect(hook.activate).toHaveBeenCalledWith(canvasAddCmd)
  })

  it('calls open() but skips activate() when commandId has no match', async () => {
    getCommands.mockReturnValue([canvasAddCmd])
    const hook = makeHook()
    vi.spyOn(hook, 'open')

    await hook.openCommand('nonexistent-command')

    expect(hook.open).toHaveBeenCalledOnce()
    expect(getCommands).toHaveBeenCalledWith(hook)
    expect(hook.activate).not.toHaveBeenCalled()
  })

  it('skips activate() for a command whose when() returns false', async () => {
    getCommands.mockReturnValue([hiddenCmd])
    const hook = makeHook()
    vi.spyOn(hook, 'open')

    await hook.openCommand('hidden-cmd')

    expect(hook.open).toHaveBeenCalledOnce()
    expect(hook.activate).not.toHaveBeenCalled()
  })

  it('submenu activate pushes onto the stack', async () => {
    getCommands.mockReturnValue([canvasAddCmd])
    const hook = makeHook()
    vi.spyOn(hook, 'open')

    expect(hook.stack).toHaveLength(0)
    await hook.openCommand('canvas-add-session')
    expect(hook.stack).toHaveLength(1)
    expect(hook.stack[0].id).toBe('canvas-add-session')
  })

  it('passes the hook instance to getCommands (required for pushEvent context)', async () => {
    getCommands.mockReturnValue([])
    const hook = makeHook()
    vi.spyOn(hook, 'open')

    await hook.openCommand('canvas-add-session')

    expect(getCommands).toHaveBeenCalledWith(hook)
  })
})
