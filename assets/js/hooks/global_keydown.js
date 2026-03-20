export const GlobalKeydown = {
  mounted() {
    console.log("[GlobalKeydown] mounted on", this.el.id)
    this._handler = (e) => {
      if (e.ctrlKey && e.key === "k") {
        const tag = document.activeElement?.tagName
        if (tag === "INPUT" || tag === "TEXTAREA" || document.activeElement?.isContentEditable) return
        e.preventDefault()
        console.log("[GlobalKeydown] Ctrl+K fired, pushing event")
        this.pushEvent("keydown", {key: "k", ctrlKey: true})
      }
    }
    window.addEventListener("keydown", this._handler)
  },
  destroyed() {
    window.removeEventListener("keydown", this._handler)
  }
}
