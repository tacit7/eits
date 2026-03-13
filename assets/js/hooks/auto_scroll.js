export const AutoScroll = {
  mounted() {
    this.shouldAutoScroll = true
    this._loadingMore = false

    this._onScroll = () => {
      const { scrollHeight, scrollTop, clientHeight } = this.el
      this.shouldAutoScroll = scrollHeight - scrollTop - clientHeight <= 50

      // Auto-load older messages when scrolled near the top
      if (!this._loadingMore && scrollTop < 100 && this.el.dataset.hasMore === "true") {
        this._loadingMore = true
        this.pushEvent("load_more_messages", {})
      }
    }

    this.el.addEventListener("scroll", this._onScroll, { passive: true })
    this.scrollToBottom()

    this.handleEvent("new_message", () => {
      if (this.shouldAutoScroll) this.scrollToBottom()
    })
  },

  beforeUpdate() {
    this._prevScrollHeight = this.el.scrollHeight
    this._prevScrollTop = this.el.scrollTop
  },

  updated() {
    if (this.shouldAutoScroll) {
      this.scrollToBottom()
    } else {
      // Preserve scroll position when older messages are prepended
      const heightDiff = this.el.scrollHeight - this._prevScrollHeight
      if (heightDiff > 0) {
        this.el.scrollTop = this._prevScrollTop + heightDiff
      }
    }
    // Reset load guard after DOM update so next scroll triggers work
    this._loadingMore = false
  },

  destroyed() {
    this.el.removeEventListener("scroll", this._onScroll)
  },

  scrollToBottom() {
    requestAnimationFrame(() => {
      this.el.scrollTop = this.el.scrollHeight
    })
  }
}
