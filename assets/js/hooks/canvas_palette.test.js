import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest'
import { canvasCommands } from './palette_commands/canvas.js'
import { CanvasPanHook } from './canvas_pan_hook.js'

// ---------------------------------------------------------------------------
// canvasCommands — palette command visibility and session mapping
// ---------------------------------------------------------------------------

describe('canvasCommands', () => {
  let hook

  beforeEach(() => {
    hook = {
      pushEvent: vi.fn(),
      _paletteSessionsResolve: null,
    }
  })

  it('returns exactly one command', () => {
    const cmds = canvasCommands(hook)
    expect(cmds).toHaveLength(1)
    expect(cmds[0].id).toBe('canvas-add-session')
  })

  it('when() returns true only on /canvases/:id paths', () => {
    const [cmd] = canvasCommands(hook)

    // Paths that should show the command
    const showPaths = ['/canvases/1', '/canvases/42', '/canvases/1?foo=bar']
    for (const path of showPaths) {
      Object.defineProperty(window, 'location', {
        value: { pathname: path },
        writable: true,
        configurable: true,
      })
      expect(cmd.when()).toBe(true)
    }

    // Paths that should hide the command
    const hidePaths = ['/', '/sessions', '/canvases', '/tasks']
    for (const path of hidePaths) {
      Object.defineProperty(window, 'location', {
        value: { pathname: path },
        writable: true,
        configurable: true,
      })
      expect(cmd.when()).toBe(false)
    }
  })

  it('commands() is type submenu and returns a Promise', () => {
    const [cmd] = canvasCommands(hook)
    expect(cmd.type).toBe('submenu')
    const result = cmd.commands()
    expect(result).toBeInstanceOf(Promise)
  })

  it('commands() pushes palette:sessions event with null project_id', () => {
    const [cmd] = canvasCommands(hook)
    cmd.commands()
    expect(hook.pushEvent).toHaveBeenCalledWith('palette:sessions', { project_id: null })
  })

  it('commands() maps sessions to callback items that dispatch canvas:add-session', async () => {
    const [cmd] = canvasCommands(hook)

    const sessions = [
      { id: 10, uuid: 'abc-123', name: 'My Agent', description: null, status: 'working' },
      { id: 20, uuid: 'def-456', name: null, description: 'unnamed', status: 'stopped' },
    ]

    const pendingCommands = cmd.commands()
    // Resolve the pending promise as the server would
    hook._paletteSessionsResolve(sessions)

    const commands = await pendingCommands

    expect(commands).toHaveLength(2)
    expect(commands[0].type).toBe('callback')
    expect(commands[0].label).toBe('My Agent')
    expect(commands[1].label).toBe('unnamed')

    // Verify fn dispatches canvas:add-session with the right sessionId
    const dispatched = []
    const listener = (e) => dispatched.push(e.detail)
    window.addEventListener('canvas:add-session', listener)

    commands[0].fn()
    expect(dispatched).toHaveLength(1)
    expect(dispatched[0].sessionId).toBe(10)

    commands[1].fn()
    expect(dispatched[1].sessionId).toBe(20)

    window.removeEventListener('canvas:add-session', listener)
  })

  it('commands() resolves to empty array when hook is null', async () => {
    const [cmd] = canvasCommands(null)
    const result = await cmd.commands()
    expect(result).toEqual([])
  })
})

// ---------------------------------------------------------------------------
// CanvasPanHook — canvas:add-session bridges to pushEvent
// ---------------------------------------------------------------------------

describe('CanvasPanHook canvas:add-session', () => {
  let hook

  beforeEach(() => {
    hook = Object.create(CanvasPanHook)
    hook.el = document.createElement('div')
    hook.pushEvent = vi.fn()
    hook.mounted()
  })

  afterEach(() => {
    hook.destroyed()
  })

  it('calls pushEvent("pick_session") with string session-id on canvas:add-session', () => {
    window.dispatchEvent(
      new CustomEvent('canvas:add-session', { detail: { sessionId: 42 } })
    )
    expect(hook.pushEvent).toHaveBeenCalledWith('pick_session', { 'session-id': '42' })
  })

  it('does not call pushEvent when detail is missing sessionId', () => {
    window.dispatchEvent(new CustomEvent('canvas:add-session', { detail: {} }))
    expect(hook.pushEvent).not.toHaveBeenCalled()
  })

  it('does not call pushEvent after destroyed()', () => {
    hook.destroyed()
    window.dispatchEvent(
      new CustomEvent('canvas:add-session', { detail: { sessionId: 99 } })
    )
    expect(hook.pushEvent).not.toHaveBeenCalled()
  })
})
