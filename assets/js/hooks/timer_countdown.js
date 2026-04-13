/**
 * TimerCountdown hook
 *
 * Attach to the timer badge button. Reads `data-fire-ms` (epoch milliseconds)
 * and updates the `.timer-countdown-text` child span with MM:SS or H:MM:SS.
 *
 * Using epoch ms avoids ISO 8601 microsecond parsing issues across browsers.
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
    const fireMs = parseInt(this.el.dataset.fireMs, 10)
    if (!fireMs || isNaN(fireMs)) return

    const target = this.el.querySelector('.timer-countdown-text')
    if (!target) return

    const remaining = Math.max(0, Math.floor((fireMs - Date.now()) / 1000))
    const h = Math.floor(remaining / 3600)
    const m = Math.floor((remaining % 3600) / 60)
    const s = remaining % 60

    target.textContent = h > 0
      ? `${h}:${String(m).padStart(2, '0')}:${String(s).padStart(2, '0')}`
      : `${m}:${String(s).padStart(2, '0')}`
  }
}
