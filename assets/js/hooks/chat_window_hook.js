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
    // z-index is not rendered server-side; initialize it here so it survives patches.
    // data-saved-z-index acts as cross-hook shared memory — readable by peer _raiseToFront calls.
    this.el.style.zIndex = "1"
    this._zIndex = "1"
    this.el.dataset.savedZIndex = "1"

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
        this._dragLeft = startLeft + dx
        this._dragTop  = startTop  + dy
        this.el.style.left = `${this._dragLeft}px`
        this.el.style.top  = `${this._dragTop}px`

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
        this._dragging = false
        document.removeEventListener("mousemove", onMouseMove)
        document.removeEventListener("mouseup", onMouseUp)
        if (snapPreview) snapPreview.style.display = "none"

        const snap = activeSnap
        activeSnap = null

        clearTimeout(dragPersistTimer)
        dragPersistTimer = setTimeout(() => {
          let x = parseInt(this.el.style.left, 10) || 0
          let y = parseInt(this.el.style.top, 10)  || 0

          if (snap && !this._minimized) {
            x = snap.left
            y = snap.top
            this.el.style.left   = `${x}px`
            this.el.style.top    = `${y}px`
            this.el.style.width  = `${snap.width}px`
            this.el.style.height = `${snap.height}px`
            this.pushEventTo(this.el, "window_resized", {
              id: this.el.dataset.csId, w: snap.width, h: snap.height
            })
          } else if (snap && this._minimized) {
            x = snap.left
            y = snap.top
            this.el.style.left = `${x}px`
            this.el.style.top  = `${y}px`
          }

          this.pushEventTo(this.el, "window_moved", {
            id: this.el.dataset.csId, x, y
          })
        }, 50)
      }

      handle.addEventListener("mousedown", (e) => {
        e.preventDefault()
        this._dragging = true
        startX    = e.clientX
        startY    = e.clientY
        startLeft = parseInt(this.el.style.left, 10) || 0
        startTop  = parseInt(this.el.style.top, 10)  || 0
        // Initialize to current position so updated() never writes undefinedpx
        // if a LiveView patch fires before the first mousemove event.
        this._dragLeft = startLeft
        this._dragTop  = startTop

        canvas      = this.el.closest("[data-canvas-area]")
        snapPreview = canvas ? getOrCreateSnapPreview(canvas) : null

        this._raiseToFront()

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
          const unreadDot = this.el.querySelector("[data-unread-dot]")
          if (unreadDot) unreadDot.remove()
        }
      })
    }

    const maximizeBtn = this.el.querySelector("[data-maximize-btn]")
    if (maximizeBtn) {
      this._maximized = false
      maximizeBtn.addEventListener("mousedown", (e) => {
        e.stopPropagation()
        e.preventDefault()
      })
      maximizeBtn.addEventListener("click", (e) => {
        e.stopPropagation()
        this._maximized = !this._maximized
        const canvas = this.el.closest("[data-canvas-area]")
        if (this._maximized && canvas) {
          this.el.dataset.savedLeft = this.el.style.left
          this.el.dataset.savedTop = this.el.style.top
          this.el.dataset.savedWidth = this.el.style.width
          this.el.dataset.savedMaxHeight = this.el.style.height
          this.el.style.left = "0px"
          this.el.style.top = "0px"
          this.el.style.width = canvas.offsetWidth + "px"
          this.el.style.height = canvas.offsetHeight + "px"
          this.el.style.resize = "none"
          this.el.style.zIndex = "20"
          this._zIndex = "20"
          this.el.dataset.savedZIndex = "20"
        } else {
          this.el.style.left = this.el.dataset.savedLeft || "0px"
          this.el.style.top = this.el.dataset.savedTop || "0px"
          this.el.style.width = this.el.dataset.savedWidth || ""
          this.el.style.height = this.el.dataset.savedMaxHeight || ""
          this.el.style.resize = "both"
          this.el.style.zIndex = "1"
          this._zIndex = "1"
          this.el.dataset.savedZIndex = "1"
        }
      })
    }

    // --- Click-to-focus: raise window on any mousedown ---
    this.el.addEventListener("mousedown", () => { this._raiseToFront() })

    document.addEventListener("mousedown", this._onBlurWindows = (e) => {
      if (!e.target.closest("[data-chat-window]")) {
        document.querySelectorAll("[data-chat-window]").forEach(w => {
          w.classList.remove("ring-2", "ring-primary/40")
        })
      }
    })

    // --- Auto-scroll ---
    this._autoScroll = true
    this._newMsgCount = 0
    const chatBody = this.el.querySelector("[data-chat-body]")
    const autoScrollBtn = this.el.querySelector("[data-autoscroll-btn]")
    const newMsgPill = this.el.querySelector("[data-new-msg-pill]")

    const scrollToBottom = () => {
      if (chatBody) chatBody.scrollTop = chatBody.scrollHeight
    }

    const setAutoScroll = (enabled) => {
      this._autoScroll = enabled
      if (autoScrollBtn) {
        autoScrollBtn.classList.toggle("text-base-content/30", enabled)
        autoScrollBtn.classList.toggle("text-warning", !enabled)
      }
      if (enabled) {
        this._newMsgCount = 0
        if (newMsgPill) newMsgPill.classList.add("hidden")
      }
    }

    if (chatBody) {
      scrollToBottom()
      chatBody.addEventListener("scroll", () => {
        const atBottom = chatBody.scrollTop + chatBody.clientHeight >= chatBody.scrollHeight - 10
        const scrolledUp = chatBody.scrollTop + chatBody.clientHeight < chatBody.scrollHeight - 20
        if (atBottom && !this._autoScroll) {
          setAutoScroll(true)
        } else if (scrolledUp && this._autoScroll) {
          setAutoScroll(false)
        }
      })
    }

    if (autoScrollBtn) {
      autoScrollBtn.addEventListener("click", () => {
        setAutoScroll(true)
        scrollToBottom()
      })
    }

    if (newMsgPill) {
      newMsgPill.addEventListener("click", () => {
        setAutoScroll(true)
        scrollToBottom()
      })
    }

    // When the user sends a message, always scroll to bottom regardless of
    // where they were scrolled. The _autoScroll flag may be stale if they
    // scrolled up at any point while reading — reset it on submit.
    const chatForm = this.el.querySelector("[data-chat-footer] form")
    if (chatForm) {
      chatForm.addEventListener("submit", () => {
        setAutoScroll(true)
        requestAnimationFrame(() => scrollToBottom())
      })
    }

    this.handleEvent("messages-updated-" + this.el.dataset.csId, () => {
      if (this._minimized) {
        const handle = this.el.querySelector("[data-drag-handle]")
        if (handle && !handle.querySelector("[data-unread-dot]")) {
          const dot = document.createElement("span")
          dot.dataset.unreadDot = ""
          dot.className = "w-2 h-2 rounded-full bg-error animate-pulse flex-shrink-0 ml-1"
          const nameSpan = handle.querySelector("span.truncate") || handle.querySelector("span")
          if (nameSpan) nameSpan.after(dot)
          else handle.appendChild(dot)
        }
      } else if (this._autoScroll) {
        scrollToBottom()
      } else {
        this._newMsgCount = (this._newMsgCount || 0) + 1
        if (newMsgPill) {
          const n = this._newMsgCount
          newMsgPill.textContent = `\u2193 ${n} new message${n > 1 ? "s" : ""}`
          newMsgPill.classList.remove("hidden")
        }
      }
    })

  },

  _raiseToFront() {
    let maxZ = 1
    document.querySelectorAll("[data-chat-window]").forEach(w => {
      const z = parseInt(w.style.zIndex, 10) || 1
      if (z > maxZ) maxZ = z
      w.style.zIndex = "1"
      w.dataset.savedZIndex = "1"  // update shared memory so peers' updated() won't undo this
      w.classList.remove("ring-2", "ring-primary/40")
    })
    const zVal = this._maximized ? "20" : String(Math.max(10, maxZ))
    this.el.style.zIndex = zVal
    this._zIndex = zVal
    this.el.dataset.savedZIndex = zVal
    this.el.classList.add("ring-2", "ring-primary/40")
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
    // LiveView patches the style attr but doesn't render z-index — restore it.
    // Prefer dataset.savedZIndex (cross-hook authoritative) over instance memory.
    const saved = this.el.dataset.savedZIndex
    if (saved) {
      this.el.style.zIndex = saved
      this._zIndex = saved
    } else if (this._zIndex) {
      this.el.style.zIndex = this._zIndex
    }

    // If the user is mid-drag, LiveView may have snapped position back to DB values.
    // Restore the visual position from the in-flight drag state.
    if (this._dragging) {
      this.el.style.left = `${this._dragLeft}px`
      this.el.style.top  = `${this._dragTop}px`
    }

    if (this._minimized) this._applyMinimized()
  },

  destroyed() {
    if (this._resizeObserver) this._resizeObserver.disconnect()
    document.removeEventListener("mousedown", this._onBlurWindows)
  }
}
