import { describe, it, expect, beforeEach } from 'vitest'
import { CommandPalette } from './command_palette.js'

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
