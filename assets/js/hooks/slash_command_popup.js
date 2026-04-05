import { createEnumAutocomplete } from './enum_autocomplete.js'

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

  // Score an item against a query. Higher = better match.
  // 3: exact match on slug
  // 2: slug starts with query
  // 1: slug contains query
  // 0: description/type contains query
  scoreItem(item, q) {
    if (!q) {
      let score = 1
      if (item.type === 'flag' && this.activeFlags && this.activeFlags[item.slug] !== undefined) {
        score += 10
      }
      return score
    }
    const slug = item.slug.toLowerCase()
    const desc = (item.description || '').toLowerCase()
    const type = (item.type || '').toLowerCase()
    let score = -1
    if (slug === q) score = 3
    else if (slug.startsWith(q)) score = 2
    else if (slug.includes(q)) score = 1
    else if (desc.includes(q) || type.includes(q)) score = 0

    if (score >= 0 && item.type === 'flag' && this.activeFlags && this.activeFlags[item.slug] !== undefined) {
      score += 10
    }
    return score
  },

  slashFilter(query, typeFilter) {
    const q = query.toLowerCase()
    const MAX_RESULTS = 8

    let pool = typeFilter
      ? this.slashItems.filter(item => item.type === typeFilter)
      : this.slashItems.filter(item => item.type !== 'agent')

    let scored = pool
      .map(item => ({ item, score: this.scoreItem(item, q) }))
      .filter(({ score }) => score >= 0)

    // Sort by score desc, then slug asc for ties
    scored.sort((a, b) => {
      if (b.score !== a.score) return b.score - a.score
      return a.item.slug.localeCompare(b.item.slug)
    })

    this.slashFiltered = scored.slice(0, MAX_RESULTS).map(({ item }) => item)

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
    this.popup.innerHTML = ''

    // Build groups in typeOrder — this determines DOM order
    const groups = {}
    for (const item of this.slashFiltered) {
      const t = item.type || 'other'
      if (!groups[t]) groups[t] = []
      groups[t].push(item)
    }

    const typeOrder = ['skill', 'command', 'flag', 'agent', 'prompt']
    const typeLabels = { skill: 'Skills', command: 'Commands', flag: 'Flags', agent: 'Agents', prompt: 'Prompts' }
    const allTypes = [...typeOrder, ...Object.keys(groups).filter(t => !typeOrder.includes(t))]

    // slashOrdered tracks items in exact DOM render order — used by slashSelect
    this.slashOrdered = []

    for (const type of allTypes) {
      if (!groups[type]) continue

      const header = document.createElement('div')
      header.className = 'px-3 py-1 text-[10px] font-semibold uppercase tracking-wider text-base-content/40 bg-base-content/[0.02] sticky top-0'
      header.textContent = typeLabels[type] || type
      this.popup.appendChild(header)

      for (const item of groups[type]) {
        const idx = this.slashOrdered.length
        this.slashOrdered.push(item)

        const row = document.createElement('button')
        row.type = 'button'
        row.dataset.slashIdx = idx
        row.className = this.rowClass(idx)
        row.innerHTML = this.rowHTML(item, query)
        row.addEventListener('mouseenter', () => {
          this.slashIndex = idx
          this.highlightRow()
        })
        row.addEventListener('mousedown', (e) => {
          e.preventDefault()
          this.slashIndex = idx
          this.slashSelect()
        })
        this.popup.appendChild(row)
      }
    }

    // Keyboard hint footer
    const hint = document.createElement('div')
    hint.className = 'px-3 py-1.5 text-[10px] text-base-content/30 border-t border-base-content/5 flex items-center gap-3 sticky bottom-0 bg-base-100'
    hint.innerHTML = '<kbd class="font-mono">↑↓</kbd> navigate &nbsp;<kbd class="font-mono">↵</kbd> or <kbd class="font-mono">Tab</kbd> select &nbsp;<kbd class="font-mono">Esc</kbd> dismiss'
    this.popup.appendChild(hint)

    this.popup.classList.remove('hidden')
    this.highlightRow()
  },

  // Highlight query match in text — wraps matching part in <mark>
  highlightMatch(text, query) {
    if (!query) return this.escapeHtml(text)
    const q = query.toLowerCase()
    const idx = text.toLowerCase().indexOf(q)
    if (idx === -1) return this.escapeHtml(text)
    return (
      this.escapeHtml(text.slice(0, idx)) +
      `<mark class="bg-primary/20 text-primary rounded px-0.5">${this.escapeHtml(text.slice(idx, idx + q.length))}</mark>` +
      this.escapeHtml(text.slice(idx + q.length))
    )
  },

  escapeHtml(str) {
    return str
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;')
  },

  rowClass(idx) {
    return 'w-full flex items-start gap-3 px-3 py-2 text-left transition-colors text-sm'
  },

  rowHTML(item, query) {
    const badge = {
      skill: '<span class="shrink-0 mt-0.5 inline-flex items-center px-1.5 py-0.5 rounded text-[10px] font-medium bg-primary/10 text-primary">skill</span>',
      command: '<span class="shrink-0 mt-0.5 inline-flex items-center px-1.5 py-0.5 rounded text-[10px] font-medium bg-secondary/10 text-secondary">cmd</span>',
      flag: '<span class="shrink-0 mt-0.5 inline-flex items-center px-1.5 py-0.5 rounded text-[10px] font-medium bg-info/10 text-info">flag</span>',
      agent: '<span class="shrink-0 mt-0.5 inline-flex items-center px-1.5 py-0.5 rounded text-[10px] font-medium bg-accent/10 text-accent">agent</span>',
      prompt: '<span class="shrink-0 mt-0.5 inline-flex items-center px-1.5 py-0.5 rounded text-[10px] font-medium bg-warning/10 text-warning">prompt</span>',
    }[item.type] || ''

    const prefix = item.type === 'agent' ? '@' : '/'
    const nameHtml = this.highlightMatch(item.slug, query)
    const name = `<span class="font-medium text-base-content">${prefix}${nameHtml}</span>`

    const isActive = item.type === 'flag' && this.activeFlags && this.activeFlags[item.slug] !== undefined
    const activeVal = isActive ? this.activeFlags[item.slug] : null
    const activeBadge = isActive
      ? `<span class="shrink-0 inline-flex items-center px-1.5 py-0.5 rounded text-[10px] font-medium bg-success/10 text-success ml-1">${activeVal === true ? 'on' : activeVal === false ? 'off' : this.escapeHtml(String(activeVal))}</span>`
      : ''

    const desc = item.description
      ? `<span class="text-xs text-base-content/50 truncate">${this.escapeHtml(item.description)}</span>`
      : ''

    return `
      ${badge}
      <span class="min-w-0 flex-1">
        <span class="flex items-center gap-2">
          ${name}${activeBadge}
        </span>
        ${desc}
      </span>
    `
  },

  highlightRow() {
    const rows = this.popup.querySelectorAll('button[data-slash-idx]')
    rows.forEach(row => {
      const idx = parseInt(row.dataset.slashIdx)
      if (idx === this.slashIndex) {
        row.classList.add('bg-base-content/[0.06]')
        row.scrollIntoView({ block: 'nearest' })
      } else {
        row.classList.remove('bg-base-content/[0.06]')
      }
    })
  },

  slashMove(delta) {
    const total = (this.slashOrdered || this.slashFiltered).length
    if (total === 0) return
    this.slashIndex = (this.slashIndex + delta + total) % total
    this.highlightRow()
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
