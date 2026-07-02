const SKIP_KEY = "dm_reload_skip_confirm"

export const ReloadConfirmModal = {
  mounted() {
    // Trigger: buttons dispatch this event instead of using data-confirm
    this._boundReloadCheck = () => {
      if (localStorage.getItem(SKIP_KEY) === "1") {
        this.pushEvent("reload_from_session_file", {})
      } else {
        this.el.showModal()
      }
    }
    this.el.addEventListener("dm:reload-check", this._boundReloadCheck)

    this._boundConfirm = () => {
      if (this.el.querySelector("[data-reload-skip]").checked) {
        localStorage.setItem(SKIP_KEY, "1")
      }
      this.el.close()
      this.pushEvent("reload_from_session_file", {})
    }
    this.el.querySelector("[data-reload-confirm]").addEventListener("click", this._boundConfirm)

    this._boundCancel = () => {
      this.el.close()
    }
    this.el.querySelector("[data-reload-cancel]").addEventListener("click", this._boundCancel)
  },

  destroyed() {
    if (this._boundReloadCheck) this.el.removeEventListener("dm:reload-check", this._boundReloadCheck)
    const confirmBtn = this.el.querySelector("[data-reload-confirm]")
    if (confirmBtn && this._boundConfirm) confirmBtn.removeEventListener("click", this._boundConfirm)
    const cancelBtn = this.el.querySelector("[data-reload-cancel]")
    if (cancelBtn && this._boundCancel) cancelBtn.removeEventListener("click", this._boundCancel)
  }
}
