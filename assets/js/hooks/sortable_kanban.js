import Sortable from 'sortablejs'

export const SortableKanban = {
  mounted() { this._init() },
  updated() {
    // Sortable handles DOM mutations internally; no need to destroy/recreate
  },
  _init() {
    const isTouchDevice = "ontouchstart" in window || navigator.maxTouchPoints > 0
    this.sortable = Sortable.create(this.el, {
      group: "kanban",
      animation: 150,
      ghostClass: "opacity-30",
      draggable: "[data-task-id]",
      handle: isTouchDevice ? "[data-drag-handle]" : null,
      filter: "button, a, input, select, textarea",
      delay: isTouchDevice ? 150 : 0,
      delayOnTouchOnly: true,
      touchStartThreshold: 5,
      onEnd: (evt) => {
        const taskId = evt.item.dataset.taskId
        const targetCol = evt.to.closest("[data-state-id]")
        const sourceCol = evt.from.closest("[data-state-id]")
        if (!taskId || !targetCol) return

        // Remove "No tasks" placeholder from target column immediately
        const placeholder = evt.to.querySelector("[data-empty-placeholder]")
        if (placeholder) placeholder.remove()

        const targetStateId = targetCol.dataset.stateId
        const movedColumn = targetCol !== sourceCol

        // Always send reorder for the target column
        const targetOrder = [...evt.to.querySelectorAll("[data-task-id]")].map(el => el.dataset.taskId)

        if (movedColumn) {
          // Column change: move_task handles state update, reorder handles position
          this.pushEvent("move_task", { task_id: taskId, state_id: targetStateId })
          if (targetOrder.length > 0) {
            this.pushEvent("reorder_tasks", { task_ids: targetOrder, state_id: targetStateId })
          }
          // Also reorder the source column
          const sourceOrder = [...evt.from.querySelectorAll("[data-task-id]")].map(el => el.dataset.taskId)
          if (sourceOrder.length > 0) {
            this.pushEvent("reorder_tasks", { task_ids: sourceOrder, state_id: sourceCol.dataset.stateId })
          }
        } else {
          // Same column: just reorder
          if (targetOrder.length > 0) {
            this.pushEvent("reorder_tasks", { task_ids: targetOrder, state_id: targetStateId })
          }
        }
      }
    })
  },
  destroyed() {
    if (this.sortable) this.sortable.destroy()
  }
}

export const SortableColumns = {
  mounted() {
    this.sortable = Sortable.create(this.el, {
      animation: 150,
      ghostClass: "opacity-30",
      handle: "[data-column-handle]",
      draggable: "[data-column-id]",
      onEnd: () => {
        const order = [...this.el.querySelectorAll("[data-column-id]")].map(el => el.dataset.columnId)
        this.pushEvent("reorder_columns", { column_ids: order })
      }
    })
  },
  destroyed() {
    if (this.sortable) this.sortable.destroy()
  }
}
