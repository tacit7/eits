// assets/js/hooks/diff_collapse.js
// Intercepts the DaisyUI collapse checkbox for commit diffs.
//
// First click (diff not yet cached):
//   - Prevents the collapse from opening immediately
//   - Shows a spinner in the commit header
//   - Pushes load_diff to LiveView
//   - updated() auto-opens the collapse once data-loaded becomes "true"
//
// Subsequent clicks: normal checkbox toggle (diff already in cache).

export const DiffCollapse = {
  mounted() {
    this._loaded = this.el.dataset.loaded === "true"
    this._pending = false

    const checkbox = this.el.querySelector('input[type="checkbox"]')
    if (!checkbox) return

    checkbox.addEventListener("change", (e) => {
      if (e.target.checked && !this._loaded) {
        // Collapse would open but diff isn't ready — block it
        e.target.checked = false
        this._pending = true
        this._setSpinner(true)
        this.pushEvent("load_diff", { hash: this.el.dataset.hash })
      }
    })
  },

  updated() {
    const isLoaded = this.el.dataset.loaded === "true"

    if (this._pending && isLoaded) {
      this._pending = false
      this._setSpinner(false)
      const checkbox = this.el.querySelector('input[type="checkbox"]')
      if (checkbox) checkbox.checked = true
    }

    // Error case: clear pending spinner without opening
    if (this._pending && this.el.dataset.loaded === "error") {
      this._pending = false
      this._setSpinner(false)
    }

    this._loaded = isLoaded
  },

  _setSpinner(visible) {
    const spinner = this.el.querySelector('[data-role="diff-spinner"]')
    if (spinner) spinner.classList.toggle("hidden", !visible)
  },
}
