// DrawerDirtyForm — tracks whether the task edit form has unsaved changes.
// Sets data-dirty="" on the form when any field differs from its original value.
// Disables the Save button when clean; enables + shows dirty indicator when dirty.
// Resets automatically when LiveView patches the form (new task selected or after save).
export const DrawerDirtyForm = {
  mounted() {
    this._snapshot = this._captureValues()
    this._submitBtn = document.querySelector(`[form="${this.el.id}"][type="submit"]`)
    this._indicator = document.getElementById("task-dirty-indicator")
    this._sync()

    this.el.addEventListener("input", () => this._sync())
    this.el.addEventListener("change", () => this._sync())
  },

  // Fires after LiveView patches the form — new task selected or save completed.
  // Reset snapshot so the clean state reflects the new field values.
  updated() {
    this._snapshot = this._captureValues()
    this._submitBtn = document.querySelector(`[form="${this.el.id}"][type="submit"]`)
    this._indicator = document.getElementById("task-dirty-indicator")
    this._sync()
  },

  _captureValues() {
    const vals = {}
    this.el.querySelectorAll("input, select, textarea").forEach((el) => {
      if (el.name) vals[el.name] = el.value
    })
    return vals
  },

  _isDirty() {
    const current = this._captureValues()
    return Object.keys(current).some((k) => current[k] !== (this._snapshot[k] ?? ""))
  },

  _sync() {
    const dirty = this._isDirty()

    if (dirty) {
      this.el.setAttribute("data-dirty", "")
    } else {
      this.el.removeAttribute("data-dirty")
    }

    if (this._submitBtn) {
      this._submitBtn.disabled = !dirty
      // Visual weight: full opacity when dirty, dimmed when clean
      this._submitBtn.classList.toggle("opacity-40", !dirty)
      this._submitBtn.classList.toggle("pointer-events-none", !dirty)
    }

    if (this._indicator) {
      this._indicator.classList.toggle("hidden", !dirty)
    }
  },
}
