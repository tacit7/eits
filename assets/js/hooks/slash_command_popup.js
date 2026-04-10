import { createEnumAutocomplete } from './enum_autocomplete.js'
import { filterAndScore } from './slash_scorer.js'
import { renderItems, updateActiveItem } from './slash_renderer.js'

export const SlashCommandPopup = {
  mounted() {
    // Slash command popup state
    this.slashItems = []
    this.slashFiltered = []
    this.slashOrdered = []
    this.slashIndex = 0
    this.slashOpen = false
    this.slashTriggerPos = -1
    this.slashTriggerChar = '/'  // '/' or '@'

    this.enumAC = createEnumAutocomplete(this)

    this.loadSlashItems()
    this.buildPopup()

    // Slash detection on input
    this._inputListener = () => {
      this.loadSlashItems()
      this.checkSlashTrigger()
      if (!this.slashOpen) this.enumAC.checkEnumContext()
    }
    this.el.addEventListener('input', this._inputListener)

    // Close popup on click outside
    this._outsideClick = (e) => {
      if (this.slashOpen && !this.popup.contains(e.target) && e.target !== this.el) {
        this.slashClose()
      }
    }
    document.addEventListener('mousedown', this._outsideClick)

    // Listen for clear-input event from server
    this.handleEvent('clear-input', () => {
      this.slashClose()
    })
  },

  destroyed() {
    document.removeEventListener('mousedown', this._outsideClick)
    this.el.removeEventListener('input', this._inputListener)
    if (this.popup && this.popup.parentNode) {
      this.popup.parentNode.removeChild(this.popup)
    }
  },

  loadSlashItems() {
    const form = this.el.closest('form') || this.el.closest('[data-slash-items]')
    const target = this.el.closest('[data-slash-items]') || (form && form.querySelector('[data-slash-items]')) || form
    if (!target) return

    const raw = target.dataset.slashItems
    if (!raw) return

    try {
      this.slashItems = JSON.parse(raw)
    } catch (e) {
      this.slashItems = []
    }

    const activeRaw = target.dataset.sessionFlags
    this.activeFlags = {}
    if (activeRaw) {
      try { JSON.parse(activeRaw).forEach(f => { this.activeFlags[f.slug] = f.value }) } catch (_) {}
    }

    // If the popup was detached by a LiveView DOM patch while open,
    // the popup element is gone but slashOpen may still be true.
    // Reset popup state to match reality.
    if (this.slashOpen && !document.contains(this.popup)) {
      this.slashOpen = false
      this.slashTriggerPos = -1
      this.slashOrdered = []
    }
  },

  buildPopup() {
    this.popup = document.createElement('div')
    this.popup.id = 'slash-command-popup'
    this.popup.className = [
      'absolute bottom-full left-0 right-0 mb-2',
      'rounded-xl border border-base-content/10',
      'bg-base-100 shadow-xl overflow-hidden',
      'z-50 hidden'
    ].join(' ')
    this.popup.style.maxHeight = '280px'
    this.popup.style.overflowY = 'auto'

    // Insert popup as sibling inside the form's relative wrapper
    const form = this.el.closest('form')
    if (form) {
      form.style.position = 'relative'
      form.appendChild(this.popup)
    }
  },

  checkSlashTrigger() {
    const val = this.el.value
    const cursor = this.el.selectionStart

    // Check for @ trigger (agents only)
    let atTriggerPos = -1
    for (let i = cursor - 1; i >= 0; i--) {
      if (val[i] === '@') {
        const before = i === 0 ? '' : val[i - 1]
        if (i === 0 || before === ' ' || before === '\n') {
          atTriggerPos = i
        }
        break
      }
      if (val[i] === ' ' || val[i] === '\n') break
    }

    if (atTriggerPos !== -1) {
      const query = val.slice(atTriggerPos + 1, cursor)
      this.slashTriggerPos = atTriggerPos
      this.slashTriggerChar = '@'
      this.slashFilter(query, 'agent')
      return
    }

    // Check for / trigger (skills, commands, prompts)
    let triggerPos = -1
    for (let i = cursor - 1; i >= 0; i--) {
      if (val[i] === '/') {
        const before = i === 0 ? '' : val[i - 1]
        if (i === 0 || before === ' ' || before === '\n') {
          triggerPos = i
        }
        break
      }
      if (val[i] === ' ' || val[i] === '\n') break
    }

    if (triggerPos === -1) {
      this.slashClose()
      return
    }

    const query = val.slice(triggerPos + 1, cursor)
    this.slashTriggerPos = triggerPos
    this.slashTriggerChar = '/'
    this.slashFilter(query, null)
  },

  slashFilter(query, typeFilter) {
    this.slashFiltered = filterAndScore(this.slashItems, query, typeFilter, this.activeFlags)

    if (this.slashFiltered.length === 0) {
      this.slashClose()
      return
    }

    this.slashIndex = 0
    this.slashOpen = true
    this.renderPopup(query)
  },

  renderPopup(query) {
    // Re-attach popup if LiveView's DOM patch removed it
    if (!document.contains(this.popup)) {
      const form = this.el.closest('form')
      if (form) {
        form.style.position = 'relative'
        form.appendChild(this.popup)
      }
    }

    this.slashOrdered = renderItems(
      this.popup,
      this.slashFiltered,
      this.slashIndex,
      query,
      this.activeFlags,
      (idx) => {
        this.slashIndex = idx
        updateActiveItem(this.popup, idx)
      },
      (idx) => {
        this.slashIndex = idx
        this.slashSelect()
      }
    )

    this.popup.classList.remove('hidden')
  },

  slashMove(delta) {
    const total = (this.slashOrdered || this.slashFiltered).length
    if (total === 0) return
    this.slashIndex = (this.slashIndex + delta + total) % total
    updateActiveItem(this.popup, this.slashIndex)
  },

  slashBuildInsertion(item) {
    if (item.type === 'agent') return { text: `@${item.slug} `, selectRange: null }

    const argType = item.arg_type
    if (!argType || argType === 'none') return { text: `/${item.slug} `, selectRange: null }

    let placeholder
    if (typeof argType === 'object' && argType.type === 'enum') {
      placeholder = `<${argType.values[0]}>`
    } else if (argType === 'path') {
      placeholder = '<path>'
    } else if (argType === 'integer') {
      placeholder = '<n>'
    } else {
      placeholder = '<value>'
    }

    const text = `/${item.slug} ${placeholder}`
    const selectStart = item.slug.length + 2  // '/' + slug + ' '
    const selectEnd   = selectStart + placeholder.length
    return { text, selectRange: [selectStart, selectEnd] }
  },

  slashSelect() {
    const item = (this.slashOrdered || this.slashFiltered)[this.slashIndex]
    if (!item) return

    if (this.enumAC.handleSelect()) return

    const val = this.el.value
    const cursor = this.el.selectionStart
    const prefix = val.slice(0, this.slashTriggerPos)
    const suffix = val.slice(cursor)

    const { text: insertion, selectRange } = this.slashBuildInsertion(item)
    const newVal = prefix + insertion + suffix
    this.el.value = newVal

    if (selectRange) {
      const base = prefix.length
      this.el.setSelectionRange(base + selectRange[0], base + selectRange[1])
    } else {
      const pos = prefix.length + insertion.length
      this.el.setSelectionRange(pos, pos)
    }
    this.el.focus()

    this.slashClose()
    this.autoResize && this.autoResize()
  },

  slashClose() {
    this.slashOpen = false
    this.slashTriggerPos = -1
    this.slashTriggerChar = '/'
    this.slashOrdered = []
    this.enumAC.close()
    this.popup.classList.add('hidden')
    this.popup.innerHTML = ''
  },
}
