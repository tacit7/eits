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
  beforeEach(() => {
    document.body.innerHTML = '<dialog id="command-palette"></dialog>'
  })

  afterEach(() => {
    vi.restoreAllMocks()
    document.body.innerHTML = ''
  })

  it('opens the project picker for Space p p', () => {
    const hook = mountHook()
    const palette = document.querySelector('#command-palette')
    const handler = vi.fn()
    palette.addEventListener('palette:open-command', handler)

    keydown(' ')
    keydown('p')
    keydown('p')

    expect(handler).toHaveBeenCalledOnce()
    expect(handler.mock.calls[0][0].detail).toEqual({ commandId: 'go-project' })

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
    expect(handler.mock.calls[0][0].detail).toEqual({ commandId: 'go-project' })

    hook.destroyed()
  })
})
