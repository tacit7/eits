import { TOUCH_DEVICE, createSwipeDetector } from './touch_gesture'

const STORAGE_KEY = 'rail_state'
const CURRENT_VERSION = 1

// --- Migration from legacy separate keys (one-time, removes old entries) ---
function migrateOldKeys() {
  const section = localStorage.getItem('rail_section')
  const projectId = localStorage.getItem('rail_project_id')
  if (!section && !projectId) return

  const current = readState()
  if (section && !current.section) current.section = section
  if (projectId && !current.project_id) current.project_id = projectId
  writeState(current)
  localStorage.removeItem('rail_section')
  localStorage.removeItem('rail_project_id')
}

function readState() {
  try {
    const raw = localStorage.getItem(STORAGE_KEY)
    const state = raw ? JSON.parse(raw) : {}
    if (!state.version) {
      return { version: CURRENT_VERSION, ...state }
    }
    return state
  } catch {
    return { version: CURRENT_VERSION }
  }
}

function writeState(state) {
  try {
    localStorage.setItem(STORAGE_KEY, JSON.stringify(state))
  } catch {
    // storage quota exceeded — silently skip
  }
}

export const RailState = {
  mounted() {
    migrateOldKeys()

    // Send the full blob to the server once on mount.
    // The server applies each field defensively.
    const state = readState()
    this.pushEventTo(this.el, 'restore_rail_state', state)

    // Server pushes partial patches; hook merges them into the blob.
    this.handleEvent('save_rail_state', (patch) => {
      const current = readState()
      const next = { version: CURRENT_VERSION, ...current, ...patch }
      writeState(next)
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
