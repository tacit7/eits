import { describe, it, expect, beforeEach } from 'vitest'
import { createEnumAutocomplete } from './enum_autocomplete.js'

function makeCtx(overrides = {}) {
  const popup = document.createElement('div')
  document.body.appendChild(popup)

  const el = document.createElement('textarea')
  document.body.appendChild(el)

  return {
    el,
    popup,
    slashItems: [],
    slashOrdered: [],
    slashIndex: 0,
    slashOpen: false,
    rowClass: () => 'row-class',
    highlightMatch: (text) => text,
    highlightRow: () => {},
    slashSelect: () => {},
    slashClose() {
      this.slashOpen = false
      this.slashOrdered = []
      popup.classList.add('hidden')
      popup.innerHTML = ''
    },
    autoResize: null,
    ...overrides,
  }
}

describe('createEnumAutocomplete', () => {
  let ctx, enumAC

  beforeEach(() => {
    document.body.innerHTML = ''
    ctx = makeCtx()
    enumAC = createEnumAutocomplete(ctx)
    // Wire up slashClose to call enumAC.close() like the real hook does
    const origClose = ctx.slashClose.bind(ctx)
    ctx.slashClose = function () { origClose(); enumAC.close() }
  })

  describe('checkEnumContext', () => {
    it('activates enum popup when cursor is after a flag with enum arg_type', () => {
      ctx.slashItems = [
        { slug: 'theme', type: 'flag', arg_type: { type: 'enum', values: ['dark', 'light', 'auto'] } },
      ]
      ctx.el.value = '/theme '
      ctx.el.selectionStart = 7

      // Override slashClose to track whether popup was opened (not closed)
      let closeCalled = false
      ctx.slashClose = function () { closeCalled = true; this.slashOpen = false }

      enumAC.checkEnumContext()

      expect(enumAC.isActive()).toBe(true)
      expect(ctx.slashOpen).toBe(true)
      expect(ctx.slashOrdered.length).toBe(3)
      expect(ctx.slashOrdered.map(i => i.slug)).toEqual(['dark', 'light', 'auto'])
    })

    it('filters enum values by partial input', () => {
      ctx.slashItems = [
        { slug: 'theme', type: 'flag', arg_type: { type: 'enum', values: ['dark', 'light', 'auto'] } },
      ]
      ctx.el.value = '/theme da'
      ctx.el.selectionStart = 9

      enumAC.checkEnumContext()

      expect(enumAC.isActive()).toBe(true)
      expect(ctx.slashOrdered.length).toBe(1)
      expect(ctx.slashOrdered[0].slug).toBe('dark')
    })

    it('does nothing when no flag matches', () => {
      ctx.slashItems = [
        { slug: 'help', type: 'command' },
      ]
      ctx.el.value = '/help '
      ctx.el.selectionStart = 6

      enumAC.checkEnumContext()

      expect(enumAC.isActive()).toBe(false)
    })

    it('does nothing when arg_type is not enum', () => {
      ctx.slashItems = [
        { slug: 'limit', type: 'flag', arg_type: 'integer' },
      ]
      ctx.el.value = '/limit '
      ctx.el.selectionStart = 7

      enumAC.checkEnumContext()

      expect(enumAC.isActive()).toBe(false)
    })

    it('closes popup when no enum values match partial', () => {
      let closeCalled = false
      ctx.slashClose = function () { closeCalled = true; this.slashOpen = false }
      ctx.slashItems = [
        { slug: 'theme', type: 'flag', arg_type: { type: 'enum', values: ['dark', 'light'] } },
      ]
      ctx.el.value = '/theme zzz'
      ctx.el.selectionStart = 10

      enumAC.checkEnumContext()

      expect(closeCalled).toBe(true)
      expect(enumAC.isActive()).toBe(false)
    })
  })

  describe('handleSelect', () => {
    it('returns false when not in enum mode', () => {
      expect(enumAC.handleSelect()).toBe(false)
    })

    it('inserts selected enum value and closes popup', () => {
      ctx.slashItems = [
        { slug: 'theme', type: 'flag', arg_type: { type: 'enum', values: ['dark', 'light', 'auto'] } },
      ]
      ctx.el.value = '/theme d'
      ctx.el.selectionStart = 8

      enumAC.checkEnumContext()
      expect(enumAC.isActive()).toBe(true)

      // Simulate selecting "dark" (index 0)
      ctx.slashIndex = 0
      const result = enumAC.handleSelect()

      expect(result).toBe(true)
      expect(ctx.el.value).toBe('/theme dark ')
      expect(ctx.el.selectionStart).toBe(12)
      expect(enumAC.isActive()).toBe(false)
    })

    it('preserves text after cursor when inserting', () => {
      ctx.slashItems = [
        { slug: 'theme', type: 'flag', arg_type: { type: 'enum', values: ['dark', 'light'] } },
      ]
      ctx.el.value = '/theme d some extra text'
      ctx.el.selectionStart = 8

      enumAC.checkEnumContext()
      ctx.slashIndex = 0
      enumAC.handleSelect()

      expect(ctx.el.value).toBe('/theme dark  some extra text')
    })
  })

  describe('close', () => {
    it('resets enum mode', () => {
      ctx.slashItems = [
        { slug: 'theme', type: 'flag', arg_type: { type: 'enum', values: ['dark'] } },
      ]
      ctx.el.value = '/theme '
      ctx.el.selectionStart = 7

      enumAC.checkEnumContext()
      expect(enumAC.isActive()).toBe(true)

      enumAC.close()
      expect(enumAC.isActive()).toBe(false)
    })
  })
})
