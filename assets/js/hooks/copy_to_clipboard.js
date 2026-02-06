export const CopyToClipboard = {
  mounted() {
    this.handleClick = () => {
      const id = this.el.dataset.sessionId
      if (!id) return

      if (navigator.clipboard?.writeText) {
        navigator.clipboard
          .writeText(id)
          .catch((err) => console.error("Failed to copy session id", err))
      }
    }

    this.el.addEventListener("click", this.handleClick)
  },

  destroyed() {
    if (this.handleClick) {
      this.el.removeEventListener("click", this.handleClick)
    }
  }
}
