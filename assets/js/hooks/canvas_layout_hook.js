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

const GAP  = 8  // px between tiled windows
const EDGE = 8  // px from canvas edges

// Show a brief dismissing banner inside the canvas area.
function showCanvasBanner(message) {
  const canvas = document.querySelector('[data-canvas-area]')
  if (!canvas) return

  const existing = canvas.querySelector('[data-layout-banner]')
  if (existing) existing.remove()

  const banner = document.createElement('div')
  banner.dataset.layoutBanner = ''
  banner.textContent = message
  banner.style.cssText = [
    'position:absolute',
    'bottom:16px',
    'left:50%',
    'transform:translateX(-50%)',
    'background:oklch(var(--b2))',
    'border:1px solid oklch(var(--bc)/0.15)',
    'color:oklch(var(--bc)/0.7)',
    'font-size:0.75rem',
    'padding:6px 14px',
    'border-radius:9999px',
    'z-index:100',
    'pointer-events:none',
    'white-space:nowrap',
    'box-shadow:0 2px 8px oklch(var(--b3)/0.4)',
  ].join(';')

  canvas.appendChild(banner)
  setTimeout(() => banner.remove(), 3000)
}

// Compute tile positions for n windows in a grid layout.
// cols/rows are inferred from count.
function computePositions(windows, W, H) {
  const n = windows.length

  if (n === 1) {
    return [{ x: EDGE, y: EDGE, w: W, h: H }]
  }

  if (n === 2) {
    const colW = Math.round((W - GAP) / 2)
    return [0, 1].map(i => ({ x: EDGE + i * (colW + GAP), y: EDGE, w: colW, h: H }))
  }

  // 3–4: 2×2 grid
  if (n <= 4) {
    const colW = Math.round((W - GAP) / 2)
    const rowH = Math.round((H - GAP) / 2)
    return windows.map((_, i) => ({
      x: EDGE + (i % 2) * (colW + GAP),
      y: EDGE + Math.floor(i / 2) * (rowH + GAP),
      w: colW,
      h: rowH
    }))
  }

  return null  // caller handles > 4
}

export const CanvasLayoutHook = {
  mounted() {
    this.el.addEventListener('click', () => {
      const canvasArea = document.querySelector('[data-canvas-area]')
      if (!canvasArea) return
      const W = canvasArea.offsetWidth  - EDGE * 2
      const H = canvasArea.offsetHeight - EDGE * 2
      const windows = Array.from(document.querySelectorAll('[data-chat-window]'))
      if (windows.length === 0) return

      if (windows.length > 4) {
        showCanvasBanner('Auto-layout supports up to 4 sessions — drag to arrange the rest')
        // Still tile the first 4; cascade the overflow windows below them
        const positions = computePositions(windows.slice(0, 4), W, H)
        const colW = Math.round((W - GAP) / 2)
        const rowH = Math.round((H - GAP) / 2)
        const overflowPositions = windows.slice(4).map((_, i) => ({
          x: EDGE + 24 + i * 32,
          y: EDGE + 24 + i * 32,
          w: colW,
          h: rowH
        }))
        ;[...positions, ...overflowPositions].forEach((pos, i) => applyPosition(windows[i], pos))
        return
      }

      const positions = computePositions(windows, W, H)
      positions.forEach((pos, i) => applyPosition(windows[i], pos))
    })
  }
}

function applyPosition(win, pos) {
  if (!win || !pos) return
  win.style.left   = pos.x + 'px'
  win.style.top    = pos.y + 'px'
  win.style.width  = pos.w + 'px'
  win.style.height = pos.h + 'px'
  win.dispatchEvent(new CustomEvent('canvas:layout-applied', {
    detail: { x: pos.x, y: pos.y, w: pos.w, h: pos.h },
    bubbles: false
  }))
  saveWindowLayout(win.dataset.csId, pos.x, pos.y, pos.w, pos.h)
}
