// TaskListSelection — persists the selected row highlight (data-drawer-open) across
// LiveView stream patches. When a stream_insert re-renders a row it loses its
// client-side data-drawer-open attribute. This hook restores it by watching
// data-selected-task-id on the list container.
export const TaskListSelection = {
  mounted() {
    this._syncSelection()
    // Watch for LiveView patching data-selected-task-id (server-driven selection change)
    this._observer = new MutationObserver(() => this._syncSelection())
    this._observer.observe(this.el, {
      attributes: true,
      attributeFilter: ["data-selected-task-id"],
    })
  },

  // Fires after LiveView patches the DOM — restores data-drawer-open after stream inserts
  updated() {
    this._syncSelection()
  },

  destroyed() {
    if (this._observer) this._observer.disconnect()
  },

  _syncSelection() {
    const selectedId = this.el.dataset.selectedTaskId

    // Clear stale selections (there should only ever be one, but be defensive)
    this.el.querySelectorAll("[data-drawer-open]").forEach((el) => {
      el.removeAttribute("data-drawer-open")
    })

    if (selectedId) {
      const row = document.getElementById(`task-row-${selectedId}`)
      if (row) row.setAttribute("data-drawer-open", "")
    }
  },
}
