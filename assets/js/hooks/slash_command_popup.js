import { createEnumAutocomplete } from './enum_autocomplete.js'
import { filterAndScore } from './slash_scorer.js'
import { renderItems, updateActiveItem, escapeHtml } from './slash_renderer.js'

export const SlashCommandPopup = {
  mounted() {
    // Slash command popup state
    this.slashItems = []
    this.slashFiltered = []
    this.slashOrdered = []
    this.slashIndex = 0
    this.slashOpen = false
    this.slashTriggerPos = -1
    this.slashTriggerChar = '/'  // '/', '@', or '@@'

    this.fileMode = false
    this._fileRoot = 'project'
    this.fileRequestSeq = 0
    this._fileDebounceTimer = null

    this.enumAC = createEnumAutocomplete(this)

    this.loadSlashItems()
    this.buildPopup()

    // Slash detection on input
    this._inputListener = () => {
      if (!this.fileMode) this.loadSlashItems()
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
    const textToCursor = val.slice(0, cursor)

    // 1. @@ agent autocomplete — checked before @ to avoid fallthrough
    const atAtMatch = textToCursor.match(/(^|[\s(])@@([^\s]*)$/)
    if (atAtMatch) {
      const query = atAtMatch[2]
      this.slashTriggerPos = cursor - query.length - 2
      this.slashTriggerChar = '@@'
      this.fileMode = false
      this.slashFilter(query, 'agent')
      return
    }

    // 2. @ file autocomplete — does not match @@ positions
    const atMatch = textToCursor.match(/(^|[\s(])@([^\s@]*)$/)
    if (atMatch) {
      const rawPartial = atMatch[2]
      this.slashTriggerPos = cursor - rawPartial.length - 1
      this.slashTriggerChar = '@'
      this.fileMode = true

      let root, partial
      if (rawPartial.startsWith('~/')) {
        root = 'home'
        partial = rawPartial.slice(2)
      } else if (rawPartial.startsWith('/')) {
        root = 'filesystem'
        partial = rawPartial.slice(1)
      } else {
        root = 'project'
        partial = rawPartial
      }

      this._fileRoot = root
      this.startFileAutocomplete(partial, root)
      return
    }

    // 3. / slash commands (unchanged logic)
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
    this.fileMode = false
    this.slashFilter(query, null)
  },

  startFileAutocomplete(partial, root) {
    this.fileRequestSeq = (this.fileRequestSeq || 0) + 1
    const seq = this.fileRequestSeq

    clearTimeout(this._fileDebounceTimer)
    this._fileDebounceTimer = setTimeout(() => {
      this.pushEvent('list_files', { root, partial }, (reply) => {
        if (seq !== this.fileRequestSeq) return
        if (!reply?.entries) { this.slashClose(); return }
        this.renderFilePopup(reply.entries, reply.truncated)
      })
    }, 150)
  },

  renderFilePopup(entries, truncated) {
    if (!document.contains(this.popup)) {
      const form = this.el.closest('form')
      if (form) {
        form.style.position = 'relative'
        form.appendChild(this.popup)
      }
    }

    this.popup.innerHTML = ''

    if (entries.length === 0) {
      const empty = document.createElement('div')
      empty.className = 'px-4 py-3 text-xs text-base-content/40 select-none text-center'
      empty.textContent = 'No matching files'
      this.popup.appendChild(empty)
      this.slashOrdered = []
      this.slashIndex = 0
      this.slashOpen = true
      this.popup.classList.remove('hidden')
      return
    }

    const header = document.createElement('div')
    header.className = 'px-3 py-1 text-xs font-semibold uppercase tracking-wider text-base-content/40 bg-base-content/[0.02] sticky top-0'
    header.textContent = 'Files'
    this.popup.appendChild(header)

    const ordered = []

    for (const entry of entries) {
      const idx = ordered.length
      ordered.push(entry)

      const row = document.createElement('button')
      row.type = 'button'
      row.dataset.slashIdx = idx
      row.className = 'w-full flex items-center gap-3 px-3 py-2 text-left transition-colors text-sm'

      const iconHtml = entry.is_dir
        ? '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor" class="size-4 text-base-content/40 shrink-0"><path d="M2 6a2 2 0 0 1 2-2h5l2 2h5a2 2 0 0 1 2 2v6a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2V6Z"/></svg>'
        : '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor" class="size-4 text-base-content/30 shrink-0"><path d="M3 3.5A1.5 1.5 0 0 1 4.5 2h6.879a1.5 1.5 0 0 1 1.06.44l4.122 4.12A1.5 1.5 0 0 1 17 7.622V16.5a1.5 1.5 0 0 1-1.5 1.5h-11A1.5 1.5 0 0 1 3 16.5v-13Z"/></svg>'

      row.innerHTML = `${iconHtml}<span class="font-medium text-base-content truncate flex-1">${escapeHtml(entry.name)}${entry.is_dir ? '/' : ''}</span>`

      row.addEventListener('mouseenter', () => {
        this.slashIndex = idx
        this._updateFileActive()
      })
      row.addEventListener('mousedown', (e) => {
        e.preventDefault()
        this.slashIndex = idx
        this.slashSelect()
      })

      this.popup.appendChild(row)
    }

    if (truncated) {
      const footer = document.createElement('div')
      footer.className = 'px-3 py-1.5 text-xs text-base-content/30 border-t border-base-content/5 select-none'
      footer.textContent = 'Showing first 50 — keep typing to narrow'
      this.popup.appendChild(footer)
    }

    const hint = document.createElement('div')
    hint.className = 'px-3 py-1.5 text-xs text-base-content/30 border-t border-base-content/5 flex items-center gap-3 sticky bottom-0 bg-base-100'
    hint.innerHTML = '<kbd class="font-mono">↑↓</kbd> navigate &nbsp;<kbd class="font-mono">↵</kbd> or <kbd class="font-mono">Tab</kbd> select &nbsp;<kbd class="font-mono">Esc</kbd> dismiss'
    this.popup.appendChild(hint)

    this.slashOrdered = ordered
    this.slashIndex = 0
    this.slashOpen = true
    this.popup.classList.remove('hidden')

    this._updateFileActive()
  },

  _updateFileActive() {
    const rows = this.popup.querySelectorAll('button[data-slash-idx]')
    rows.forEach(row => {
      const active = parseInt(row.dataset.slashIdx) === this.slashIndex
      row.classList.toggle('bg-base-content/[0.06]', active)
      if (active) row.scrollIntoView?.({ block: 'nearest' })
    })
  },

  _fileSelect() {
    const item = this.slashOrdered[this.slashIndex]
    if (!item) return

    const val = this.el.value
    const cursor = this.el.selectionStart
    const before = val.slice(0, this.slashTriggerPos)
    const after = val.slice(cursor)
    const newVal = before + item.insert_text + after
    this.el.value = newVal

    const pos = before.length + item.insert_text.length
    this.el.setSelectionRange(pos, pos)
    this.el.focus()

    if (item.is_dir) {
      this.el.dispatchEvent(new Event('input', { bubbles: true }))
    } else {
      this.slashClose()
      this.el.dispatchEvent(new Event('input', { bubbles: true }))
    }
    this.autoResize && this.autoResize()
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
    if (this.fileMode) {
      this._updateFileActive()
    } else {
      updateActiveItem(this.popup, this.slashIndex)
    }
  },

  slashBuildInsertion(item) {
    if (item.type === 'agent') return { text: `@@${item.slug} `, selectRange: null }

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
    if (this.fileMode) {
      this._fileSelect()
      return
    }

    if (this.enumAC.handleSelect()) return

    const item = (this.slashOrdered || this.slashFiltered)[this.slashIndex]
    if (!item) return

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
    clearTimeout(this._fileDebounceTimer)
    this.fileRequestSeq++
    this.fileMode = false
    this.slashOpen = false
    this.slashTriggerPos = -1
    this.slashTriggerChar = '/'
    this.slashOrdered = []
    this.enumAC.close()
    this.popup.classList.add('hidden')
    this.popup.innerHTML = ''
  },
}
