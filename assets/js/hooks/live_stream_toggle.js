export const LiveStreamToggle = {
  mounted() {
    const saved = localStorage.getItem("show_live_stream")
    if (saved === "true") {
      this.pushEvent("toggle_live_stream", {enabled: true})
    }
    this._clickHandler = () => {
      const current = localStorage.getItem("show_live_stream") === "true"
      localStorage.setItem("show_live_stream", String(!current))
    }
    this.el.addEventListener("click", this._clickHandler)
  },
  destroyed() {
    if (this._clickHandler) this.el.removeEventListener("click", this._clickHandler)
  }
}
