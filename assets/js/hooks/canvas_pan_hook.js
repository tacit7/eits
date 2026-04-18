export const CanvasPanHook = {
  mounted() {
    this._panX = 0
    this._panY = 0
    this._panning = false
    this._startX = 0
    this._startY = 0
    this._spaceDown = false

    const onKeyDown = (e) => {
      if (e.code === "Space" && !e.target.matches("input, textarea, [contenteditable]")) {
        e.preventDefault()
        this._spaceDown = true
        this.el.style.cursor = "grab"
      }
    }
    const onKeyUp = (e) => {
      if (e.code === "Space") {
        this._spaceDown = false
        if (!this._panning) this.el.style.cursor = ""
      }
    }
    const onMouseDown = (e) => {
      if (!this._spaceDown) return
      e.preventDefault()
      this._panning = true
      this._startX = e.clientX - this._panX
      this._startY = e.clientY - this._panY
      this.el.style.cursor = "grabbing"
    }
    const onMouseMove = (e) => {
      if (!this._panning) return
      this._panX = e.clientX - this._startX
      this._panY = e.clientY - this._startY
      this.el.style.transform = "translate(" + this._panX + "px, " + this._panY + "px)"
    }
    const onMouseUp = () => {
      if (!this._panning) return
      this._panning = false
      this.el.style.cursor = this._spaceDown ? "grab" : ""
    }

    window.addEventListener("keydown", onKeyDown)
    window.addEventListener("keyup", onKeyUp)
    this.el.addEventListener("mousedown", onMouseDown)
    window.addEventListener("mousemove", onMouseMove)
    window.addEventListener("mouseup", onMouseUp)

    this._cleanup = () => {
      window.removeEventListener("keydown", onKeyDown)
      window.removeEventListener("keyup", onKeyUp)
      this.el.removeEventListener("mousedown", onMouseDown)
      window.removeEventListener("mousemove", onMouseMove)
      window.removeEventListener("mouseup", onMouseUp)
    }
  },
  destroyed() {
    if (this._cleanup) this._cleanup()
  }
}
