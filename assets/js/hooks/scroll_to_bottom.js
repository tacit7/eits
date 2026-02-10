export const ScrollToBottom = {
  mounted() {
    this.scrollToBottom()
    this.isNearBottom = true
  },
  beforeUpdate() {
    const threshold = 100
    this.isNearBottom =
      (this.el.scrollHeight - this.el.scrollTop - this.el.clientHeight) < threshold
    this.prevScrollHeight = this.el.scrollHeight
    this.prevScrollTop = this.el.scrollTop
  },
  updated() {
    if (this.isNearBottom) {
      this.scrollToBottom()
    } else {
      // Preserve scroll position when older messages are prepended
      const heightDiff = this.el.scrollHeight - this.prevScrollHeight
      if (heightDiff > 0) {
        this.el.scrollTop = this.prevScrollTop + heightDiff
      }
    }
  },
  scrollToBottom() {
    requestAnimationFrame(() => {
      this.el.scrollTop = this.el.scrollHeight
    })
  }
}
