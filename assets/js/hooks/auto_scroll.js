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
    // Scroll synchronously so scrollTop is correct before any beforeUpdate()
    // fires. The RAF below catches late-expanding content (images, transitions).
    this.el.scrollTop = this.el.scrollHeight
    this.scrollToBottom()

    // Watch for content growth from non-LiveView sources (LocalTime hooks
    // formatting times, phx-mounted transitions, late-arriving stream
    // patches, image loads). Without this the initial scrollToBottom can
    // fire before all content has expanded, leaving the view stuck partway
    // up. While shouldAutoScroll is true, keep snapping to the bottom as
    // the container grows.
    if (typeof ResizeObserver !== "undefined") {
      this._lastScrollHeight = this.el.scrollHeight
      this._resizeObserver = new ResizeObserver(() => {
        if (this.el.scrollHeight === this._lastScrollHeight) return
        this._lastScrollHeight = this.el.scrollHeight
        if (this.shouldAutoScroll) this.scrollToBottom()
      })
      this._resizeObserver.observe(this.el)
      // Also observe each direct child — ResizeObserver on the container
      // alone fires only when the container's own size changes, not when
      // children grow inside an overflow:auto parent.
      for (const child of this.el.children) {
        this._resizeObserver.observe(child)
      }
    }

    // Mark ready on the next frame so the load-more guard doesn't fire
    // from the initial scroll-to-bottom.
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
    // Re-observe children — LiveView patches may have replaced them.
    if (this._resizeObserver) {
      this._resizeObserver.disconnect()
      this._resizeObserver.observe(this.el)
      for (const child of this.el.children) {
        this._resizeObserver.observe(child)
      }
      this._lastScrollHeight = this.el.scrollHeight
    }
    // Reset load guard after DOM update so next scroll triggers work
    this._loadingMore = false
    // Release the scroll listener after the browser has settled the swap
    requestAnimationFrame(() => { this._updating = false })
  },

  destroyed() {
    this.el.removeEventListener("scroll", this._onScroll)
    if (this._resizeObserver) {
      this._resizeObserver.disconnect()
      this._resizeObserver = null
    }
  },

  scrollToBottom() {
    requestAnimationFrame(() => {
      this.el.scrollTop = this.el.scrollHeight
    })
  }
}
