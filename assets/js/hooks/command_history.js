// Phoenix only supports one phx-hook per element. SlashCommandPopup is composed here
// via SlashCommandPopup.mounted.call(this) so both hooks share the same LiveView hook
// context (this.el, this.handleEvent, etc.) without needing a second phx-hook attribute.
import {SlashCommandPopup} from "./slash_command_popup"

export const CommandHistory = {
  mounted() {
    this.history = []
    this.historyIndex = -1
    this.currentInput = ''

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
      if (this.history.length > 100) {
        this.history.pop()
      }
    }
    this.historyIndex = -1
    this.currentInput = ''
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
  }
}
