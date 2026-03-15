import { TOUCH_DEVICE } from "./touch_gesture"

const MAX_REVEAL = 160  // px — Option B from design spec
const SNAP_THRESHOLD = MAX_REVEAL * 0.35  // 56px

// Track open row across all instances so only one is open at a time
let _openHook = null

function isFormEl(el) {
  return !!el.closest("input, textarea, select, [contenteditable]")
}

export const SwipeRow = {
  mounted() {
    if (!TOUCH_DEVICE) return
    this._setup()
  },

  updated() {
    // LiveView stream patches may re-render the element; re-attach listeners
    if (!TOUCH_DEVICE) return
    this._teardown()
    this._setup()
  },

  destroyed() {
    this._teardown()
    if (_openHook === this) _openHook = null
  },

  _setup() {
    this._rowEl = this.el.querySelector("[data-swipe-row]")
    if (!this._rowEl) return

    this.isOpen = false
    this._startX = 0
    this._startY = 0
    this._startTime = 0
    this._dragging = false

    this._onTouchStart = this._touchStart.bind(this)
    this._onTouchMove  = this._touchMove.bind(this)
    this._onTouchEnd   = this._touchEnd.bind(this)
    this._onSwipeOpen  = this._handleOtherOpen.bind(this)

    this.el.addEventListener("touchstart", this._onTouchStart, { passive: true })
    this.el.addEventListener("touchmove",  this._onTouchMove,  { passive: false })
    this.el.addEventListener("touchend",   this._onTouchEnd,   { passive: true })
    document.addEventListener("swiperow:open", this._onSwipeOpen)
    document.addEventListener("touchstart", this._onDocTouch = (e) => {
      if (this.isOpen && !this.el.contains(e.target)) this._snapClose()
    }, { passive: true })
  },

  _teardown() {
    if (!this._rowEl) return
    this.el.removeEventListener("touchstart", this._onTouchStart)
    this.el.removeEventListener("touchmove",  this._onTouchMove)
    this.el.removeEventListener("touchend",   this._onTouchEnd)
    document.removeEventListener("swiperow:open", this._onSwipeOpen)
    document.removeEventListener("touchstart", this._onDocTouch)
  },

  _touchStart(e) {
    if (isFormEl(e.target)) return
    if (e.touches.length !== 1) return
    this._startX = e.touches[0].clientX
    this._startY = e.touches[0].clientY
    this._startTime = Date.now()
    this._dragging = false
    this._rowEl.style.transition = "none"
  },

  _touchMove(e) {
    const dx = e.touches[0].clientX - this._startX
    const dy = e.touches[0].clientY - this._startY

    if (!this._dragging) {
      if (Math.abs(dx) > 8 && Math.abs(dx) > Math.abs(dy)) {
        this._dragging = true
        // Close any other open row
        if (_openHook && _openHook !== this) _openHook._snapClose()
      } else if (Math.abs(dy) > 10) {
        return  // vertical scroll, ignore
      }
    }

    if (this._dragging) {
      e.preventDefault()
      const base = this.isOpen ? -MAX_REVEAL : 0
      const clamped = Math.min(0, Math.max(-MAX_REVEAL, base + dx))
      this._rowEl.style.transform = `translateX(${clamped}px)`
    }
  },

  _touchEnd(e) {
    const dx = e.changedTouches[0].clientX - this._startX
    const dy = e.changedTouches[0].clientY - this._startY
    const dt = Date.now() - this._startTime

    this._rowEl.style.transition = "transform 0.25s cubic-bezier(0.25,0.46,0.45,0.94)"

    if (this._dragging) {
      if (!this.isOpen && dx < -SNAP_THRESHOLD) {
        this._snapOpen()
      } else if (this.isOpen && dx > SNAP_THRESHOLD) {
        this._snapClose()
      } else if (this.isOpen) {
        this._snapOpen()   // snap back to open
      } else {
        this._rowEl.style.transform = ""  // snap back to closed
      }
    } else if (Math.abs(dx) < 10 && Math.abs(dy) < 10 && dt < 300) {
      // Tap
      if (this.isOpen) {
        this._snapClose()
      }
      // If closed, do nothing — let phx-click on the row fire normally
    }
  },

  _snapOpen() {
    this._rowEl.style.transition = "transform 0.25s cubic-bezier(0.25,0.46,0.45,0.94)"
    this._rowEl.style.transform = `translateX(-${MAX_REVEAL}px)`
    this.isOpen = true
    _openHook = this
    document.dispatchEvent(new CustomEvent("swiperow:open", { detail: { hook: this } }))
  },

  _snapClose() {
    this._rowEl.style.transition = "transform 0.25s cubic-bezier(0.25,0.46,0.45,0.94)"
    this._rowEl.style.transform = ""
    this.isOpen = false
    if (_openHook === this) _openHook = null
  },

  _handleOtherOpen(e) {
    if (e.detail.hook !== this && this.isOpen) this._snapClose()
  },
}
