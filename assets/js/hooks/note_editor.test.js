import { beforeEach, describe, expect, it, vi } from 'vitest'

vi.mock('./cm_editor_setup', () => ({
  loadCMModulesAndCompartments: vi.fn(async () => ({
    EditorView: { lineWrapping: {} },
    keymap: { of: vi.fn((bindings) => bindings) },
    highlightActiveLine: vi.fn(() => ({})),
    EditorState: {},
    defaultKeymap: [],
    history: vi.fn(() => ({})),
    historyKeymap: [],
    syntaxHighlighting: vi.fn(() => ({})),
    defaultHighlightStyle: {},
    markdown: vi.fn(() => ({})),
    themeExtension: {},
    tabExtension: {},
    fontExtension: {},
    vimExtension: {},
    watch: vi.fn(),
    tabWatch: vi.fn(),
    watchFont: vi.fn(),
    watchVim: vi.fn()
  })),
  mountCMView: vi.fn((hook) => {
    hook._view = { focus: vi.fn() }
  }),
  destroyCMView: vi.fn()
}))

describe('NoteEditorHook', () => {
  beforeEach(() => {
    document.body.innerHTML = ''
  })

  it('opens the eits disclosure wrapper when the inline editor mounts', async () => {
    const wrapper = document.createElement('div')
    wrapper.className = 'eits-disclosure'
    wrapper.innerHTML = `
      <input type="checkbox" />
      <div class="eits-disclosure__content">
        <div id="note-editor" data-note-id="42" data-body=""></div>
      </div>
    `
    document.body.appendChild(wrapper)

    const { NoteEditorHook } = await import('./note_editor')
    const hook = {
      ...NoteEditorHook,
      el: document.getElementById('note-editor'),
      pushEvent: vi.fn()
    }

    await hook.mounted()

    expect(wrapper.querySelector('input[type="checkbox"]').checked).toBe(true)
  })
})
