<script>
  import { onMount } from 'svelte'
  import CodeMirror from 'svelte-codemirror-editor'

  export let live
  export let content = ''
  export let lang = 'text'
  export let filePath = ''
  export let readonly = false

  let langExtension = null
  let themeExtension = null
  let value = content
  let dirty = false
  let saving = false

  async function loadLang(l) {
    switch (l) {
      case 'elixir': {
        const { elixir } = await import('codemirror-lang-elixir')
        return elixir()
      }
      case 'javascript': case 'js': case 'ts': {
        const { javascript } = await import('@codemirror/lang-javascript')
        return javascript()
      }
      case 'css': {
        const { css } = await import('@codemirror/lang-css')
        return css()
      }
      case 'html': case 'heex': {
        const { html } = await import('@codemirror/lang-html')
        return html()
      }
      case 'markdown': case 'md': {
        const { markdown } = await import('@codemirror/lang-markdown')
        return markdown()
      }
      case 'json': {
        const { json } = await import('@codemirror/lang-json')
        return json()
      }
      case 'shell': case 'sh': case 'bash': {
        const [{ StreamLanguage }, { shell }] = await Promise.all([
          import('@codemirror/language'),
          import('@codemirror/legacy-modes/mode/shell'),
        ])
        return StreamLanguage.define(shell)
      }
      default: return null
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
        // dark
        const { oneDark } = await import('@codemirror/theme-one-dark')
        return oneDark
      }
    }
  }

  onMount(async () => {
    const appTheme = document.documentElement.dataset.theme || 'dark'
    ;[langExtension, themeExtension] = await Promise.all([
      loadLang(lang),
      loadTheme(appTheme),
    ])

    window.addEventListener('phx:apply_theme', handleThemeChange)
    window.addEventListener('keydown', handleKeydown)
    return () => {
      window.removeEventListener('phx:apply_theme', handleThemeChange)
      window.removeEventListener('keydown', handleKeydown)
    }
  })

  async function handleThemeChange({ detail }) {
    themeExtension = await loadTheme(detail.theme)
  }

  function handleKeydown(e) {
    if ((e.metaKey || e.ctrlKey) && e.key === 's') {
      e.preventDefault()
      save()
    }
  }

  function handleChange(newValue) {
    value = newValue
    dirty = value !== content
  }

  function save() {
    if (readonly || saving || !dirty) return
    saving = true
    live.pushEvent('file_save', { content: value }, (reply) => {
      saving = false
      if (reply && reply.ok) {
        dirty = false
        content = value
      }
    })
  }
</script>

<div class="flex flex-col h-full">
  <div class="flex items-center justify-between px-4 py-2 border-b border-base-300 shrink-0 bg-base-100">
    <span class="text-xs text-base-content/50 font-mono">{filePath}</span>
    {#if !readonly}
      <button
        class="btn btn-xs btn-primary"
        disabled={!dirty || saving}
        on:click={save}
      >
        {saving ? 'Saving…' : 'Save'}
      </button>
    {/if}
  </div>

  <div class="flex-1 min-h-0 overflow-hidden">
    {#if langExtension !== undefined && themeExtension !== undefined}
      <CodeMirror
        value={content}
        lang={langExtension}
        theme={themeExtension}
        {readonly}
        lineNumbers={true}
        useTab={true}
        tabSize={2}
        styles={{ "&": { height: "100%" }, ".cm-scroller": { overflow: "auto" } }}
        onchange={handleChange}
      />
    {/if}
  </div>
</div>
