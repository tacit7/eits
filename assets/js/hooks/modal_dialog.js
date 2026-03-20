export const ModalDialog = {
  mounted() {
    this._sync()
    this._cancelHandler = (e) => {
      e.preventDefault()
      const toggleEvent = this.el.dataset.toggleEvent
      if (toggleEvent) this.pushEvent(toggleEvent, {})
    }
    this.el.addEventListener("cancel", this._cancelHandler)
  },
  destroyed() {
    this.el.removeEventListener("cancel", this._cancelHandler)
  },
  updated() { this._sync() },
  _sync() {
    const open = this.el.dataset.open === "true"
    if (open && !this.el.open) {
      this.el.showModal()
    } else if (!open && this.el.open) {
      this.el.close()
    }
  }
}
