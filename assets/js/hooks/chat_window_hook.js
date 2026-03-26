export const ChatWindowHook = {
  mounted() {
    // --- Drag ---
    const handle = this.el.querySelector("[data-drag-handle]")
    if (handle) {
      let startX, startY, startLeft, startTop
      let dragPersistTimer = null

      const onMouseMove = (e) => {
        const dx = e.clientX - startX
        const dy = e.clientY - startY
        this.el.style.left = `${startLeft + dx}px`
        this.el.style.top = `${startTop + dy}px`
      }

      const onMouseUp = () => {
        document.removeEventListener("mousemove", onMouseMove)
        document.removeEventListener("mouseup", onMouseUp)
        clearTimeout(dragPersistTimer)
        dragPersistTimer = setTimeout(() => {
          this.pushEventTo(this.el, "window_moved", {
            id: this.el.dataset.csId,
            x: parseInt(this.el.style.left, 10) || 0,
            y: parseInt(this.el.style.top, 10) || 0
          })
        }, 300)
      }

      handle.addEventListener("mousedown", (e) => {
        e.preventDefault()
        startX = e.clientX
        startY = e.clientY
        startLeft = parseInt(this.el.style.left, 10) || 0
        startTop = parseInt(this.el.style.top, 10) || 0

        document.querySelectorAll("[data-chat-window]").forEach(w => { w.style.zIndex = "1" })
        this.el.style.zIndex = "10"

        document.addEventListener("mousemove", onMouseMove)
        document.addEventListener("mouseup", onMouseUp)
      })
    }

    // --- Resize ---
    let resizePersistTimer = null
    const observer = new ResizeObserver(() => {
      clearTimeout(resizePersistTimer)
      resizePersistTimer = setTimeout(() => {
        this.pushEventTo(this.el, "window_resized", {
          id: this.el.dataset.csId,
          w: this.el.offsetWidth,
          h: this.el.offsetHeight
        })
      }, 400)
    })
    observer.observe(this.el)
    this._resizeObserver = observer
  },

  destroyed() {
    if (this._resizeObserver) this._resizeObserver.disconnect()
  }
}
