export const GlobalKeydown = {
  mounted() {
    this._handler = (e) => {
      if (e.ctrlKey && e.key === "k") {
        const tag = document.activeElement?.tagName
        if (tag === "INPUT" || tag === "TEXTAREA" || document.activeElement?.isContentEditable) return
        e.preventDefault()
        this.pushEvent("keydown", {key: "k", ctrlKey: true})
      }
    }
    window.addEventListener("keydown", this._handler)
  },
  destroyed() {
    window.removeEventListener("keydown", this._handler)
  }
}
