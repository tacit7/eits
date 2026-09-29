import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest'
import { GlobalKeydown } from './global_keydown.js'

function keydown(key, attrs = {}) {
  window.dispatchEvent(new KeyboardEvent('keydown', {
    key,
    code: key === ' ' ? 'Space' : `Key${key.toUpperCase()}`,
    bubbles: true,
    cancelable: true,
    ...attrs,
  }))
}

function mountHook() {
  const hook = Object.create(GlobalKeydown)
  hook.el = document.createElement('div')
  hook.mounted()
  return hook
}

describe('GlobalKeydown leader shortcuts', () => {
  const originalLocation = window.location

  beforeEach(() => {
    document.body.innerHTML = '<dialog id="command-palette"></dialog>'
    localStorage.clear()

    delete window.location
    window.location = {
      pathname: '/',
      assign: vi.fn(),
    }
  })

  afterEach(() => {
    hookCleanup()
    window.location = originalLocation
    vi.restoreAllMocks()
    document.body.innerHTML = ''
  })

  function hookCleanup() {
    window.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape' }))
  }

  it('opens the project picker for Space p p', () => {
    const hook = mountHook()
    const palette = document.querySelector('#command-palette')
    const handler = vi.fn()
    palette.addEventListener('palette:open-command', handler)

    keydown(' ')
    keydown('p')
    keydown('p')

    expect(handler).toHaveBeenCalledOnce()
    expect(handler.mock.calls[0][0].detail).toEqual({ commandId: 'list-projects' })

    hook.destroyed()
  })

  it('keeps the documented Space t p project picker shortcut working', () => {
    const hook = mountHook()
    const palette = document.querySelector('#command-palette')
    const handler = vi.fn()
    palette.addEventListener('palette:open-command', handler)

    keydown(' ')
    keydown('t')
    keydown('p')

    expect(handler).toHaveBeenCalledOnce()
    expect(handler.mock.calls[0][0].detail).toEqual({ commandId: 'list-projects' })

    hook.destroyed()
  })

  it('opens current project tasks for Space g t on project routes', () => {
    const hook = mountHook()
    window.location.pathname = '/projects/42/sessions'

    keydown(' ')
    keydown('g')
    keydown('t')

    expect(window.location.assign).toHaveBeenCalledOnce()
    expect(window.location.assign).toHaveBeenCalledWith('/projects/42/tasks')

    hook.destroyed()
  })

  it('opens selected project tasks for Space g t from workspace routes', () => {
    const hook = mountHook()
    window.location.pathname = '/sessions'
    localStorage.setItem('rail_state', JSON.stringify({ project_id: 7 }))

    keydown(' ')
    keydown('g')
    keydown('t')

    expect(window.location.assign).toHaveBeenCalledOnce()
    expect(window.location.assign).toHaveBeenCalledWith('/projects/7/tasks')

    hook.destroyed()
  })

  it('falls back to workspace tasks for Space g t with no selected project', () => {
    const hook = mountHook()

    keydown(' ')
    keydown('g')
    keydown('t')

    expect(window.location.assign).toHaveBeenCalledOnce()
    expect(window.location.assign).toHaveBeenCalledWith('/tasks')

    hook.destroyed()
  })
})
