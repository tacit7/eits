export const AutoScroll = {
  mounted() {
    this.shouldAutoScroll = true
    this._loadingMore = false
    this._mounted = false
    this._updating = false

    this._onScroll = () => {
      // Ignore scroll events fired by LiveView DOM swaps. The container's
      // scrollTop briefly resets during patch, which would otherwise flip
      // shouldAutoScroll to false right before updated() runs.
      if (this._updating) return

      const { scrollHeight, scrollTop, clientHeight } = this.el
      this.shouldAutoScroll = scrollHeight - scrollTop - clientHeight <= 50

      // Auto-load older messages when scrolled near the top
      if (this._mounted && !this._loadingMore && scrollTop < 100 && this.el.dataset.hasMore === "true") {
        this._loadingMore = true
        this.pushEvent("load_more_messages", {})
      }
    }

    this.el.addEventListener("scroll", this._onScroll, { passive: true })
    this.scrollToBottom()
    requestAnimationFrame(() => { this._mounted = true })

    this.handleEvent("new_message", () => {
      if (this.shouldAutoScroll) this.scrollToBottom()
    })
  },

  beforeUpdate() {
    this._prevScrollHeight = this.el.scrollHeight
    this._prevScrollTop = this.el.scrollTop
    this._prevClientHeight = this.el.clientHeight
    // Lock shouldAutoScroll to its pre-patch value computed from actual
    // pre-patch geometry. Prevents a transient scroll event during the swap
    // from flipping the flag before updated() reads it.
    this.shouldAutoScroll =
      this._prevScrollHeight - this._prevScrollTop - this._prevClientHeight <= 50
    this._updating = true
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
    // Release the scroll listener after the browser has settled the swap
    requestAnimationFrame(() => { this._updating = false })
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
