// DmComposer: keyboard-aware layout + Aa format toolbar for the DM message form.
//
// Keyboard layout: on mobile, when the software keyboard opens the visual viewport
// height shrinks while window.innerHeight stays fixed. This hook listens to
// visualViewport resize/scroll events and keeps the message list scrolled to
// the bottom so the composer is always visible above the keyboard.
//
// Format toolbar: the Aa button toggles a format strip. Each button wraps the
// current textarea selection with markdown syntax. Keyboard shortcuts:
//   Cmd/Ctrl+B  → bold
//   Cmd/Ctrl+I  → italic
//   Cmd/Ctrl+E  → inline code
//   Cmd/Ctrl+Shift+E → code block

export const DmComposer = {
  mounted() {
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
    const input  = document.getElementById('message-input')

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

    if (input) {
      this._onKeydown = (e) => {
        const mod = e.metaKey || e.ctrlKey
        if (!mod) return

        if (e.key === 'b' || e.key === 'B') {
          e.preventDefault()
          this._applyFormat(input, 'bold')
        } else if (e.key === 'i' || e.key === 'I') {
          e.preventDefault()
          this._applyFormat(input, 'italic')
        } else if ((e.key === 'e' || e.key === 'E') && e.shiftKey) {
          e.preventDefault()
          this._applyFormat(input, 'code-block')
        } else if (e.key === 'e' || e.key === 'E') {
          e.preventDefault()
          this._applyFormat(input, 'code')
        }
      }
      input.addEventListener('keydown', this._onKeydown)
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
        // No selection — place cursor between markers
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
      // Cursor on the empty line between fences
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

    // Select 'url' placeholder so user can type over it
    const urlStart = start + label.length + 3
    ta.setSelectionRange(urlStart, urlStart + 3)

    ta.dispatchEvent(new Event('input', { bubbles: true }))
    ta.focus()
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

    if (toggle && this._onToggle) toggle.removeEventListener('click', this._onToggle)
    if (bar && this._onFmtClick) bar.removeEventListener('click', this._onFmtClick)
    if (input && this._onKeydown) input.removeEventListener('keydown', this._onKeydown)
  }
}
