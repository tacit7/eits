const SKIP_KEY = "dm_reload_skip_confirm"

export const ReloadConfirmModal = {
  mounted() {
    // Trigger: buttons dispatch this event instead of using data-confirm
    this.el.addEventListener("dm:reload-check", () => {
      if (localStorage.getItem(SKIP_KEY) === "1") {
        this.pushEvent("reload_from_session_file", {})
      } else {
        this.el.showModal()
      }
    })

    this.el.querySelector("[data-reload-confirm]").addEventListener("click", () => {
      if (this.el.querySelector("[data-reload-skip]").checked) {
        localStorage.setItem(SKIP_KEY, "1")
      }
      this.el.close()
      this.pushEvent("reload_from_session_file", {})
    })

    this.el.querySelector("[data-reload-cancel]").addEventListener("click", () => {
      this.el.close()
    })
  }
}
