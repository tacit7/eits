import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest'
import { SlashCommandPopup } from './slash_command_popup.js'

function makeCtx(overrides = {}) {
  const form = document.createElement('form')
  form.style.position = 'relative'
  document.body.appendChild(form)

  const el = document.createElement('textarea')
  form.appendChild(el)

  const popup = document.createElement('div')
  popup.className = 'hidden'
  form.appendChild(popup)

  const ctx = {
    el,
    popup,
    slashItems: [],
    slashFiltered: [],
    slashOrdered: [],
    slashIndex: 0,
    slashOpen: false,
    slashTriggerPos: -1,
    slashTriggerChar: '/',
    fileMode: false,
    _fileRoot: 'project',
    fileRequestSeq: 0,
    _fileDebounceTimer: null,
    pushEventCalls: [],
    pushEvent(name, payload, cb) {
      this.pushEventCalls.push({ name, payload, cb })
    },
    enumAC: { handleSelect: () => false, close: () => {}, checkEnumContext: () => {} },
    slashFilter: vi.fn(),
    slashClose: vi.fn(),
    autoResize: vi.fn(),
    ...overrides,
  }

  // Bind the methods under test from SlashCommandPopup
  ctx.startFileAutocomplete = SlashCommandPopup.startFileAutocomplete.bind(ctx)
  ctx.renderFilePopup = SlashCommandPopup.renderFilePopup.bind(ctx)
  ctx._fileSelect = SlashCommandPopup._fileSelect.bind(ctx)
  ctx._updateFileActive = SlashCommandPopup._updateFileActive.bind(ctx)
  ctx.checkSlashTrigger = SlashCommandPopup.checkSlashTrigger.bind(ctx)
  ctx.slashSelect = SlashCommandPopup.slashSelect.bind(ctx)

  return ctx
}

describe('checkSlashTrigger — @@ agent trigger', () => {
  let ctx
  beforeEach(() => {
    document.body.innerHTML = ''
    ctx = makeCtx()
  })

  it('detects @@ at start of input', () => {
    ctx.el.value = '@@claude'
    ctx.el.setSelectionRange(8, 8)
    ctx.checkSlashTrigger()
    expect(ctx.slashFilter).toHaveBeenCalledWith('claude', 'agent')
    expect(ctx.fileMode).toBe(false)
  })

  it('detects @@ after space', () => {
    ctx.el.value = 'hello @@my-agent'
    ctx.el.setSelectionRange(16, 16)
    ctx.checkSlashTrigger()
    expect(ctx.slashFilter).toHaveBeenCalledWith('my-agent', 'agent')
  })

  it('sets slashTriggerPos to position of first @', () => {
    ctx.el.value = 'hello @@claude'
    ctx.el.setSelectionRange(14, 14)
    ctx.checkSlashTrigger()
    // "hello " = 6 chars, first @ at index 6
    expect(ctx.slashTriggerPos).toBe(6)
  })
})

describe('checkSlashTrigger — @ file trigger', () => {
  let ctx
  beforeEach(() => {
    document.body.innerHTML = ''
    ctx = makeCtx()
    ctx.startFileAutocomplete = vi.fn()
  })

  it('detects @ project-root trigger', () => {
    ctx.el.value = '@src/foo'
    ctx.el.setSelectionRange(8, 8)
    ctx.checkSlashTrigger()
    expect(ctx.startFileAutocomplete).toHaveBeenCalledWith('src/foo', 'project')
    expect(ctx.fileMode).toBe(true)
    expect(ctx._fileRoot).toBe('project')
  })

  it('detects @~/ as home root', () => {
    ctx.el.value = '@~/Documents/f'
    ctx.el.setSelectionRange(14, 14)
    ctx.checkSlashTrigger()
    expect(ctx.startFileAutocomplete).toHaveBeenCalledWith('Documents/f', 'home')
    expect(ctx._fileRoot).toBe('home')
  })

  it('detects @/ as filesystem root', () => {
    ctx.el.value = '@/etc/h'
    ctx.el.setSelectionRange(7, 7)
    ctx.checkSlashTrigger()
    expect(ctx.startFileAutocomplete).toHaveBeenCalledWith('etc/h', 'filesystem')
    expect(ctx._fileRoot).toBe('filesystem')
  })

  it('does not trigger @ file when @@ matches', () => {
    ctx.el.value = '@@claude'
    ctx.el.setSelectionRange(8, 8)
    ctx.checkSlashTrigger()
    expect(ctx.slashFilter).toHaveBeenCalledWith('claude', 'agent')
    expect(ctx.startFileAutocomplete).not.toHaveBeenCalled()
  })

  it('sets slashTriggerPos to position of @', () => {
    ctx.el.value = 'send @src/f'
    ctx.el.setSelectionRange(11, 11)
    ctx.checkSlashTrigger()
    // "send " = 5 chars, @ at index 5
    expect(ctx.slashTriggerPos).toBe(5)
  })
})

describe('renderFilePopup', () => {
  let ctx
  beforeEach(() => {
    document.body.innerHTML = ''
    ctx = makeCtx()
  })

  it('shows empty state when no entries', () => {
    ctx.renderFilePopup([], false)
    expect(ctx.popup.textContent).toContain('No matching files')
    expect(ctx.slashOpen).toBe(true)
    expect(ctx.slashOrdered).toEqual([])
  })

  it('renders entries and sets slashOrdered', () => {
    const entries = [
      { name: 'components', path: 'src/components/', insert_text: '@src/components/', is_dir: true },
      { name: 'router.ex', path: 'src/router.ex', insert_text: '@src/router.ex', is_dir: false },
    ]
    ctx.renderFilePopup(entries, false)
    expect(ctx.slashOrdered).toHaveLength(2)
    expect(ctx.slashOpen).toBe(true)
    expect(ctx.popup.classList.contains('hidden')).toBe(false)
  })

  it('shows truncated footer when truncated', () => {
    const entries = [
      { name: 'foo.ex', path: 'foo.ex', insert_text: '@foo.ex', is_dir: false }
    ]
    ctx.renderFilePopup(entries, true)
    expect(ctx.popup.textContent).toContain('Showing first 50')
  })

  it('does not show truncated footer when not truncated', () => {
    const entries = [
      { name: 'foo.ex', path: 'foo.ex', insert_text: '@foo.ex', is_dir: false }
    ]
    ctx.renderFilePopup(entries, false)
    expect(ctx.popup.textContent).not.toContain('Showing first 50')
  })
})

describe('startFileAutocomplete — list_files pushEvent payload and debounce', () => {
  let ctx
  beforeEach(() => {
    vi.useFakeTimers()
    document.body.innerHTML = ''
    ctx = makeCtx()
    // use the real startFileAutocomplete (already bound in makeCtx)
  })

  afterEach(() => {
    vi.useRealTimers()
  })

  it('emits list_files with correct root and partial after debounce', () => {
    ctx.el.value = '@src/comp'
    ctx.el.setSelectionRange(9, 9)
    ctx.checkSlashTrigger()

    // debounce not elapsed yet — no pushEvent
    expect(ctx.pushEventCalls).toHaveLength(0)

    vi.advanceTimersByTime(150)

    expect(ctx.pushEventCalls).toHaveLength(1)
    const call = ctx.pushEventCalls[0]
    expect(call.name).toBe('list_files')
    expect(call.payload.root).toBe('project')
    expect(call.payload.partial).toBe('src/comp')
  })
})

describe('startFileAutocomplete — stale-reply guard (fileRequestSeq)', () => {
  let ctx
  beforeEach(() => {
    vi.useFakeTimers()
    document.body.innerHTML = ''
    ctx = makeCtx()
  })

  afterEach(() => {
    vi.useRealTimers()
  })

  it('ignores stale reply when a newer request is in flight', () => {
    // First request: @foo
    ctx.el.value = '@foo'
    ctx.el.setSelectionRange(4, 4)
    ctx.checkSlashTrigger()
    vi.advanceTimersByTime(150)

    // First callback captured
    expect(ctx.pushEventCalls).toHaveLength(1)
    const firstCb = ctx.pushEventCalls[0].cb

    // Second request: @bar — increments fileRequestSeq
    ctx.el.value = '@bar'
    ctx.el.setSelectionRange(4, 4)
    ctx.checkSlashTrigger()
    vi.advanceTimersByTime(150)

    expect(ctx.pushEventCalls).toHaveLength(2)
    const secondCb = ctx.pushEventCalls[1].cb

    // Stale (first) callback fires — should be a no-op
    const staleEntries = [
      { name: 'foo.ex', path: 'foo.ex', insert_text: '@foo.ex', is_dir: false }
    ]
    firstCb({ entries: staleEntries, truncated: false })

    // Popup should not show stale entries
    expect(ctx.slashOpen).toBe(false)
    expect(ctx.slashOrdered).toHaveLength(0)

    // Fresh (second) callback fires — should render
    const freshEntries = [
      { name: 'bar.ex', path: 'bar.ex', insert_text: '@bar.ex', is_dir: false }
    ]
    secondCb({ entries: freshEntries, truncated: false })

    expect(ctx.slashOpen).toBe(true)
    expect(ctx.slashOrdered).toHaveLength(1)
    expect(ctx.slashOrdered[0].name).toBe('bar.ex')
  })
})

describe('_fileSelect', () => {
  let ctx
  beforeEach(() => {
    document.body.innerHTML = ''
    ctx = makeCtx()
  })

  it('inserts insert_text for a file and closes popup', () => {
    ctx.el.value = 'hello @src/r'
    ctx.el.setSelectionRange(12, 12)
    ctx.slashTriggerPos = 6
    ctx.slashOrdered = [
      { name: 'router.ex', path: 'src/router.ex', insert_text: '@src/router.ex', is_dir: false }
    ]
    ctx.slashIndex = 0
    ctx._fileSelect()
    expect(ctx.el.value).toBe('hello @src/router.ex')
    expect(ctx.slashClose).toHaveBeenCalled()
  })

  it('inserts insert_text for a directory and fires input event (no close)', () => {
    ctx.el.value = '@src'
    ctx.el.setSelectionRange(4, 4)
    ctx.slashTriggerPos = 0
    ctx.slashOrdered = [
      { name: 'src', path: 'src/', insert_text: '@src/', is_dir: true }
    ]
    ctx.slashIndex = 0

    const inputEvents = []
    ctx.el.addEventListener('input', (e) => inputEvents.push(e))

    ctx._fileSelect()
    expect(ctx.el.value).toBe('@src/')
    expect(ctx.slashClose).not.toHaveBeenCalled()
    expect(inputEvents).toHaveLength(1)
  })

  it('does nothing when slashOrdered is empty', () => {
    ctx.slashOrdered = []
    ctx.slashIndex = 0
    ctx._fileSelect()
    expect(ctx.slashClose).not.toHaveBeenCalled()
  })

  it('places cursor after inserted text', () => {
    ctx.el.value = '@src'
    ctx.el.setSelectionRange(4, 4)
    ctx.slashTriggerPos = 0
    ctx.slashOrdered = [
      { name: 'router.ex', path: 'src/router.ex', insert_text: '@src/router.ex', is_dir: false }
    ]
    ctx.slashIndex = 0
    ctx._fileSelect()
    expect(ctx.el.selectionStart).toBe('@src/router.ex'.length)
  })
})
