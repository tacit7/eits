export const KanbanKeyboard = {
  mounted() {
    this._handler = (e) => {
      // Skip if user is typing in an input/textarea/select
      const tag = e.target.tagName
      if (tag === "INPUT" || tag === "TEXTAREA" || tag === "SELECT" || e.target.isContentEditable) return

      if (e.key === "n" && !e.ctrlKey && !e.metaKey) {
        e.preventDefault()
        this.pushEvent("toggle_new_task_drawer", {})
      } else if (e.key === "/" && !e.ctrlKey && !e.metaKey) {
        e.preventDefault()
        const searchInput = this.el.querySelector("input[name='query']")
        if (searchInput) searchInput.focus()
      } else if (e.key === "Escape") {
        // Close drawers/quick-add if open
        const detailDrawer = document.getElementById("task-detail-panel")
        const newTaskDrawer = document.getElementById("new-task-drawer")
        if (detailDrawer) {
          this.pushEvent("toggle_task_detail_drawer", {})
        } else if (newTaskDrawer && newTaskDrawer.querySelector("[data-show='true']")) {
          this.pushEvent("toggle_new_task_drawer", {})
        } else {
          this.pushEvent("hide_quick_add", {})
        }
      }
    }
    document.addEventListener("keydown", this._handler)
  },
  destroyed() {
    if (this._handler) document.removeEventListener("keydown", this._handler)
  }
}

export const KanbanScrollDots = {
  mounted() {
    const dots = this.el.querySelector("#kanban-dots")
    if (!dots) return
    const allDots = dots.querySelectorAll("[data-dot-index]")
    const count = parseInt(this.el.dataset.columnCount) || 0
    if (count === 0) return

    const update = () => {
      const scrollLeft = this.el.scrollLeft
      const scrollWidth = this.el.scrollWidth - this.el.clientWidth
      const ratio = scrollWidth > 0 ? scrollLeft / scrollWidth : 0
      const activeIdx = Math.round(ratio * (count - 1))
      allDots.forEach(dot => {
        const idx = parseInt(dot.dataset.dotIndex)
        dot.style.opacity = idx === activeIdx ? "1" : "0.3"
        dot.style.transform = idx === activeIdx ? "scale(1.3)" : "scale(1)"
      })
    }

    update()
    this.el.addEventListener("scroll", update, { passive: true })
    this._scrollHandler = update
  },
  destroyed() {
    if (this._scrollHandler) {
      this.el.removeEventListener("scroll", this._scrollHandler)
    }
  }
}
