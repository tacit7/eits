// EnumAutocomplete — manages the enum sub-popup for slash command parameters.
// Not a LiveView hook. Used internally by SlashCommandPopup.
//
// Usage:
//   import { createEnumAutocomplete } from './enum_autocomplete.js'
//   this.enumAC = createEnumAutocomplete(this)  // pass the parent hook as ctx
//
// ctx must expose: el, popup, slashItems, slashOrdered, slashIndex, slashOpen,
//   rowClass(), highlightMatch(), highlightRow(), slashSelect(), slashClose(), autoResize

export function createEnumAutocomplete(ctx) {
  let enumMode = false
  let enumTriggerWordStart = -1
  let enumValues = []

  function renderEnumPopup(matches, partial) {
    if (!document.contains(ctx.popup)) {
      const form = ctx.el.closest('form')
      if (form) {
        form.style.position = 'relative'
        form.appendChild(ctx.popup)
      }
    }
    ctx.popup.innerHTML = ''

    for (let idx = 0; idx < matches.length; idx++) {
      const v = matches[idx]
      const row = document.createElement('button')
      row.type = 'button'
      row.dataset.slashIdx = idx
      row.className = ctx.rowClass(idx)
      row.innerHTML = `<span class="min-w-0 flex-1"><span class="font-medium text-base-content">${ctx.highlightMatch(v, partial)}</span></span>`
      row.addEventListener('mouseenter', () => {
        ctx.slashIndex = idx
        ctx.highlightRow()
      })
      row.addEventListener('mousedown', (e) => {
        e.preventDefault()
        ctx.slashIndex = idx
        ctx.slashSelect()
      })
      ctx.popup.appendChild(row)
    }

    const hint = document.createElement('div')
    hint.className = 'px-3 py-1.5 text-[10px] text-base-content/30 border-t border-base-content/5 flex items-center gap-3 sticky bottom-0 bg-base-100'
    hint.innerHTML = '<kbd class="font-mono">↑↓</kbd> navigate &nbsp;<kbd class="font-mono">↵</kbd> or <kbd class="font-mono">Tab</kbd> select &nbsp;<kbd class="font-mono">Esc</kbd> dismiss'
    ctx.popup.appendChild(hint)

    ctx.popup.classList.remove('hidden')
    ctx.highlightRow()
  }

  function filterAndShowEnum(partial) {
    const q = partial.toLowerCase()
    const matches = enumValues.filter(v => v.toLowerCase().startsWith(q))
    if (matches.length === 0) { ctx.slashClose(); return }

    ctx.slashOrdered = matches.map(v => ({ slug: v, type: '_enum', description: '' }))
    ctx.slashIndex = 0
    ctx.slashOpen = true
    enumMode = true
    renderEnumPopup(matches, partial)
  }

  return {
    // Inspect cursor position and show enum popup if cursor is in an enum argument.
    checkEnumContext() {
      const val = ctx.el.value
      const cursor = ctx.el.selectionStart

      let wordStart = cursor
      while (wordStart > 0 && val[wordStart - 1] !== ' ' && val[wordStart - 1] !== '\n') wordStart--
      if (wordStart === 0 || val[wordStart - 1] !== ' ') return

      const partial = val.slice(wordStart, cursor)
      let cmdEnd = wordStart - 1
      let cmdStart = cmdEnd - 1
      while (cmdStart > 0 && val[cmdStart - 1] !== ' ' && val[cmdStart - 1] !== '\n') cmdStart--

      const cmdToken = val.slice(cmdStart, cmdEnd)
      if (!cmdToken.startsWith('/')) return

      const slug = cmdToken.slice(1)
      const flagItem = ctx.slashItems && ctx.slashItems.find(i => i.slug === slug && i.type === 'flag')
      if (!flagItem) return

      const argType = flagItem.arg_type
      if (!argType || typeof argType !== 'object' || argType.type !== 'enum') return

      enumTriggerWordStart = wordStart
      enumValues = argType.values
      filterAndShowEnum(partial)
    },

    // Insert the selected enum value. Returns true if handled (caller should return early).
    handleSelect() {
      if (!enumMode) return false
      const item = ctx.slashOrdered[ctx.slashIndex]
      if (!item) return false

      const val = ctx.el.value
      const cursor = ctx.el.selectionStart
      const prefix = val.slice(0, enumTriggerWordStart)
      const suffix = val.slice(cursor)
      const newVal = prefix + item.slug + ' ' + suffix
      ctx.el.value = newVal
      const pos = prefix.length + item.slug.length + 1
      ctx.el.setSelectionRange(pos, pos)
      ctx.slashClose()
      ctx.autoResize && ctx.autoResize()
      return true
    },

    isActive() {
      return enumMode
    },

    close() {
      enumMode = false
    },
  }
}
