const LS_KEY = (csId) => `cw_${csId}`

export function saveWindowLayout(csId, x, y, w, h, z) {
  try {
    const existing = loadWindowLayout(csId) || {}
    const entry = { ...existing, x, y, w: Math.round(w), h: Math.round(h) }
    if (z !== undefined) entry.z = z
    localStorage.setItem(LS_KEY(csId), JSON.stringify(entry))
  } catch (_) {}
}

export function saveWindowZ(csId, z) {
  try {
    const existing = loadWindowLayout(csId) || {}
    localStorage.setItem(LS_KEY(csId), JSON.stringify({ ...existing, z }))
  } catch (_) {}
}

export function loadWindowLayout(csId) {
  try {
    const raw = localStorage.getItem(LS_KEY(csId))
    return raw ? JSON.parse(raw) : null
  } catch (_) { return null }
}

export const CanvasLayoutHook = {
  mounted() {
    this.el.addEventListener('click', () => {
      const preset = this.el.dataset.layoutBtn  // '2up' or '4up'
      const canvasArea = document.querySelector('[data-canvas-area]')
      if (!canvasArea) return
      const W = canvasArea.offsetWidth
      const H = canvasArea.offsetHeight
      const windows = Array.from(document.querySelectorAll('[data-chat-window]'))
      if (windows.length === 0) return

      const positions = preset === '2up'
        ? windows.slice(0, 2).map((_, i) => ({ x: Math.round(i * (W / 2)), y: 0, w: Math.round(W / 2), h: H }))
        : windows.slice(0, 4).map((_, i) => ({ x: Math.round((i % 2) * (W / 2)), y: Math.round(Math.floor(i / 2) * (H / 2)), w: Math.round(W / 2), h: Math.round(H / 2) }))

      positions.forEach((pos, i) => {
        const win = windows[i]
        if (!win) return
        const csId = win.dataset.csId
        win.style.left   = pos.x + 'px'
        win.style.top    = pos.y + 'px'
        win.style.width  = pos.w + 'px'
        win.style.height = pos.h + 'px'
        // Dispatch so ChatWindowHook can sync its instance vars
        win.dispatchEvent(new CustomEvent('canvas:layout-applied', {
          detail: { x: pos.x, y: pos.y, w: pos.w, h: pos.h },
          bubbles: false
        }))
        saveWindowLayout(csId, pos.x, pos.y, pos.w, pos.h)
      })
    })
  }
}
