export const CommandHistory = {
  mounted() {
    this.history = []
    this.historyIndex = -1
    this.currentInput = ''

    // Slash command popup state
    this.slashItems = []
    this.slashFiltered = []
    this.slashOrdered = []
    this.slashIndex = 0
    this.slashOpen = false
    this.slashTriggerPos = -1

    this.loadSlashItems()
    this.buildPopup()

    this.el.addEventListener('keydown', (e) => {
      // If popup is open, intercept navigation/select keys
      if (this.slashOpen) {
        if (e.key === 'ArrowDown') {
          e.preventDefault()
          this.slashMove(1)
          return
        }
        if (e.key === 'ArrowUp') {
          e.preventDefault()
          this.slashMove(-1)
          return
        }
        if (e.key === 'Tab' || e.key === 'Enter') {
          e.preventDefault()
          this.slashSelect()
          return
        }
        if (e.key === 'Escape') {
          e.preventDefault()
          this.slashClose()
          return
        }
      }

      // Shift+Enter - insert newline
      if (e.key === 'Enter' && e.shiftKey) {
        requestAnimationFrame(() => this.autoResize())
        return
      }
      // Enter - submit form
      if (e.key === 'Enter' && !e.shiftKey) {
        e.preventDefault()
        const value = this.el.value.trim()
        if (value) {
          this.addToHistory(value)
          const form = this.el.form || this.el.closest('form')
          if (form) {
            if (form.requestSubmit) {
              form.requestSubmit()
            } else {
              form.dispatchEvent(new Event('submit', { bubbles: true, cancelable: true }))
            }
          }
        }
        return
      }
      // Ctrl+P or Up Arrow - Previous command (only when popup closed)
      if ((e.ctrlKey && e.key === 'p') || e.key === 'ArrowUp') {
        e.preventDefault()
        this.navigateHistory('prev')
      }
      // Ctrl+N or Down Arrow - Next command (only when popup closed)
      else if ((e.ctrlKey && e.key === 'n') || e.key === 'ArrowDown') {
        e.preventDefault()
        this.navigateHistory('next')
      }
    })

    // Auto-resize and slash detection on input
    this.el.addEventListener('input', () => {
      this.autoResize()
      this.loadSlashItems()
      this.checkSlashTrigger()
    })

    // Close popup on click outside
    this._outsideClick = (e) => {
      if (this.slashOpen && !this.popup.contains(e.target) && e.target !== this.el) {
        this.slashClose()
      }
    }
    document.addEventListener('mousedown', this._outsideClick)

    // Listen for clear-input event from server
    this.handleEvent('clear-input', () => {
      this.el.value = ''
      this.historyIndex = -1
      this.currentInput = ''
      this.slashClose()
      this.autoResize()
      this.el.focus()
    })

    // Listen for focus-input event from server
    this.handleEvent('focus-input', () => {
      this.el.focus()
    })
  },

  destroyed() {
    document.removeEventListener('mousedown', this._outsideClick)
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

    // Find the last '/' before cursor that's at start or after a space/newline
    let triggerPos = -1
    for (let i = cursor - 1; i >= 0; i--) {
      if (val[i] === '/') {
        const before = i === 0 ? '' : val[i - 1]
        if (i === 0 || before === ' ' || before === '\n') {
          triggerPos = i
        }
        break
      }
      // If we hit a space/newline before finding '/', stop
      if (val[i] === ' ' || val[i] === '\n') break
    }

    if (triggerPos === -1) {
      this.slashClose()
      return
    }

    const query = val.slice(triggerPos + 1, cursor)
    this.slashTriggerPos = triggerPos
    this.slashFilter(query)
  },

  slashFilter(query) {
    const q = query.toLowerCase()
    this.slashFiltered = this.slashItems.filter(item => {
      return item.slug.toLowerCase().includes(q) ||
        (item.description || '').toLowerCase().includes(q) ||
        (item.type || '').toLowerCase().includes(q)
    })

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

    const typeOrder = ['skill', 'command', 'agent', 'prompt']
    const typeLabels = { skill: 'Skills', command: 'Commands', agent: 'Agents', prompt: 'Prompts' }
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
        row.innerHTML = this.rowHTML(item)
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

    this.popup.classList.remove('hidden')
    this.highlightRow()
  },

  rowClass(idx) {
    return 'w-full flex items-start gap-3 px-3 py-2 text-left transition-colors text-sm'
  },

  rowHTML(item) {
    const badge = {
      skill: '<span class="shrink-0 mt-0.5 inline-flex items-center px-1.5 py-0.5 rounded text-[10px] font-medium bg-primary/10 text-primary">skill</span>',
      command: '<span class="shrink-0 mt-0.5 inline-flex items-center px-1.5 py-0.5 rounded text-[10px] font-medium bg-secondary/10 text-secondary">cmd</span>',
      agent: '<span class="shrink-0 mt-0.5 inline-flex items-center px-1.5 py-0.5 rounded text-[10px] font-medium bg-accent/10 text-accent">agent</span>',
      prompt: '<span class="shrink-0 mt-0.5 inline-flex items-center px-1.5 py-0.5 rounded text-[10px] font-medium bg-warning/10 text-warning">prompt</span>',
    }[item.type] || ''

    const name = item.type === 'agent'
      ? `<span class="font-medium text-base-content">@${item.slug}</span>`
      : `<span class="font-medium text-base-content">/${item.slug}</span>`

    const desc = item.description
      ? `<span class="text-xs text-base-content/50 truncate">${item.description}</span>`
      : ''

    return `
      ${badge}
      <span class="min-w-0 flex-1">
        <span class="flex items-center gap-2">
          ${name}
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

  slashSelect() {
    const item = (this.slashOrdered || this.slashFiltered)[this.slashIndex]
    if (!item) return

    const val = this.el.value
    const cursor = this.el.selectionStart
    const prefix = val.slice(0, this.slashTriggerPos)
    const suffix = val.slice(cursor)

    const insertion = item.type === 'agent' ? `@${item.slug} ` : `/${item.slug} `
    const newVal = prefix + insertion + suffix
    this.el.value = newVal

    const newCursor = prefix.length + insertion.length
    this.el.setSelectionRange(newCursor, newCursor)
    this.el.focus()

    this.slashClose()
    this.autoResize()
  },

  slashClose() {
    this.slashOpen = false
    this.slashTriggerPos = -1
    this.slashOrdered = []
    this.popup.classList.add('hidden')
    this.popup.innerHTML = ''
  },

  autoResize() {
    this.el.style.height = 'auto'
    this.el.style.height = Math.min(this.el.scrollHeight, 160) + 'px'
  },

  navigateHistory(direction) {
    if (this.historyIndex === -1) {
      this.currentInput = this.el.value
    }

    if (direction === 'prev') {
      if (this.historyIndex < this.history.length - 1) {
        this.historyIndex++
        this.el.value = this.history[this.historyIndex]
      }
    } else if (direction === 'next') {
      if (this.historyIndex > 0) {
        this.historyIndex--
        this.el.value = this.history[this.historyIndex]
      } else if (this.historyIndex === 0) {
        this.historyIndex = -1
        this.el.value = this.currentInput
      }
    }

    this.el.setSelectionRange(this.el.value.length, this.el.value.length)
    this.autoResize()
  },

  addToHistory(command) {
    if (this.history.length === 0 || this.history[0] !== command) {
      this.history.unshift(command)
      if (this.history.length > 100) {
        this.history.pop()
      }
    }
    this.historyIndex = -1
    this.currentInput = ''
  }
}
