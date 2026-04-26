<script>
  import { onMount } from 'svelte'
  import CodeMirror from 'svelte-codemirror-editor'
  import { loadLanguage } from '../../js/cm_lang.js'

  export let live
  export let content = ''
  export let lang = ''
  export let path = ''
  export let hash = ''
  export let readonly = false

  let langExtension = null
  let themeExtension = null
  let settingsExtensions = []
  let tabSize = 2
  // editorValue tracks what is currently in the CM6 editor for save operations.
  // content (from LiveView) is passed directly to <CodeMirror value={content}> so
  // svelte-codemirror-editor calls setState when the server pushes a new version.
  // The old pattern of syncing value=content via a reactive reset editorValue on
  // every keystroke because Svelte 4 reactive statements depend on all referenced
  // variables — including value itself — so typing → value=newValue → reactive fires
  // → value=content (reset). That would mean save() always sent stale content.
  let editorValue = content
  let currentHash = hash
  let loadError = null

  $: if (hash !== currentHash && hash !== undefined) {
    currentHash = hash
  }

  async function loadTheme(appTheme) {
    switch (appTheme) {
      case 'dracula': {
        const { dracula } = await import('@uiw/codemirror-theme-dracula')
        return dracula
      }
      case 'tokyonight': {
        const { tokyoNight } = await import('@uiw/codemirror-theme-tokyo-night')
        return tokyoNight
      }
      case 'light': {
        const { eclipse } = await import('@uiw/codemirror-theme-eclipse')
        return eclipse
      }
      case 'autumn': {
        const { bespin } = await import('@uiw/codemirror-theme-bespin')
        return bespin
      }
      default: {
        const { oneDark } = await import('@codemirror/theme-one-dark')
        return oneDark
      }
    }
  }

  async function buildSettingsExtensions(size, fontSize, vimEnabled) {
    const [{ EditorView }, { EditorState }, { indentUnit }] = await Promise.all([
      import('@codemirror/view'),
      import('@codemirror/state'),
      import('@codemirror/language'),
    ])
    const exts = [
      EditorState.tabSize.of(size),
      indentUnit.of(' '.repeat(size)),
      EditorView.theme({
        "&": { fontSize: fontSize + 'px' },
        ".cm-scroller": { fontFamily: 'monospace' },
      }),
    ]
    if (vimEnabled) {
      const { vim } = await import('@replit/codemirror-vim')
      exts.push(vim())
    }
    return exts
  }

  onMount(() => {
    // onMount must be sync — async would return a Promise instead of a cleanup fn
    // and Svelte would skip listener teardown, leaking handlers across remounts.
    const onTheme = async ({ detail }) => {
      try { themeExtension = await loadTheme(detail.theme) } catch (_) {}
    }

    const onCmSettings = async ({ detail }) => {
      const size = parseInt(detail.cm_tab_size || document.documentElement.dataset.cmTabSize || '2', 10)
      const fontSize = detail.cm_font_size || document.documentElement.dataset.cmFontSize || '14'
      const vimEnabled = detail.cm_vim !== undefined
        ? detail.cm_vim === 'true'
        : document.documentElement.dataset.cmVim === 'true'
      tabSize = size
      settingsExtensions = await buildSettingsExtensions(size, fontSize, vimEnabled)
    }

    const onKeydown = (e) => {
      if ((e.metaKey || e.ctrlKey) && e.key === 's') {
        e.preventDefault()
        save()
      }
    }

    window.addEventListener('phx:apply_theme', onTheme)
    window.addEventListener('phx:apply_cm_settings', onCmSettings)
    window.addEventListener('keydown', onKeydown)

    // Async init runs in the background; cleanup is registered synchronously above.
    ;(async () => {
      const appTheme = document.documentElement.dataset.theme || 'dark'
      const ds = document.documentElement.dataset
      const initSize = parseInt(ds.cmTabSize || '2', 10)
      const initFont = ds.cmFontSize || '14'
      const initVim = ds.cmVim === 'true'

      tabSize = initSize
      try {
        ;[langExtension, themeExtension, settingsExtensions] = await Promise.all([
          loadLanguage(lang),
          loadTheme(appTheme),
          buildSettingsExtensions(initSize, initFont, initVim),
        ])
      } catch (err) {
        console.error('FileEditor: failed to load CodeMirror extensions:', err)
        loadError = 'Editor failed to load. Try refreshing.'
        // Attempt minimal fallback so the editor still renders
        try { themeExtension = await loadTheme('dark') } catch (_) { themeExtension = null }
        langExtension = null
        settingsExtensions = []
      }
    })()

    return () => {
      window.removeEventListener('phx:apply_theme', onTheme)
      window.removeEventListener('phx:apply_cm_settings', onCmSettings)
      window.removeEventListener('keydown', onKeydown)
    }
  })

  function handleChange(newValue) {
    editorValue = newValue
  }

  function save() {
    if (readonly) return
    live.pushEvent('file_save', { content: editorValue, path: path, original_hash: currentHash })
  }
</script>

<div class="h-full overflow-hidden flex flex-col">
  {#if loadError}
    <div class="text-xs text-error px-3 py-1 bg-base-200 border-b border-base-300 shrink-0">
      {loadError}
    </div>
  {/if}
  {#if langExtension !== undefined && themeExtension !== undefined}
    <CodeMirror
      class="flex-1 min-h-0"
      value={content}
      lang={langExtension}
      theme={themeExtension}
      extensions={settingsExtensions}
      {tabSize}
      {readonly}
      lineNumbers={true}
      useTab={true}
      styles={{
        "&": { height: "100%", backgroundColor: "oklch(var(--b1))" },
        ".cm-scroller": { overflow: "auto" },
        ".cm-gutters": { backgroundColor: "oklch(var(--b2))", borderRight: "1px solid oklch(var(--b3))", color: "oklch(var(--bc) / 0.4)" },
        ".cm-gutterElement": { color: "oklch(var(--bc) / 0.4)" },
        ".cm-activeLineGutter": { backgroundColor: "oklch(var(--b3))", color: "oklch(var(--bc) / 0.7)" },
        ".cm-activeLine": { backgroundColor: "oklch(var(--b3) / 0.4)" },
      }}
      on:change={(e) => handleChange(e.detail)}
    />
  {/if}
</div>
