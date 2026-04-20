import { TOUCH_DEVICE, createSwipeDetector } from './touch_gesture'

export const RailState = {
  mounted() {
    // Future-compatible restore. MVP does not write rail_section — this is a no-op until
    // write-back is added. Do not add localStorage.setItem calls here.
    const savedSection = localStorage.getItem('rail_section')
    if (savedSection) {
      this.pushEventTo(this.el, 'restore_section', { section: savedSection })
    }

    // Listen for mobile open event dispatched from app header
    this._openHandler = () => this.pushEventTo(this.el, 'open_mobile', {})
    this.el.addEventListener('rail:open', this._openHandler)

    if (TOUCH_DEVICE) {
      // Swipe left on open flyout → close
      this._flyoutGesture = createSwipeDetector({
        onSwipeLeft: () => this.pushEventTo(this.el, 'close_flyout', {}),
      })
      const flyoutPanel = this.el.querySelector('[data-flyout-panel]')
      if (flyoutPanel) {
        flyoutPanel.addEventListener('touchstart', this._flyoutGesture.onTouchStart, { passive: true })
        flyoutPanel.addEventListener('touchmove', this._flyoutGesture.onTouchMove, { passive: true })
        flyoutPanel.addEventListener('touchend', this._flyoutGesture.onTouchEnd, { passive: true })
      }

      // Swipe right on left edge → open flyout
      this._edgeGesture = createSwipeDetector({
        onSwipeRight: () => this.pushEventTo(this.el, 'open_mobile', {}),
      })
      this._grabHandle = document.getElementById('rail-grab-handle')
      if (this._grabHandle) {
        this._grabHandle.addEventListener('touchstart', this._edgeGesture.onTouchStart)
        this._grabHandle.addEventListener('touchmove', this._edgeGesture.onTouchMove)
        this._grabHandle.addEventListener('touchend', this._edgeGesture.onTouchEnd)
      }
    }
  },

  destroyed() {
    if (this._openHandler) {
      this.el.removeEventListener('rail:open', this._openHandler)
    }
    if (this._flyoutGesture) {
      const flyoutPanel = this.el.querySelector('[data-flyout-panel]')
      if (flyoutPanel) {
        flyoutPanel.removeEventListener('touchstart', this._flyoutGesture.onTouchStart)
        flyoutPanel.removeEventListener('touchmove', this._flyoutGesture.onTouchMove)
        flyoutPanel.removeEventListener('touchend', this._flyoutGesture.onTouchEnd)
      }
    }
    if (this._grabHandle && this._edgeGesture) {
      this._grabHandle.removeEventListener('touchstart', this._edgeGesture.onTouchStart)
      this._grabHandle.removeEventListener('touchmove', this._edgeGesture.onTouchMove)
      this._grabHandle.removeEventListener('touchend', this._edgeGesture.onTouchEnd)
    }
  }
}
