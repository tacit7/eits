export const CommandHistory = {
  mounted() {
    this.history = []
    this.historyIndex = -1
    this.currentInput = ''

    this.el.addEventListener('keydown', (e) => {
      // Shift+Enter - insert newline (default textarea behavior, just auto-resize)
      if (e.key === 'Enter' && e.shiftKey) {
        // Let default happen (inserts newline), then resize
        requestAnimationFrame(() => this.autoResize())
        return
      }
      // Enter - submit form
      if (e.key === 'Enter' && !e.shiftKey) {
        e.preventDefault()
        const value = this.el.value.trim()
        if (value) {
          this.addToHistory(value)
          this.el.form.dispatchEvent(new Event('submit', { bubbles: true, cancelable: true }))
        }
        return
      }
      // Ctrl+P or Up Arrow - Previous command
      if ((e.ctrlKey && e.key === 'p') || e.key === 'ArrowUp') {
        e.preventDefault()
        this.navigateHistory('prev')
      }
      // Ctrl+N or Down Arrow - Next command
      else if ((e.ctrlKey && e.key === 'n') || e.key === 'ArrowDown') {
        e.preventDefault()
        this.navigateHistory('next')
      }
    })

    // Auto-resize on input
    this.el.addEventListener('input', () => this.autoResize())

    // Listen for clear-input event from server
    this.handleEvent('clear-input', () => {
      this.el.value = ''
      this.historyIndex = -1
      this.currentInput = ''
      this.autoResize()
      this.el.focus()
    })
  },

  autoResize() {
    this.el.style.height = 'auto'
    this.el.style.height = Math.min(this.el.scrollHeight, 160) + 'px'
  },

  navigateHistory(direction) {
    // Save current input if we're at the end
    if (this.historyIndex === -1) {
      this.currentInput = this.el.value
    }

    if (direction === 'prev') {
      // Move backwards through history
      if (this.historyIndex < this.history.length - 1) {
        this.historyIndex++
        this.el.value = this.history[this.historyIndex]
      }
    } else if (direction === 'next') {
      // Move forwards through history
      if (this.historyIndex > 0) {
        this.historyIndex--
        this.el.value = this.history[this.historyIndex]
      } else if (this.historyIndex === 0) {
        // Return to current input
        this.historyIndex = -1
        this.el.value = this.currentInput
      }
    }

    // Move cursor to end
    this.el.setSelectionRange(this.el.value.length, this.el.value.length)
    this.autoResize()
  },

  addToHistory(command) {
    // Don't add duplicates of the last command
    if (this.history.length === 0 || this.history[0] !== command) {
      // Add to beginning of history
      this.history.unshift(command)
      // Limit history to 100 commands
      if (this.history.length > 100) {
        this.history.pop()
      }
    }
    // Reset history navigation
    this.historyIndex = -1
    this.currentInput = ''
  }
}
