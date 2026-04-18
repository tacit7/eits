const SNAP_THRESHOLD = 80

function getSnapZone(cursorX, cursorY, canvasW, canvasH) {
  canvasW = Math.round(canvasW)
  canvasH = Math.round(canvasH)

  const nearLeft   = cursorX < SNAP_THRESHOLD
  const nearRight  = cursorX > canvasW - SNAP_THRESHOLD
  const nearTop    = cursorY < SNAP_THRESHOLD
  const nearBottom = cursorY > canvasH - SNAP_THRESHOLD

  const hw = Math.round(canvasW / 2)
  const hh = Math.round(canvasH / 2)

  if (nearLeft && nearTop)     return { left: 0,  top: 0,  width: hw,     height: hh }
  if (nearRight && nearTop)    return { left: hw, top: 0,  width: hw,     height: hh }
  if (nearLeft && nearBottom)  return { left: 0,  top: hh, width: hw,     height: hh }
  if (nearRight && nearBottom) return { left: hw, top: hh, width: hw,     height: hh }
  if (nearLeft)                return { left: 0,  top: 0,  width: hw,     height: canvasH }
  if (nearRight)               return { left: hw, top: 0,  width: hw,     height: canvasH }
  if (nearTop)                 return { left: 0,  top: 0,  width: canvasW, height: hh }
  if (nearBottom)              return { left: 0,  top: hh, width: canvasW, height: hh }
  return null
}

function getOrCreateSnapPreview(canvas) {
  let el = canvas.querySelector("[data-snap-preview]")
  if (!el) {
    el = document.createElement("div")
    el.dataset.snapPreview = ""
    el.className = "bg-primary/20 border-2 border-primary/40"
    el.style.cssText = "position:absolute;pointer-events:none;border-radius:0.75rem;transition:all 80ms ease;display:none;z-index:0"
    canvas.appendChild(el)
  }
  return el
}

export const ChatWindowHook = {
  mounted() {
    // --- Drag + Snap ---
    const handle = this.el.querySelector("[data-drag-handle]")
    if (handle) {
      let startX, startY, startLeft, startTop
      let dragPersistTimer = null
      let activeSnap = null
      let canvas = null
      let snapPreview = null

      const onMouseMove = (e) => {
        const dx = e.clientX - startX
        const dy = e.clientY - startY
        this.el.style.left = `${startLeft + dx}px`
        this.el.style.top  = `${startTop  + dy}px`

        if (canvas && snapPreview) {
          const rect = canvas.getBoundingClientRect()
          activeSnap = getSnapZone(e.clientX - rect.left, e.clientY - rect.top, rect.width, rect.height)
          if (activeSnap) {
            snapPreview.style.display = "block"
            snapPreview.style.left    = `${activeSnap.left}px`
            snapPreview.style.top     = `${activeSnap.top}px`
            snapPreview.style.width   = `${activeSnap.width}px`
            snapPreview.style.height  = `${activeSnap.height}px`
          } else {
            snapPreview.style.display = "none"
          }
        }
      }

      const onMouseUp = () => {
        document.removeEventListener("mousemove", onMouseMove)
        document.removeEventListener("mouseup", onMouseUp)
        if (snapPreview) snapPreview.style.display = "none"

        const snap = activeSnap
        activeSnap = null

        clearTimeout(dragPersistTimer)
        dragPersistTimer = setTimeout(() => {
          let x = parseInt(this.el.style.left, 10) || 0
          let y = parseInt(this.el.style.top, 10)  || 0

          if (snap) {
            x = snap.left
            y = snap.top
            this.el.style.left   = `${x}px`
            this.el.style.top    = `${y}px`
            this.el.style.width  = `${snap.width}px`
            this.el.style.height = `${snap.height}px`
            this.pushEventTo(this.el, "window_resized", {
              id: this.el.dataset.csId, w: snap.width, h: snap.height
            })
          }

          this.pushEventTo(this.el, "window_moved", {
            id: this.el.dataset.csId, x, y
          })
        }, 50)
      }

      handle.addEventListener("mousedown", (e) => {
        e.preventDefault()
        startX    = e.clientX
        startY    = e.clientY
        startLeft = parseInt(this.el.style.left, 10) || 0
        startTop  = parseInt(this.el.style.top, 10)  || 0

        canvas      = this.el.closest("[data-canvas-area]")
        snapPreview = canvas ? getOrCreateSnapPreview(canvas) : null

        document.querySelectorAll("[data-chat-window]").forEach(w => { w.style.zIndex = "1" })
        this.el.style.zIndex = "10"

        document.addEventListener("mousemove", onMouseMove)
        document.addEventListener("mouseup", onMouseUp)
      })
    }

    // --- Resize (native browser handle) ---
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

    const minimizeBtn = this.el.querySelector("[data-minimize-btn]")
    if (minimizeBtn) {
      this._minimized = this.el.dataset.windowMinimized === "true"
      if (this._minimized) this._applyMinimized()
      minimizeBtn.addEventListener("mousedown", (e) => {
        e.stopPropagation()
        e.preventDefault()
      })
      minimizeBtn.addEventListener("click", (e) => {
        e.stopPropagation()
        this._minimized = !this._minimized
        const body = this.el.querySelector("[data-chat-body]")
        const footer = this.el.querySelector("[data-chat-footer]")
        const handle = this.el.querySelector("[data-drag-handle]")
        if (this._minimized) {
          this.el.dataset.savedHeight = this.el.offsetHeight + "px"
          this.el.dataset.windowMinimized = "true"
          this._applyMinimized()
        } else {
          delete this.el.dataset.windowMinimized
          if (body) body.style.display = ""
          if (footer) footer.style.display = ""
          this.el.style.resize = "both"
          this.el.style.overflow = "auto"
          if (this.el.dataset.savedHeight) {
            this.el.style.height = this.el.dataset.savedHeight
          }
          if (this._resizeObserver) this._resizeObserver.observe(this.el)
        }
      })
    }

  },

  _applyMinimized() {
    const body = this.el.querySelector("[data-chat-body]")
    const footer = this.el.querySelector("[data-chat-footer]")
    const handle = this.el.querySelector("[data-drag-handle]")
    if (body) body.style.display = "none"
    if (footer) footer.style.display = "none"
    this.el.style.resize = "none"
    this.el.style.overflow = "hidden"
    const headerH = handle ? handle.offsetHeight : 40
    if (this._resizeObserver) this._resizeObserver.disconnect()
    this.el.style.height = headerH + "px"
  },

  updated() {
    if (this._minimized) this._applyMinimized()
  },

  destroyed() {
    if (this._resizeObserver) this._resizeObserver.disconnect()
  }
}
