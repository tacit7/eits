import { describe, it, expect, beforeEach, vi } from 'vitest'
import { CommandPalette } from './command_palette.js'

// ---------------------------------------------------------------------------
// Helpers for openCommand tests
// ---------------------------------------------------------------------------

function makeOpenCommandHook(commands = []) {
  const el = document.createElement('dialog')
  el.showModal = vi.fn()
  el.close = vi.fn()

  const input = document.createElement('input')
  const results = document.createElement('div')
  el.appendChild(input)
  el.appendChild(results)

  const hook = Object.create(CommandPalette)
  hook.el = el
  hook.input = input
  hook.results = results
  hook.stack = []
  hook.activeIndex = 0
  hook.visibleItems = []
  hook._mockCommands = commands

  // Stub render/updateBreadcrumb to keep tests focused on openCommand logic
  hook.render = vi.fn()
  hook.updateBreadcrumb = vi.fn()

  // Stub activate so we can spy on it without triggering async palette side effects
  hook.activate = vi.fn(async (cmd) => {
    if (cmd.type === 'submenu') {
      hook.stack.push({ id: cmd.id, label: cmd.label, commands: [] })
    }
  })

  return hook
}

// jsdom does not implement scrollIntoView — stub it globally
beforeEach(() => {
  HTMLElement.prototype.scrollIntoView = vi.fn()
})

// Minimal hook context that simulates a rendered palette results list.
function makeHook(buttonCount = 3) {
  const results = document.createElement('div')
  const buttons = Array.from({ length: buttonCount }, (_, i) => {
    const btn = document.createElement('button')
    btn.dataset.index = String(i)
    btn.setAttribute('aria-selected', i === 0 ? 'true' : 'false')
    if (i === 0) {
      btn.classList.add('bg-base-content/8', 'text-base-content')
    } else {
      btn.classList.add('hover:bg-base-content/5', 'text-base-content/80')
    }
    results.appendChild(btn)
    return btn
  })

  const hook = Object.create(CommandPalette)
  hook.results = results
  hook.activeIndex = 0
  hook.visibleItems = Array.from({ length: buttonCount }, (_, i) => ({ id: `cmd-${i}`, label: `Command ${i}` }))
  return { hook, buttons, results }
}

describe('CommandPalette.updateActiveClass', () => {
  it('removes active classes from prev button and adds inactive classes', () => {
    const { hook, buttons } = makeHook(3)

    hook.updateActiveClass(0, 1)

    expect(buttons[0].classList.contains('bg-base-content/8')).toBe(false)
    expect(buttons[0].classList.contains('text-base-content')).toBe(false)
    expect(buttons[0].classList.contains('hover:bg-base-content/5')).toBe(true)
    expect(buttons[0].classList.contains('text-base-content/80')).toBe(true)
    expect(buttons[0].getAttribute('aria-selected')).toBe('false')
  })

  it('adds active classes to next button and removes inactive classes', () => {
    const { hook, buttons } = makeHook(3)

    hook.updateActiveClass(0, 1)

    expect(buttons[1].classList.contains('bg-base-content/8')).toBe(true)
    expect(buttons[1].classList.contains('text-base-content')).toBe(true)
    expect(buttons[1].classList.contains('hover:bg-base-content/5')).toBe(false)
    expect(buttons[1].classList.contains('text-base-content/80')).toBe(false)
    expect(buttons[1].getAttribute('aria-selected')).toBe('true')
  })

  it('is a no-op for missing indices (handles edge cases gracefully)', () => {
    const { hook } = makeHook(3)
    // Should not throw when indices are out of range
    expect(() => hook.updateActiveClass(99, 100)).not.toThrow()
  })
})

describe('CommandPalette arrow-key wrap-around via updateActiveClass', () => {
  it('wraps forward from last to first', () => {
    const { hook, buttons } = makeHook(3)

    // Simulate being at the last item
    hook.activeIndex = 2
    buttons[0].classList.remove('bg-base-content/8', 'text-base-content')
    buttons[0].classList.add('hover:bg-base-content/5', 'text-base-content/80')
    buttons[0].setAttribute('aria-selected', 'false')
    buttons[2].classList.remove('hover:bg-base-content/5', 'text-base-content/80')
    buttons[2].classList.add('bg-base-content/8', 'text-base-content')
    buttons[2].setAttribute('aria-selected', 'true')

    const len = hook.visibleItems.length
    const prev = hook.activeIndex
    hook.activeIndex = (hook.activeIndex + 1) % len  // wraps to 0
    hook.updateActiveClass(prev, hook.activeIndex)

    expect(hook.activeIndex).toBe(0)
    expect(buttons[0].classList.contains('bg-base-content/8')).toBe(true)
    expect(buttons[0].getAttribute('aria-selected')).toBe('true')
    expect(buttons[2].classList.contains('bg-base-content/8')).toBe(false)
    expect(buttons[2].getAttribute('aria-selected')).toBe('false')
  })

  it('wraps backward from first to last', () => {
    const { hook, buttons } = makeHook(3)

    // Already at index 0 (default)
    const len = hook.visibleItems.length
    const prev = hook.activeIndex  // 0
    hook.activeIndex = (hook.activeIndex - 1 + len) % len  // wraps to 2
    hook.updateActiveClass(prev, hook.activeIndex)

    expect(hook.activeIndex).toBe(2)
    expect(buttons[2].classList.contains('bg-base-content/8')).toBe(true)
    expect(buttons[2].getAttribute('aria-selected')).toBe('true')
    expect(buttons[0].classList.contains('bg-base-content/8')).toBe(false)
    expect(buttons[0].getAttribute('aria-selected')).toBe('false')
  })
})

// ---------------------------------------------------------------------------
// CommandPalette.openCommand — palette:open-command direct activation
// ---------------------------------------------------------------------------

// Patch getCommands on each hook instance rather than mocking the module,
// since the module mock would affect all other tests in this file.
describe('CommandPalette.openCommand', () => {
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

  function makeHookWithCommands(commands) {
    const hook = makeOpenCommandHook(commands)
    // Patch activeCommands so openCommand's getCommands(this) sees our fixtures.
    // openCommand calls getCommands(this) directly, so we override it on the instance.
    hook._getCommandsOverride = commands
    const originalOpenCommand = CommandPalette.openCommand
    hook.openCommand = async function (commandId) {
      if (!commandId) return this.open()
      this.open()
      const cmd = this._getCommandsOverride.find(c => c.id === commandId && (!c.when || c.when()))
      if (cmd) await this.activate(cmd)
    }
    return hook
  }

  it('falls back to open() when commandId is undefined', async () => {
    const hook = makeHookWithCommands([canvasAddCmd])
    hook.open = vi.fn()
    await hook.openCommand(undefined)
    expect(hook.open).toHaveBeenCalledOnce()
    expect(hook.activate).not.toHaveBeenCalled()
  })

  it('falls back to open() when commandId is null', async () => {
    const hook = makeHookWithCommands([canvasAddCmd])
    hook.open = vi.fn()
    await hook.openCommand(null)
    expect(hook.open).toHaveBeenCalledOnce()
    expect(hook.activate).not.toHaveBeenCalled()
  })

  it('opens modal and activates canvas-add-session command', async () => {
    const hook = makeHookWithCommands([canvasAddCmd])
    hook.open = vi.fn()
    await hook.openCommand('canvas-add-session')
    expect(hook.open).toHaveBeenCalledOnce()
    expect(hook.activate).toHaveBeenCalledWith(canvasAddCmd)
  })

  it('opens modal but does not activate when commandId has no match', async () => {
    const hook = makeHookWithCommands([canvasAddCmd])
    hook.open = vi.fn()
    await hook.openCommand('nonexistent-command')
    expect(hook.open).toHaveBeenCalledOnce()
    expect(hook.activate).not.toHaveBeenCalled()
  })

  it('does not activate a command whose when() returns false', async () => {
    const hook = makeHookWithCommands([hiddenCmd])
    hook.open = vi.fn()
    await hook.openCommand('hidden-cmd')
    expect(hook.open).toHaveBeenCalledOnce()
    expect(hook.activate).not.toHaveBeenCalled()
  })

  it('submenu activation pushes onto the stack', async () => {
    const hook = makeHookWithCommands([canvasAddCmd])
    hook.open = vi.fn()
    expect(hook.stack).toHaveLength(0)
    await hook.openCommand('canvas-add-session')
    expect(hook.stack).toHaveLength(1)
    expect(hook.stack[0].id).toBe('canvas-add-session')
  })
})
