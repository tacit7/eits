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

    // --- Mobile: icon taps open the drawer, never navigate -------------------
    // The strip is tappable on mobile even with the drawer closed, and the
    // server can't tell viewports apart. Intercept in capture phase and send
    // a dedicated event that opens drawer + section flyout (pre-navigate-era
    // behavior). If this hook ever fails to mount, taps degrade to the desktop
    // path (full-page navigation) — functional, just less slick.
    {
      const strip = this.el.querySelector('#rail-icon-strip')
      if (strip) {
        this._mobileTapGuard = (e) => {
          if (!window.matchMedia('(max-width: 767px)').matches) return
          const btn = e.target.closest('button[phx-value-section]')
          if (!btn) return
          e.preventDefault()
          e.stopPropagation()
          this.pushEventTo(this.el, 'open_mobile_section', {
            section: btn.getAttribute('phx-value-section'),
          })
        }
        strip.addEventListener('click', this._mobileTapGuard, true)
      }
    }

    // --- Drag-right on the icon strip opens the flyout -----------------------
    // Click = navigate (server-side toggle_section); a horizontal pull ≥24px
    // (and more horizontal than vertical) = open the flyout panel instead.
    // The click that follows a drag's mouseup is swallowed in capture phase so
    // a drag never also navigates.
    {
      const strip = this.el.querySelector('#rail-icon-strip')
      if (strip) {
        let start = null
        let dragged = false
        this._dragDown = (e) => {
          if (e.button !== 0) return
          start = { x: e.clientX, y: e.clientY }
          dragged = false
        }
        this._dragMove = (e) => {
          if (!start || dragged) return
          const dx = e.clientX - start.x
          const dy = Math.abs(e.clientY - start.y)
          if (dx >= 24 && dx > dy) {
            dragged = true
            this.pushEventTo(this.el, 'open_flyout', {})
          }
        }
        this._dragUp = () => {
          if (dragged) {
            this._suppressNextClick = true
            // Mainstream engines dispatch the post-mouseup click before timers,
            // but that ordering is not spec-guaranteed (WKWebView is our
            // runtime). 300ms comfortably outlives any click dispatch while
            // still clearing a flag no click consumed (release outside the
            // strip), so it can't eat the NEXT legitimate click.
            setTimeout(() => { this._suppressNextClick = false }, 300)
          }
          start = null
        }
        this._dragClickGuard = (e) => {
          if (this._suppressNextClick) {
            e.stopPropagation()
            e.preventDefault()
            this._suppressNextClick = false
          }
        }
        strip.addEventListener('mousedown', this._dragDown)
        window.addEventListener('mousemove', this._dragMove)
        window.addEventListener('mouseup', this._dragUp)
        strip.addEventListener('click', this._dragClickGuard, true)
      }
    }

    // --- Tauri bridges -------------------------------------------------------
    // These MUST live in a hook: hooks are the only public API that can push
    // events to a LiveComponent (view.pushEventTo does not exist on the View
    // class — using it silently drops the event; that bug shipped in ≤0.3.9
    // and made native-dialog project creation a no-op).

    // phx:pick_folder — server asks for a folder. In Tauri, open the native
    // picker and push the result back; empty payload = cancelled/no Tauri,
    // which the server renders as the inline text-input fallback.
    this._pickFolderHandler = () => {
      if (window.__TAURI_INTERNALS__) {
        window.__TAURI_INTERNALS__
          .invoke('pick_folder', {})
          .then((path) => {
            this.pushEventTo(this.el, 'folder_picked', path ? { path } : {})
          })
          .catch((err) => {
            console.error('[tauri] pick_folder failed:', err)
            this.pushEventTo(this.el, 'folder_picked', {})
          })
      } else {
        this.pushEventTo(this.el, 'folder_picked', {})
      }
    }
    window.addEventListener('phx:pick_folder', this._pickFolderHandler)

    // tauri:session-action — fired by Rust after a native context-menu
    // selection that needs a LiveView round-trip (archive, rename, etc).
    // Payload: { action: 'archive_session', session_id: 123, extra: {} }
    this._sessionActionHandler = (e) => {
      const { action, session_id, extra } = e.detail ?? {}
      if (!action) return
      this.pushEventTo(this.el, action, { session_id: String(session_id), ...(extra ?? {}) })
    }
    window.addEventListener('tauri:session-action', this._sessionActionHandler)

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
    if (this._dragMove) {
      window.removeEventListener('mousemove', this._dragMove)
      window.removeEventListener('mouseup', this._dragUp)
      // strip listeners die with this.el; window listeners are the leak risk
    }
    if (this._pickFolderHandler) {
      window.removeEventListener('phx:pick_folder', this._pickFolderHandler)
    }
    if (this._sessionActionHandler) {
      window.removeEventListener('tauri:session-action', this._sessionActionHandler)
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
