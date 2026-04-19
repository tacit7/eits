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
        ? windows.slice(0, 2).map((_, i) => ({ x: i * (W/2), y: 0, w: W/2, h: H }))
        : windows.slice(0, 4).map((_, i) => ({ x: (i%2) * (W/2), y: Math.floor(i/2) * (H/2), w: W/2, h: H/2 }))

      positions.forEach((pos, i) => {
        const win = windows[i]
        if (!win) return
        const csId = win.dataset.csId
        win.style.left = pos.x + 'px'
        win.style.top = pos.y + 'px'
        win.style.width = pos.w + 'px'
        win.style.height = pos.h + 'px'
        this.pushEvent('window_moved', { id: csId, x: pos.x, y: pos.y })
        this.pushEvent('window_resized', { id: csId, w: pos.w, h: pos.h })
      })
    })
  }
}
