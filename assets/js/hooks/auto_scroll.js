export const AutoScroll = {
  mounted() {
    this.shouldAutoScroll = true

    this._onScroll = () => {
      const { scrollHeight, scrollTop, clientHeight } = this.el
      this.shouldAutoScroll = scrollHeight - scrollTop - clientHeight <= 50
    }

    this.el.addEventListener("scroll", this._onScroll)
    this.scrollToBottom()

    this.handleEvent("new_message", () => {
      if (this.shouldAutoScroll) this.scrollToBottom()
    })
  },

  updated() {
    if (this.shouldAutoScroll) this.scrollToBottom()
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
