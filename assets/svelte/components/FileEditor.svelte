<script>
  import { onMount } from 'svelte'
  import CodeMirror from 'svelte-codemirror-editor'

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
  let value = content
  let currentHash = hash

  $: if (content !== value && content !== undefined) {
    value = content
    currentHash = hash
  }

  async function loadLang(l) {
    switch (l) {
      case 'elixir': {
        const { elixir } = await import('codemirror-lang-elixir')
        return elixir()
      }
      case 'javascript':
      case 'typescript': {
        const { javascript } = await import('@codemirror/lang-javascript')
        return javascript({ typescript: l === 'typescript' })
      }
      case 'css': {
        const { css } = await import('@codemirror/lang-css')
        return css()
      }
      case 'html':
      case 'heex': {
        const { html } = await import('@codemirror/lang-html')
        return html()
      }
      case 'markdown': {
        const { markdown } = await import('@codemirror/lang-markdown')
        return markdown()
      }
      case 'json': {
        const { json } = await import('@codemirror/lang-json')
        return json()
      }
      case 'shell':
      case 'bash': {
        const [{ StreamLanguage }, { shell }] = await Promise.all([
          import('@codemirror/language'),
          import('@codemirror/legacy-modes/mode/shell'),
        ])
        return StreamLanguage.define(shell)
      }
      default:
        return null
    }
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

  onMount(async () => {
    const appTheme = document.documentElement.dataset.theme || 'dark'
    const ds = document.documentElement.dataset
    const initSize = parseInt(ds.cmTabSize || '2', 10)
    const initFont = ds.cmFontSize || '14'
    const initVim = ds.cmVim === 'true'

    tabSize = initSize
    ;[langExtension, themeExtension, settingsExtensions] = await Promise.all([
      loadLang(lang),
      loadTheme(appTheme),
      buildSettingsExtensions(initSize, initFont, initVim),
    ])

    const onTheme = async ({ detail }) => {
      themeExtension = await loadTheme(detail.theme)
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
    return () => {
      window.removeEventListener('phx:apply_theme', onTheme)
      window.removeEventListener('phx:apply_cm_settings', onCmSettings)
      window.removeEventListener('keydown', onKeydown)
    }
  })

  function handleChange(newValue) {
    value = newValue
  }

  function save() {
    if (readonly) return
    window.dispatchEvent(new CustomEvent('file:save', {
      detail: { path, content: value, original_hash: currentHash }
    }))
  }
</script>

<div class="h-full overflow-hidden">
  {#if langExtension !== undefined && themeExtension !== undefined}
    <CodeMirror
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
        ".cm-gutters": { backgroundColor: "oklch(var(--b2))", borderRight: "1px solid oklch(var(--b3))" },
        ".cm-activeLineGutter": { backgroundColor: "oklch(var(--b3))" },
        ".cm-activeLine": { backgroundColor: "oklch(var(--b3) / 0.4)" },
      }}
      on:change={(e) => handleChange(e.detail)}
    />
  {/if}
</div>
