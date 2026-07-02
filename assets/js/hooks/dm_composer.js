// DmComposer: keyboard-aware layout, Aa format toolbar, @-file mention picker,
// draft persistence, and clipboard paste for the DM message form.
//
// Keyboard layout: on mobile, when the software keyboard opens the visual viewport
// height shrinks while window.innerHeight stays fixed. This hook listens to
// visualViewport resize/scroll events and keeps the message list scrolled to
// the bottom so the composer is always visible above the keyboard.
//
// Format toolbar: the Aa button toggles a format strip. Each button wraps the
// current textarea selection with markdown syntax.
//
// @-file mention picker: intercepts '@' in the textarea, queries the server via
// the existing list_files event, and shows a floating dropdown with keyboard
// navigation. ArrowUp/Down moves selection, Enter/Tab inserts, Escape closes.
//
// Draft persistence: saves textarea content to localStorage on every input event,
// restores on mount. Key: dm-draft:{session_uuid}. Clears on form submit.
//
// Clipboard paste: intercepts paste events with image clipboard items and feeds
// them through the LiveView file upload channel via the hidden file input.

export const DmComposer = {
  mounted() {
    const input = document.getElementById('message-input')

    // ── Keyboard layout ──────────────────────────────────────────────────────
    this._prevVVHeight = window.visualViewport ? window.visualViewport.height : window.innerHeight

    this._onVVChange = () => {
      const vv = window.visualViewport
      if (!vv) return

      const keyboardHeight = Math.max(0, window.innerHeight - vv.height - vv.offsetTop)
      document.documentElement.style.setProperty('--keyboard-height', keyboardHeight + 'px')

      const container = document.getElementById('messages-container')
      if (container) {
        const { scrollHeight, scrollTop, clientHeight } = container
        const distanceFromBottom = scrollHeight - scrollTop - clientHeight
        if (distanceFromBottom <= 120) {
          requestAnimationFrame(() => {
            container.scrollTop = container.scrollHeight
          })
        }
      }

      this._prevVVHeight = vv.height
    }

    if (window.visualViewport) {
      window.visualViewport.addEventListener('resize', this._onVVChange)
      window.visualViewport.addEventListener('scroll', this._onVVChange)
    }

    // ── Format toolbar ────────────────────────────────────────────────────────
    const toggle = document.getElementById('formatter-toggle')
    const bar    = document.getElementById('format-bar')

    if (toggle && bar) {
      this._onToggle = () => {
        const visible = !bar.classList.contains('hidden')
        bar.classList.toggle('hidden', visible)
        toggle.classList.toggle('text-primary', !visible)
        toggle.classList.toggle('text-base-content/30', visible)
        if (!visible && input) input.focus()
      }
      toggle.addEventListener('click', this._onToggle)
    }

    if (bar && input) {
      this._onFmtClick = (e) => {
        const btn = e.target.closest('[data-fmt]')
        if (!btn) return
        e.preventDefault()
        const fmt = btn.dataset.fmt
        this._applyFormat(input, fmt)
      }
      bar.addEventListener('click', this._onFmtClick)
    }

    // ── Draft persistence ────────────────────────────────────────────────────
    if (input) {
      const sessionUuid = input.dataset.sessionUuid
      if (sessionUuid) {
        this._draftKey = `dm-draft:${sessionUuid}`

        const saved = localStorage.getItem(this._draftKey)
        if (saved && !input.value) {
          input.value = saved
          input.dispatchEvent(new Event('input', { bubbles: true }))
        }

        this._onDraftInput = () => {
          if (input.value.trim()) {
            localStorage.setItem(this._draftKey, input.value)
          } else {
            localStorage.removeItem(this._draftKey)
          }
        }
        input.addEventListener('input', this._onDraftInput)

        this._onFormSubmit = () => localStorage.removeItem(this._draftKey)
        this.el.addEventListener('submit', this._onFormSubmit)
      }
    }

    // ── Clipboard paste ───────────────────────────────────────────────────────
    if (input) {
      this._onPaste = (e) => {
        const items = e.clipboardData?.items
        if (!items) return

        const imageItem = Array.from(items).find(
          item => item.kind === 'file' && item.type.startsWith('image/')
        )
        if (!imageItem) return

        const file = imageItem.getAsFile()
        if (!file) return

        const fileInput = this.el.querySelector('input[type="file"]')
        if (!fileInput) return

        try {
          const dt = new DataTransfer()
          dt.items.add(file)
          fileInput.files = dt.files
          fileInput.dispatchEvent(new Event('change', { bubbles: true }))
          e.preventDefault()
        } catch (_err) {
          // DataTransfer assignment not supported — let default paste handle it
        }
      }
      input.addEventListener('paste', this._onPaste)
    }

    // ── @ File mention picker ─────────────────────────────────────────────────
    this._picker = null
    this._pickerEntries = []
    this._pickerIdx = 0
    this._atTriggerPos = -1

    if (input) {
      this._onPickerInput = () => this._handlePickerInput(input)
      this._onPickerKeydown = (e) => this._handlePickerKeydown(e, input)
      input.addEventListener('input', this._onPickerInput)
      input.addEventListener('keydown', this._onPickerKeydown)
    }
  },

  // ── Format apply ─────────────────────────────────────────────────────────
  _applyFormat(ta, fmt) {
    switch (fmt) {
      case 'bold':       return this._wrap(ta, '**')
      case 'italic':     return this._wrap(ta, '*')
      case 'strike':     return this._wrap(ta, '~~')
      case 'code':       return this._wrap(ta, '`')
      case 'code-block': return this._wrapBlock(ta)
      case 'link':       return this._insertLink(ta)
    }
  },

  _wrap(ta, marker, suffix = marker) {
    const start    = ta.selectionStart
    const end      = ta.selectionEnd
    const val      = ta.value
    const selected = val.slice(start, end)
    const before   = val.slice(0, start)
    const after    = val.slice(end)

    // Toggle off if already wrapped
    if (before.endsWith(marker) && after.startsWith(suffix)) {
      ta.value = before.slice(0, -marker.length) + selected + after.slice(suffix.length)
      ta.setSelectionRange(start - marker.length, end - marker.length)
    } else {
      ta.value = before + marker + selected + suffix + after
      if (selected.length === 0) {
        ta.setSelectionRange(start + marker.length, start + marker.length)
      } else {
        ta.setSelectionRange(start + marker.length, end + marker.length)
      }
    }

    ta.dispatchEvent(new Event('input', { bubbles: true }))
    ta.focus()
  },

  _wrapBlock(ta) {
    const start    = ta.selectionStart
    const end      = ta.selectionEnd
    const val      = ta.value
    const selected = val.slice(start, end)
    const before   = val.slice(0, start)
    const after    = val.slice(end)

    if (selected.length > 0) {
      const block = '```\n' + selected + '\n```'
      ta.value = before + block + after
      ta.setSelectionRange(start + 4, start + 4 + selected.length)
    } else {
      const block = '```\n\n```'
      ta.value = before + block + after
      ta.setSelectionRange(start + 4, start + 4)
    }

    ta.dispatchEvent(new Event('input', { bubbles: true }))
    ta.focus()
  },

  _insertLink(ta) {
    const start    = ta.selectionStart
    const end      = ta.selectionEnd
    const selected = ta.value.slice(start, end)
    const before   = ta.value.slice(0, start)
    const after    = ta.value.slice(end)
    const label    = selected || 'link text'
    const inserted = `[${label}](url)`
    ta.value       = before + inserted + after

    const urlStart = start + label.length + 3
    ta.setSelectionRange(urlStart, urlStart + 3)

    ta.dispatchEvent(new Event('input', { bubbles: true }))
    ta.focus()
  },

  // ── @ File mention picker internals ──────────────────────────────────────
  _handlePickerInput(ta) {
    const pos    = ta.selectionStart
    const before = ta.value.slice(0, pos)
    // Match an @ not preceded by a word char, followed by a path-safe string
    const match  = before.match(/@([\w./\-]*)$/)

    if (match) {
      const partial = match[1]
      this._atTriggerPos = pos - partial.length - 1
      this._fetchFiles(partial)
    } else {
      this._closePicker()
    }
  },

  _fetchFiles(partial) {
    this.pushEvent('list_files', { partial, root: 'project' }, (reply) => {
      if (!reply) return
      this._pickerEntries = reply.entries || []
      this._pickerIdx = 0
      if (this._pickerEntries.length > 0) {
        this._renderPicker()
      } else {
        this._closePicker()
      }
    })
  },

  _renderPicker() {
    if (!this._picker) {
      this._picker = document.createElement('div')
      this._picker.id = 'dm-file-picker'
      this._picker.className = [
        'fixed z-[200] bg-base-200 border border-base-content/15',
        'rounded-xl shadow-2xl overflow-hidden',
        'w-72 max-h-52 overflow-y-auto',
      ].join(' ')
      document.body.appendChild(this._picker)
    }

    const form = this.el
    const rect = form.getBoundingClientRect()
    const pickerHeight = Math.min(this._pickerEntries.length * 34 + 10, 208)
    this._picker.style.left = `${rect.left + 8}px`
    this._picker.style.top  = `${rect.top - pickerHeight - 4}px`

    const html = this._pickerEntries.map((entry, i) => {
      const icon   = entry.is_dir ? '📁' : '📄'
      const active = i === this._pickerIdx ? 'bg-base-content/10' : 'hover:bg-base-content/[0.06]'
      return `<div class="flex items-center gap-2 px-3 py-1.5 cursor-pointer text-xs ${active} transition-colors" data-idx="${i}">
        <span>${icon}</span>
        <span class="font-mono text-base-content/70 truncate">${entry.name}</span>
        ${entry.is_dir ? '<span class="ml-auto text-base-content/30 text-[10px]">dir</span>' : ''}
      </div>`
    }).join('')

    this._picker.innerHTML = html

    this._picker.querySelectorAll('[data-idx]').forEach(el => {
      el.addEventListener('mousedown', (e) => {
        e.preventDefault()
        this._selectEntry(parseInt(el.dataset.idx, 10), document.getElementById('message-input'))
      })
    })
  },

  _handlePickerKeydown(e, ta) {
    if (!this._picker) return

    if (e.key === 'Escape') {
      e.stopPropagation()
      this._closePicker()
      return
    }

    if (e.key === 'ArrowDown') {
      e.preventDefault()
      this._pickerIdx = Math.min(this._pickerIdx + 1, this._pickerEntries.length - 1)
      this._renderPicker()
      return
    }

    if (e.key === 'ArrowUp') {
      e.preventDefault()
      this._pickerIdx = Math.max(this._pickerIdx - 1, 0)
      this._renderPicker()
      return
    }

    if (e.key === 'Enter' || e.key === 'Tab') {
      if (this._pickerEntries.length > 0) {
        e.preventDefault()
        this._selectEntry(this._pickerIdx, ta)
      }
    }
  },

  _selectEntry(idx, ta) {
    const entry = this._pickerEntries[idx]
    if (!entry || !ta) return

    const val    = ta.value
    const before = val.slice(0, this._atTriggerPos)
    const after  = val.slice(ta.selectionStart)

    ta.value = before + entry.insert_text + (entry.is_dir ? '' : ' ') + after

    if (entry.is_dir) {
      // Keep picker open so the user can navigate into the directory
      this._atTriggerPos = before.length + 1
      ta.selectionStart = ta.selectionEnd = before.length + entry.insert_text.length
      ta.dispatchEvent(new Event('input', { bubbles: true }))
      this._fetchFiles(entry.path)
    } else {
      const newPos = before.length + entry.insert_text.length + 1
      ta.selectionStart = ta.selectionEnd = newPos
      ta.dispatchEvent(new Event('input', { bubbles: true }))
      this._closePicker()
    }

    ta.focus()
  },

  _closePicker() {
    if (this._picker) {
      this._picker.remove()
      this._picker = null
    }
    this._pickerEntries = []
    this._atTriggerPos = -1
  },

  // ── Cleanup ───────────────────────────────────────────────────────────────
  destroyed() {
    if (window.visualViewport) {
      window.visualViewport.removeEventListener('resize', this._onVVChange)
      window.visualViewport.removeEventListener('scroll', this._onVVChange)
    }
    document.documentElement.style.removeProperty('--keyboard-height')

    const toggle = document.getElementById('formatter-toggle')
    const bar    = document.getElementById('format-bar')
    const input  = document.getElementById('message-input')

    if (toggle && this._onToggle)    toggle.removeEventListener('click', this._onToggle)
    if (bar && this._onFmtClick)     bar.removeEventListener('click', this._onFmtClick)
    if (input) {
      if (this._onDraftInput)        input.removeEventListener('input', this._onDraftInput)
      if (this._onPickerInput)       input.removeEventListener('input', this._onPickerInput)
      if (this._onPickerKeydown)     input.removeEventListener('keydown', this._onPickerKeydown)
      if (this._onPaste)             input.removeEventListener('paste', this._onPaste)
    }
    if (this._onFormSubmit) this.el.removeEventListener('submit', this._onFormSubmit)

    this._closePicker()
  }
}
