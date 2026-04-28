import { saveWindowLayout, saveWindowZ, saveWindowMinimized, loadWindowLayout } from './canvas_layout_hook'

const SNAP_THRESHOLD = 40

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

    // Restore last-known position/size/z from localStorage (set by layout buttons, drag, resize, and focus).
    const csId = this.el.dataset.csId
    const saved = loadWindowLayout(csId)
    if (saved) {
      // Guard against corrupt values (e.g. layout computed when canvas area was collapsed)
      const MIN_W = 120, MIN_H = 120
      if (saved.w != null && (saved.w < MIN_W || saved.h < MIN_H)) {
        // Wipe the bad entry so DB defaults take over; don't apply it
        try { localStorage.removeItem(`cw_${csId}`) } catch (_) {}
      } else {
        if (saved.x != null) {
          this.el.style.left   = `${saved.x}px`
          this.el.style.top    = `${saved.y}px`
          this._dragLeft = saved.x
          this._dragTop  = saved.y
        }
        if (saved.w != null) {
          this.el.style.width  = `${saved.w}px`
          this.el.style.height = `${saved.h}px`
          this._width  = saved.w
          this._height = saved.h
        }
        if (saved.z != null) {
          this.el.style.zIndex = String(saved.z)
          this._zIndex = String(saved.z)
          this.el.dataset.savedZIndex = String(saved.z)
        }
        // Restore minimized state — keeps window hidden across page reloads
        // until the user explicitly restores via the canvas flyout
        if (saved.minimized) {
          this._minimized = true
          this.el.style.display = "none"
        }
      }
    }

    // Keep instance vars in sync when a layout button repositions this window.
    this.el.addEventListener('canvas:layout-applied', (e) => {
      const { x, y, w, h } = e.detail
      this._width    = w
      this._height   = h
      this._dragLeft = x
      this._dragTop  = y
    })

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
          if (this._destroyed) return
          let x = parseInt(this.el.style.left, 10) || 0
          let y = parseInt(this.el.style.top, 10)  || 0

          if (snap && !this._minimized) {
            x = snap.left
            y = snap.top
            this.el.style.left   = `${x}px`
            this.el.style.top    = `${y}px`
            this.el.style.width  = `${snap.width}px`
            this.el.style.height = `${snap.height}px`
            this.pushEvent("window_resized", {
              id: this.el.dataset.csId, w: snap.width, h: snap.height
            })
          } else if (snap && this._minimized) {
            x = snap.left
            y = snap.top
            this.el.style.left = `${x}px`
            this.el.style.top  = `${y}px`
          }

          this.pushEvent("window_moved", {
            id: this.el.dataset.csId, x, y
          })
          saveWindowLayout(this.el.dataset.csId, x, y,
            parseInt(this.el.style.width, 10) || this._width || 0,
            parseInt(this.el.style.height, 10) || this._height || 0)
        }, 50)
      }

      handle.addEventListener("mousedown", (e) => {
        // Let buttons inside the handle handle their own clicks (minimize, maximize, close).
        if (e.target.closest('button')) return
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

    // Track current dimensions so updated() can restore them after a LiveView
    // patch (which re-writes the style attr from DB values and would otherwise
    // snap the window back to its last-saved size mid-interaction).
    this._width  = this.el.offsetWidth
    this._height = this.el.offsetHeight

    // --- Resize (native browser handle) ---
    const observer = new ResizeObserver(() => {
      // Update tracked dims immediately — don't wait for the persist debounce —
      // so updated() restores correctly if a message is sent mid-resize.
      this._width  = this.el.offsetWidth
      this._height = this.el.offsetHeight
      clearTimeout(this._resizePersistTimer)
      this._resizePersistTimer = setTimeout(() => {
        if (this._destroyed) return
        const w = this.el.offsetWidth
        const h = this.el.offsetHeight
        this.pushEvent("window_resized", {
          id: this.el.dataset.csId, w, h
        })
        saveWindowLayout(this.el.dataset.csId,
          parseInt(this.el.style.left, 10) || 0,
          parseInt(this.el.style.top, 10)  || 0,
          w, h)
      }, 400)
    })
    observer.observe(this.el)
    this._resizeObserver = observer

    const minimizeBtn = this.el.querySelector("[data-minimize-btn]")
    if (minimizeBtn) {
      if (this._minimized == null) this._minimized = false
      minimizeBtn.addEventListener("mousedown", (e) => {
        e.stopPropagation()
        e.preventDefault()
      })
      minimizeBtn.addEventListener("click", (e) => {
        e.stopPropagation()
        this._applyMinimized()
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
          saveWindowZ(this.el.dataset.csId, 20)
        } else {
          this.el.style.left = this.el.dataset.savedLeft || "0px"
          this.el.style.top = this.el.dataset.savedTop || "0px"
          this.el.style.width = this.el.dataset.savedWidth || ""
          this.el.style.height = this.el.dataset.savedMaxHeight || ""
          this.el.style.resize = "both"
          this.el.style.zIndex = "1"
          this._zIndex = "1"
          this.el.dataset.savedZIndex = "1"
          saveWindowZ(this.el.dataset.csId, 1)
        }
      })
    }

    // --- Click-to-focus: raise window on any mousedown ---
    this.el.addEventListener("mousedown", () => { this._raiseToFront() })

    // --- Rail icon click: focus this window by session ID ---
    window.addEventListener("canvas:focus-session", this._onFocusSession = (e) => {
      const targetId = String(e.detail?.sessionId)
      if (targetId && targetId === this.el.dataset.sessionId) {
        if (this._minimized) {
          this._restoreFromMinimized()
        } else {
          this._raiseToFront()
        }
      }
    })

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

    // Re-query [data-chat-body] each call to avoid stale references after patches.
    // Also scroll this.el as a fallback: if the flex layout collapses chatBody to
    // zero height, this.el (overflow:auto) becomes the visible scroll container.
    const scrollToBottom = () => {
      const body = this.el.querySelector("[data-chat-body]")
      if (body) body.scrollTop = body.scrollHeight
      // Fallback: harmless when this.el has no overflow (scrollTop clamps to 0)
      this.el.scrollTop = this.el.scrollHeight
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

      // Detect intentional user scroll (wheel/touch) so the post-mount force-scroll
      // doesn't override a deliberate scroll-up within the settling window.
      this._userScrolled = false
      chatBody.addEventListener('wheel', () => { this._userScrolled = true }, { passive: true, once: true })
      chatBody.addEventListener('touchstart', () => { this._userScrolled = true }, { passive: true, once: true })

      // Post-mount force-scroll: fires after LocalTime hooks, markdown rendering,
      // and other late-rendering content have had time to expand the scrollHeight.
      // Uses two staggered rAF+timeout passes to cover async rendering pipelines.
      // Only fires if the user hasn't intentionally scrolled during the settling window.
      const forceScrollIfUntouched = () => {
        if (this._userScrolled || this._minimized) return
        const body = this.el.querySelector("[data-chat-body]")
        if (body) {
          setAutoScroll(true)
          body.scrollTop = body.scrollHeight
        }
      }
      requestAnimationFrame(() => {
        forceScrollIfUntouched()
        setTimeout(forceScrollIfUntouched, 150)
        setTimeout(forceScrollIfUntouched, 400)
      })

      // ResizeObserver catches late content growth (LocalTime hooks, markdown
      // rendering, code block expansion) that runs after the initial scrollToBottom.
      if (typeof ResizeObserver !== "undefined") {
        this._lastScrollHeight = chatBody.scrollHeight
        this._resizeObserver = new ResizeObserver(() => {
          if (this._minimized) return
          const body = this.el.querySelector("[data-chat-body]")
          if (!body || body.scrollHeight === this._lastScrollHeight) return
          this._lastScrollHeight = body.scrollHeight
          if (this._autoScroll) body.scrollTop = body.scrollHeight
        })
        this._resizeObserver.observe(chatBody)
        for (const child of chatBody.children) {
          this._resizeObserver.observe(child)
        }
      }

      chatBody.addEventListener("scroll", () => {
        // Ignore scroll events that fire during a LiveView morphdom patch or message
        // send. morphdom can drop scrollTop, which looks like "user scrolled up".
        if (this._sendingMessage || this._patching) return
        const atBottom = chatBody.scrollTop + chatBody.clientHeight >= chatBody.scrollHeight - 10
        const scrolledUp = chatBody.scrollTop + chatBody.clientHeight < chatBody.scrollHeight - 20
        if (atBottom && !this._autoScroll) {
          setAutoScroll(true)
        } else if (scrolledUp && this._autoScroll) {
          setAutoScroll(false)
        }
      })
    }

    // Also track scroll state on the outer container — if chatBody collapses,
    // this.el becomes the visible scroll target and we need to detect up/down.
    this.el.addEventListener("scroll", () => {
      if (this._sendingMessage || this._patching) return
      const atBottom = this.el.scrollTop + this.el.clientHeight >= this.el.scrollHeight - 10
      const scrolledUp = this.el.scrollTop + this.el.clientHeight < this.el.scrollHeight - 20
      if (atBottom && !this._autoScroll) {
        setAutoScroll(true)
      } else if (scrolledUp && this._autoScroll) {
        setAutoScroll(false)
      }
    })

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
    // where they were scrolled. Use event delegation on this.el (never
    // replaced by LiveView patches) rather than the <form> element directly,
    // which morphdom may swap out after each re-render, detaching the listener.
    //
    // We set _sendingMessage = true here so the scroll listeners ignore the
    // scroll event that fires when LiveView's morphdom re-renders the message
    // list and temporarily drops scrollTop. Without this, the drop is mis-read
    // as "user scrolled up" and _autoScroll gets set to false.
    this.el.addEventListener("submit", (e) => {
      if (e.target.closest("[data-chat-footer]")) {
        this._sendingMessage = true
        setAutoScroll(true)
        requestAnimationFrame(() => scrollToBottom())
      }
    })

    this.handleEvent("messages-updated-" + this.el.dataset.csId, () => {
      if (this._minimized) {
        // Window is hidden — nothing to do; user restores via canvas flyout
      } else if (this._autoScroll) {
        // Defer by one rAF so the browser finishes reflowing the new message
        // before we read scrollHeight. Without this, the layout flush from the
        // height-restoration in updated() can cause scrollToBottom() to land
        // short of the actual bottom.
        requestAnimationFrame(() => scrollToBottom())
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
      if (w !== this.el) saveWindowZ(w.dataset.csId, 1)
    })
    const zVal = this._maximized ? "20" : String(Math.max(10, maxZ))
    this.el.style.zIndex = zVal
    this._zIndex = zVal
    this.el.dataset.savedZIndex = zVal
    this.el.classList.add("ring-2", "ring-primary/40")
    saveWindowZ(this.el.dataset.csId, parseInt(zVal, 10))
  },

  _applyMinimized() {
    this._minimized = true
    this.el.style.display = "none"
    saveWindowMinimized(this.el.dataset.csId, true)
    if (this._resizeObserver) this._resizeObserver.disconnect()
  },

  _restoreFromMinimized() {
    this._minimized = false
    saveWindowMinimized(this.el.dataset.csId, false)
    this.el.style.display = ""
    // Re-attach resize observer and force-scroll to bottom on restore
    if (this._resizeObserver) {
      const body = this.el.querySelector("[data-chat-body]")
      if (body) {
        this._resizeObserver.observe(body)
        for (const child of body.children) this._resizeObserver.observe(child)
        this._lastScrollHeight = body.scrollHeight
        body.scrollTop = body.scrollHeight
      }
    }
    this._raiseToFront()
  },

  beforeUpdate() {
    // Block scroll listeners from misreading the morphdom patch as a user scroll.
    this._patching = true
  },

  updated() {
    // Release the patch guard after the browser settles the layout.
    requestAnimationFrame(() => { this._patching = false })

    // LiveView patches the style attr but doesn't render z-index — restore it.
    // Prefer dataset.savedZIndex (cross-hook authoritative) over instance memory.
    const saved = this.el.dataset.savedZIndex
    if (saved) {
      this.el.style.zIndex = saved
      this._zIndex = saved
    } else if (this._zIndex) {
      this.el.style.zIndex = this._zIndex
    }

    // Restore position from last-known JS state. LiveView patches the style attr
    // with DB-saved pos_x/pos_y on every render — this undoes that. We track
    // _dragLeft/_dragTop from drag, layout buttons, and localStorage restore,
    // so they're always authoritative once set.
    if (this._dragLeft != null) {
      this.el.style.left = `${this._dragLeft}px`
      this.el.style.top  = `${this._dragTop}px`
    }

    // LiveView re-writes the style attr with DB-saved width/height on every patch
    // (e.g. when a message is sent). If the user has resized the window since the
    // last DB persist, this would snap it back. Restore JS-tracked dimensions
    // instead. Skip when maximized — that mode manages its own dimensions.
    if (!this._maximized && this._width != null && this._height != null) {
      this.el.style.width  = `${this._width}px`
      this.el.style.height = `${this._height}px`
    }

    if (this._minimized) this._applyMinimized()

    // If a message send is in flight, clear the suppression flag and force
    // _autoScroll back on. The morphdom patch may have dropped scrollTop (firing
    // a spurious scroll event that set _autoScroll = false), so we reset here.
    //
    // Also scroll to bottom after ANY patch when auto-scroll is on — this handles
    // streaming agent responses where each chunk re-renders the component but
    // messages-updated is not fired (same last-message ID).
    if (this._sendingMessage) {
      this._sendingMessage = false
      this._autoScroll = true
    }
    if (this._autoScroll && !this._minimized) {
      requestAnimationFrame(() => {
        const body = this.el.querySelector("[data-chat-body]")
        if (body) body.scrollTop = body.scrollHeight
        this.el.scrollTop = this.el.scrollHeight
      })
    }

    // Re-observe children after patch — LiveView may have replaced message nodes.
    if (this._resizeObserver) {
      const body = this.el.querySelector("[data-chat-body]")
      if (body) {
        this._resizeObserver.disconnect()
        this._resizeObserver.observe(body)
        for (const child of body.children) {
          this._resizeObserver.observe(child)
        }
        this._lastScrollHeight = body.scrollHeight
      }
    }
  },

  destroyed() {
    this._destroyed = true
    clearTimeout(this._resizePersistTimer)
    if (this._resizeObserver) this._resizeObserver.disconnect()
    document.removeEventListener("mousedown", this._onBlurWindows)
    window.removeEventListener("canvas:focus-session", this._onFocusSession)
    this._userScrolled = true  // stop any pending force-scroll timeouts
  }
}
