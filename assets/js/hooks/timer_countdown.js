/**
 * TimerCountdown hook
 *
 * Reads `data-fire-at` (ISO8601 UTC) and updates the element's text with a
 * live countdown (MM:SS or H:MM:SS) every second.
 */
export const TimerCountdown = {
  mounted() {
    this._start()
  },

  updated() {
    this._stop()
    this._start()
  },

  destroyed() {
    this._stop()
  },

  _start() {
    this._tick()
    this._interval = setInterval(() => this._tick(), 1000)
  },

  _stop() {
    if (this._interval) {
      clearInterval(this._interval)
      this._interval = null
    }
  },

  _tick() {
    const fireAt = this.el.dataset.fireAt
    if (!fireAt) return

    const remaining = Math.max(0, Math.floor((new Date(fireAt).getTime() - Date.now()) / 1000))

    const h = Math.floor(remaining / 3600)
    const m = Math.floor((remaining % 3600) / 60)
    const s = remaining % 60

    this.el.textContent = h > 0
      ? `${h}:${String(m).padStart(2, '0')}:${String(s).padStart(2, '0')}`
      : `${m}:${String(s).padStart(2, '0')}`
  }
}
