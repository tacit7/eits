export const RefreshDot = {
  mounted() { this._flash() },
  updated() { this._flash() },
  destroyed() { clearTimeout(this._timer) },
  _flash() {
    this.el.style.opacity = "1"
    clearTimeout(this._timer)
    this._timer = setTimeout(() => { this.el.style.opacity = "0" }, 600)
  }
}
