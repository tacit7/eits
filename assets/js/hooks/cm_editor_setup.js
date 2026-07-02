// Shared CodeMirror bootstrap helpers used by NoteEditorHook and NoteFullEditorHook.
// Lazy imports are preserved so the CM bundle stays out of the initial chunk.

export async function loadCMModulesAndCompartments() {
  const [
    viewModule,
    { EditorState },
    { defaultKeymap, history, historyKeymap },
    { makeThemeCompartment },
    { makeTabSizeExtension, makeFontSizeExtension, makeVimExtension },
    { syntaxHighlighting, defaultHighlightStyle },
    { markdown },
  ] = await Promise.all([
    import("@codemirror/view"),
    import("@codemirror/state"),
    import("@codemirror/commands"),
    import("../cm_theme"),
    import("../cm_settings"),
    import("@codemirror/language"),
    import("@codemirror/lang-markdown"),
  ])

  const { EditorView, keymap, highlightActiveLine, lineNumbers } = viewModule

  const { extension: themeExtension, watch } = await makeThemeCompartment()
  const { extension: tabExtension, watch: tabWatch } = await makeTabSizeExtension()
  const { extension: fontExtension, watch: watchFont } = await makeFontSizeExtension()
  const { extension: vimExtension, watch: watchVim } = await makeVimExtension()

  return {
    EditorView, keymap, highlightActiveLine, lineNumbers,
    EditorState, defaultKeymap, history, historyKeymap,
    syntaxHighlighting, defaultHighlightStyle, markdown,
    themeExtension, tabExtension, fontExtension, vimExtension,
    watch, tabWatch, watchFont, watchVim,
  }
}

export function mountCMView(hook, { EditorState, EditorView, doc, extensions, watch, tabWatch, watchFont, watchVim }) {
  const state = EditorState.create({ doc, extensions })
  hook._view = new EditorView({ state, parent: hook.el })
  hook._cleanupTheme = watch(hook._view)
  hook._cleanupTabSize = tabWatch(hook._view)
  hook._cleanupFontSize = watchFont(hook._view)
  hook._cleanupVim = watchVim(hook._view)
}

export function destroyCMView(hook) {
  if (hook._cleanupTheme) hook._cleanupTheme()
  if (hook._cleanupTabSize) hook._cleanupTabSize()
  if (hook._cleanupFontSize) hook._cleanupFontSize()
  if (hook._cleanupVim) hook._cleanupVim()
  if (hook._view) {
    hook._view.destroy()
    hook._view = null
  }
}
