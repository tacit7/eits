// DmComposer: keyboard-aware layout hook for the DM message form.
//
// On mobile, when the software keyboard opens the visual viewport height
// shrinks while window.innerHeight stays fixed. This hook listens to
// visualViewport resize/scroll events and keeps the message list scrolled
// to the bottom so the composer is always visible above the keyboard.
//
// It also sets --keyboard-height on <html> so CSS can respond if needed.

export const DmComposer = {
  mounted() {
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
        // If within 120px of bottom, keep anchored there when viewport resizes
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
  },

  destroyed() {
    if (window.visualViewport) {
      window.visualViewport.removeEventListener('resize', this._onVVChange)
      window.visualViewport.removeEventListener('scroll', this._onVVChange)
    }
    document.documentElement.style.removeProperty('--keyboard-height')
  }
}
