export const LocalTime = {
  mounted() { this._format() },
  updated() { this._format() },
  _format() {
    const utc = this.el.dataset.utc
    if (!utc) return
    const d = new Date(utc)
    if (isNaN(d)) return
    if (this.el.dataset.fmt === 'short') {
      this.el.textContent = d.toLocaleString(undefined, {
        year: 'numeric', month: '2-digit', day: '2-digit',
        hour: '2-digit', minute: '2-digit'
      })
      return
    }
    const now = new Date()
    const yesterday = new Date(now)
    yesterday.setDate(yesterday.getDate() - 1)
    const timeStr = d.toLocaleTimeString(undefined, { hour: '2-digit', minute: '2-digit' })
    if (d.toDateString() === now.toDateString()) {
      this.el.textContent = `Today at ${timeStr}`
    } else if (d.toDateString() === yesterday.toDateString()) {
      this.el.textContent = `Yesterday at ${timeStr}`
    } else {
      this.el.textContent = d.toLocaleString(undefined, {
        month: '2-digit', day: '2-digit', year: 'numeric',
        hour: '2-digit', minute: '2-digit'
      })
    }
  }
}
