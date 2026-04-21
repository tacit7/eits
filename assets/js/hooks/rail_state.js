import { TOUCH_DEVICE, createSwipeDetector } from './touch_gesture'

const STORAGE_KEY_SECTION = 'rail_section'
const STORAGE_KEY_PROJECT = 'rail_project_id'

export const RailState = {
  mounted() {
    // Restore last section from localStorage (no-op if rail_section is never written)
    const savedSection = localStorage.getItem(STORAGE_KEY_SECTION)
    if (savedSection) {
      this.pushEventTo(this.el, 'restore_section', { section: savedSection })
    }

    // Restore last selected project across LiveView navigations.
    // The rail LiveComponent remounts on cross-LV navigation, losing sidebar_project.
    // We persist the project_id here and push it back on every mount so the server
    // can restore it if no project is provided by the parent LiveView.
    const savedProjectId = localStorage.getItem(STORAGE_KEY_PROJECT)
    if (savedProjectId) {
      this.pushEventTo(this.el, 'restore_project', { project_id: savedProjectId })
    }

    // Listen for save_project events pushed from the server when a project is selected.
    // project_id is a string (or null to clear).
    this.handleEvent('save_project', ({ project_id }) => {
      if (project_id) {
        localStorage.setItem(STORAGE_KEY_PROJECT, String(project_id))
      } else {
        localStorage.removeItem(STORAGE_KEY_PROJECT)
      }
    })

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
        this._grabHandle.addEventListener('touchstart', this._edgeGesture.onTouchStart, { passive: true })
        this._grabHandle.addEventListener('touchmove', this._edgeGesture.onTouchMove, { passive: true })
        this._grabHandle.addEventListener('touchend', this._edgeGesture.onTouchEnd, { passive: true })
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
