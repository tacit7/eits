export const FlashTimeout = {
  mounted() {
    this._timer = setTimeout(() => {
      this.el.click()
    }, 5000)
  },
  destroyed() {
    clearTimeout(this._timer)
  }
}
