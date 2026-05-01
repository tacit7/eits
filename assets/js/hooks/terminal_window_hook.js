/**
 * TerminalWindowHook — drag/resize chrome for canvas terminal windows.
 *
 * Mirrors the drag+resize+z-index behaviour of ChatWindowHook but without
 * the chat-specific auto-scroll, message, and minimize logic. Pushes
 * "window_moved" and "window_resized" using data-terminal-id as the ID
 * (vs data-cs-id in ChatWindowHook).
 */

export const TerminalWindowHook = {
  mounted() {
    this.el.style.zIndex = "1"
    this._zIndex = "1"

    const handle = this.el.querySelector("[data-drag-handle]")
    this._initDrag(handle)
    this._initResize()

    // Raise to front on any click
    this.el.addEventListener("mousedown", () => this._raiseToFront())
  },

  _terminalId() {
    return this.el.dataset.terminalId
  },

  _initDrag(handle) {
    if (!handle) return

    let startX, startY, startLeft, startTop
    let dragPersistTimer = null

    const onMouseMove = (e) => {
      const dx = e.clientX - startX
      const dy = e.clientY - startY
      this._dragLeft = startLeft + dx
      this._dragTop  = startTop + dy
      this.el.style.left = `${this._dragLeft}px`
      this.el.style.top  = `${this._dragTop}px`
    }

    const onMouseUp = () => {
      document.removeEventListener("mousemove", onMouseMove)
      document.removeEventListener("mouseup", onMouseUp)

      clearTimeout(dragPersistTimer)
      dragPersistTimer = setTimeout(() => {
        if (this._destroyed) return
        const x = parseInt(this.el.style.left, 10) || 0
        const y = parseInt(this.el.style.top, 10)  || 0
        this.pushEvent("terminal_moved", { id: this._terminalId(), x, y })
      }, 50)
    }

    handle.addEventListener("mousedown", (e) => {
      if (e.target.closest("button")) return
      e.preventDefault()
      startX    = e.clientX
      startY    = e.clientY
      startLeft = parseInt(this.el.style.left, 10) || 0
      startTop  = parseInt(this.el.style.top, 10)  || 0
      this._dragLeft = startLeft
      this._dragTop  = startTop
      this._raiseToFront()
      document.addEventListener("mousemove", onMouseMove)
      document.addEventListener("mouseup", onMouseUp)
    })
  },

  _initResize() {
    this._width  = this.el.offsetWidth
    this._height = this.el.offsetHeight

    const observer = new ResizeObserver(() => {
      this._width  = this.el.offsetWidth
      this._height = this.el.offsetHeight
      clearTimeout(this._resizePersistTimer)
      this._resizePersistTimer = setTimeout(() => {
        if (this._destroyed) return
        const w = this.el.offsetWidth
        const h = this.el.offsetHeight
        this.pushEvent("terminal_resized", { id: this._terminalId(), w, h })
      }, 400)
    })
    observer.observe(this.el)
    this._windowResizeObserver = observer
  },

  _raiseToFront() {
    let maxZ = 1
    // Include both chat and terminal windows in z-index management
    document.querySelectorAll("[data-chat-window], [data-terminal-window]").forEach(w => {
      const z = parseInt(w.style.zIndex, 10) || 1
      if (z > maxZ) maxZ = z
      if (w !== this.el) {
        w.style.zIndex = "1"
        w.classList.remove("ring-2", "ring-primary/40")
      }
    })
    const zVal = String(Math.max(10, maxZ))
    this.el.style.zIndex = zVal
    this._zIndex = zVal
    this.el.classList.add("ring-2", "ring-primary/40")
  },

  updated() {
    // Restore JS-tracked position/size after LiveView patches the style attr
    if (this._zIndex) this.el.style.zIndex = this._zIndex
    if (this._dragLeft != null) {
      this.el.style.left = `${this._dragLeft}px`
      this.el.style.top  = `${this._dragTop}px`
    }
    if (this._width != null && this._height != null) {
      this.el.style.width  = `${this._width}px`
      this.el.style.height = `${this._height}px`
    }
  },

  destroyed() {
    this._destroyed = true
    clearTimeout(this._resizePersistTimer)
    if (this._windowResizeObserver) this._windowResizeObserver.disconnect()
  }
}
