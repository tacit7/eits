// Phoenix only supports one phx-hook per element. SlashCommandPopup is composed here
// via SlashCommandPopup.mounted.call(this) so both hooks share the same LiveView hook
// context (this.el, this.handleEvent, etc.) without needing a second phx-hook attribute.
//
// History persistence: per-session localStorage key `dm_history:<session_uuid>`.
// Ctrl+R        → search dropdown filtered to current session's history.
// Ctrl+Shift+R  → search dropdown merged across all dm_history:* keys (global).
import {SlashCommandPopup} from "./slash_command_popup"
import {escapeHtml, highlightMatch} from "./slash_renderer"

const MAX_HISTORY = 100

export const CommandHistory = {
  mounted() {
    this.historyIndex = -1
    this.currentInput = ''
    this._searchEl = null

    // Per-session localStorage key
    this._storageKey = `dm_history:${this.el.dataset.sessionUuid || 'default'}`
    this.history = this._loadHistory()

    // Cross-tab eviction: another tab archived sessions and wrote the sentinel.
    this._onStorage = (e) => {
      if (e.key === 'dm_history_evict' && e.newValue) {
        try {
          JSON.parse(e.newValue).forEach(uuid =>
            localStorage.removeItem(`dm_history:${uuid}`)
          )
          // Reload in case our own key was evicted
          this.history = this._loadHistory()
        } catch {}
      }
    }
    window.addEventListener('storage', this._onStorage)

    this.el.addEventListener('keydown', (e) => {
      // Shift+Enter - insert newline
      if (e.key === 'Enter' && e.shiftKey) {
        requestAnimationFrame(() => this.autoResize())
        return
      }

      // When slash popup is open, delegate navigation/selection/dismiss to it
      if (this.slashOpen) {
        if (e.key === 'ArrowUp') {
          e.preventDefault()
          this.slashMove(-1)
          return
        }
        if (e.key === 'ArrowDown') {
          e.preventDefault()
          this.slashMove(1)
          return
        }
        if (e.key === 'Tab' || (e.key === 'Enter' && !e.shiftKey)) {
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

      // Ctrl+Shift+R — global history search (check before plain Ctrl+R)
      if (e.ctrlKey && e.shiftKey && (e.key === 'r' || e.key === 'R')) {
        e.preventDefault()
        this._openSearch(true)
        return
      }

      // Ctrl+R — session history search
      if (e.ctrlKey && !e.shiftKey && (e.key === 'r' || e.key === 'R')) {
        e.preventDefault()
        this._openSearch(false)
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

      // Ctrl+P or Up Arrow - Previous command
      // ArrowUp only triggers history navigation when the cursor is on the first line.
      if (e.ctrlKey && e.key === 'p') {
        e.preventDefault()
        this.navigateHistory('prev')
      } else if (e.key === 'ArrowUp' && this._isOnFirstLine()) {
        e.preventDefault()
        this.navigateHistory('prev')
      }
      // Ctrl+N or Down Arrow - Next command
      else if ((e.ctrlKey && e.key === 'n') || e.key === 'ArrowDown') {
        e.preventDefault()
        this.navigateHistory('next')
      }
    })

    this.el.addEventListener('input', () => {
      this.autoResize()
    })

    this.handleEvent('clear-input', () => {
      this.el.value = ''
      this.historyIndex = -1
      this.currentInput = ''
      this.autoResize()
      this.el.focus()
    })

    this.handleEvent('focus-input', () => {
      this.el.focus()
    })

    // Copy all SlashCommandPopup methods onto this hook context so that
    // mounted() can reference them via `this`. Phoenix only supports one
    // phx-hook per element, so composition is done manually here.
    Object.assign(this, SlashCommandPopup)
    SlashCommandPopup.mounted.call(this)
  },

  destroyed() {
    window.removeEventListener('storage', this._onStorage)
    this._closeSearch()
    SlashCommandPopup.destroyed.call(this)
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
      if (this.history.length > MAX_HISTORY) {
        this.history.pop()
      }
    }
    this.historyIndex = -1
    this.currentInput = ''
    this._saveHistory()
  },

  autoResize() {
    this.el.style.height = 'auto'
    this.el.style.height = Math.min(this.el.scrollHeight, 160) + 'px'
  },

  // Returns true when the cursor is on the first line of the textarea.
  // "First line" = no newline character between the start and the cursor position.
  _isOnFirstLine() {
    const beforeCursor = this.el.value.substring(0, this.el.selectionStart)
    return !beforeCursor.includes('\n')
  },

  // ── localStorage ─────────────────────────────────────────────────────────────
  _loadHistory() {
    try {
      const parsed = JSON.parse(localStorage.getItem(this._storageKey) || '[]')
      return Array.isArray(parsed) ? parsed : []
    } catch {
      return []
    }
  },

  _saveHistory() {
    try {
      localStorage.setItem(this._storageKey, JSON.stringify(this.history))
    } catch {}
  },

  // ── History search dropdown ───────────────────────────────────────────────────
  _openSearch(global) {
    if (this._searchEl) return

    const items = global
      ? this._loadGlobalHistory()
      : this.history.map(t => ({ text: t, session: null }))

    const label = global ? 'ctrl+shift+r — all sessions' : 'ctrl+r — this session'

    const popup = document.createElement('div')
    popup.id = 'dm-history-popup'
    popup.style.cssText = 'position:fixed;z-index:9999;width:400px;max-width:90vw'
    popup.className = 'rounded-xl border border-base-content/10 bg-base-100 shadow-xl overflow-hidden'
    popup.innerHTML = `
      <div class="flex items-center gap-2 px-3 py-2 border-b border-base-content/8">
        <span class="text-xs font-mono text-base-content/25 shrink-0 select-none">${escapeHtml(label)}</span>
        <input
          id="dm-history-search-input"
          type="text"
          class="flex-1 bg-transparent text-sm outline-none placeholder:text-base-content/30 text-base-content min-w-0"
          placeholder="Filter..."
          autocomplete="off"
          spellcheck="false"
        />
      </div>
      <div id="dm-history-results" class="max-h-52 overflow-y-auto"></div>
    `

    document.body.appendChild(popup)
    this._searchEl = popup
    this._searchItems = items
    this._searchIndex = 0

    this._positionPopup()
    this._renderResults('')

    const input = popup.querySelector('#dm-history-search-input')
    input.focus()

    this._onSearchInput = () => {
      this._searchIndex = 0
      this._renderResults(input.value)
    }
    input.addEventListener('input', this._onSearchInput)

    this._onSearchKeydown = (e) => {
      const results = popup.querySelectorAll('[data-history-idx]')
      if (e.key === 'ArrowDown') {
        e.preventDefault()
        this._searchIndex = Math.min(this._searchIndex + 1, results.length - 1)
        this._updateSearchActive(results)
      } else if (e.key === 'ArrowUp') {
        e.preventDefault()
        this._searchIndex = Math.max(this._searchIndex - 1, 0)
        this._updateSearchActive(results)
      } else if (e.key === 'Enter') {
        e.preventDefault()
        const active = results[this._searchIndex]
        if (active) this._selectHistoryItem(active.dataset.text)
      } else if (e.key === 'Escape') {
        e.preventDefault()
        this._closeSearch()
        this.el.focus()
      }
    }
    input.addEventListener('keydown', this._onSearchKeydown)

    this._onSearchOutside = (e) => {
      if (this._searchEl && !this._searchEl.contains(e.target) && e.target !== this.el) {
        this._closeSearch()
      }
    }
    document.addEventListener('mousedown', this._onSearchOutside)

    this._onSearchResize = () => this._positionPopup()
    window.addEventListener('resize', this._onSearchResize)
    window.addEventListener('scroll', this._onSearchResize, { capture: true, passive: true })
  },

  _positionPopup() {
    if (!this._searchEl) return
    const form = this.el.closest('form')
    if (!form) return
    const rect = form.getBoundingClientRect()
    this._searchEl.style.bottom = `${window.innerHeight - rect.top + 6}px`
    this._searchEl.style.left = `${rect.left}px`
  },

  _renderResults(query) {
    if (!this._searchEl) return
    const container = this._searchEl.querySelector('#dm-history-results')
    if (!container) return

    const q = query.toLowerCase().trim()
    const filtered = q
      ? this._searchItems.filter(item => item.text.toLowerCase().includes(q))
      : this._searchItems

    if (filtered.length === 0) {
      container.innerHTML = '<div class="px-4 py-3 text-xs text-base-content/30 text-center select-none">No matches</div>'
      return
    }

    container.innerHTML = filtered.map((item, i) => {
      const display = item.text.length > 100 ? item.text.slice(0, 100) + '…' : item.text
      const textHtml = highlightMatch(display, q)
      const badge = item.session
        ? `<span class="shrink-0 font-mono text-xs text-base-content/25">${escapeHtml(item.session)}</span>`
        : ''
      const activeClass = i === this._searchIndex ? 'bg-base-content/[0.06]' : ''
      return `<button
        type="button"
        data-history-idx="${i}"
        data-text="${escapeHtml(item.text)}"
        class="w-full flex items-center gap-3 px-3 py-2 text-left text-sm hover:bg-base-content/[0.04] transition-colors ${activeClass}"
      ><span class="flex-1 truncate text-base-content/80">${textHtml}</span>${badge}</button>`
    }).join('')

    container.querySelectorAll('[data-history-idx]').forEach(btn => {
      btn.addEventListener('mousedown', (e) => {
        e.preventDefault()
        this._selectHistoryItem(btn.dataset.text)
      })
    })
  },

  _updateSearchActive(results) {
    results.forEach((el, i) => {
      el.classList.toggle('bg-base-content/[0.06]', i === this._searchIndex)
    })
    const active = results[this._searchIndex]
    if (active) active.scrollIntoView({ block: 'nearest' })
  },

  _selectHistoryItem(text) {
    this.el.value = text
    this.el.dispatchEvent(new Event('input', { bubbles: true }))
    this._closeSearch()
    this.el.focus()
    this.el.setSelectionRange(text.length, text.length)
    this.autoResize()
  },

  _closeSearch() {
    if (!this._searchEl) return
    const input = this._searchEl.querySelector('#dm-history-search-input')
    if (input) {
      if (this._onSearchInput) input.removeEventListener('input', this._onSearchInput)
      if (this._onSearchKeydown) input.removeEventListener('keydown', this._onSearchKeydown)
    }
    if (this._onSearchOutside) document.removeEventListener('mousedown', this._onSearchOutside)
    if (this._onSearchResize) {
      window.removeEventListener('resize', this._onSearchResize)
      window.removeEventListener('scroll', this._onSearchResize, { capture: true })
    }
    this._searchEl.remove()
    this._searchEl = null
  },

  _loadGlobalHistory() {
    const result = []
    const seen = new Set()
    for (let i = 0; i < localStorage.length; i++) {
      const key = localStorage.key(i)
      if (!key || !key.startsWith('dm_history:')) continue
      const uuid = key.replace('dm_history:', '')
      try {
        const entries = JSON.parse(localStorage.getItem(key) || '[]')
        if (!Array.isArray(entries)) continue
        entries.forEach(text => {
          if (typeof text === 'string' && !seen.has(text)) {
            seen.add(text)
            result.push({ text, session: uuid.slice(0, 8) })
          }
        })
      } catch {}
    }
    return result
  }
}
