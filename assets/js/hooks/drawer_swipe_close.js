import {TOUCH_DEVICE, createSwipeDetector} from './touch_gesture'

// Swipe-left-to-close for right-side drawer panels.
// Attach phx-hook="DrawerSwipeClose" and data-close-event="<event_name>" to the panel element.
export const DrawerSwipeClose = {
  mounted() {
    if (!TOUCH_DEVICE) return
    const closeEvent = this.el.dataset.closeEvent
    if (!closeEvent) return
    const closeKey = this.el.dataset.closeKey
    const closePayload = closeKey ? {key: closeKey} : {}
    this._gesture = createSwipeDetector({
      onSwipeLeft: () => this.pushEvent(closeEvent, closePayload),
    })
    this.el.addEventListener("touchstart", this._gesture.onTouchStart, { passive: true })
    this.el.addEventListener("touchmove", this._gesture.onTouchMove, { passive: true })
    this.el.addEventListener("touchend", this._gesture.onTouchEnd, { passive: true })
  },
  destroyed() {
    if (!this._gesture) return
    this.el.removeEventListener("touchstart", this._gesture.onTouchStart)
    this.el.removeEventListener("touchmove", this._gesture.onTouchMove)
    this.el.removeEventListener("touchend", this._gesture.onTouchEnd)
  },
}
