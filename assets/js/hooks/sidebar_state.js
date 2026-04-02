import {debounce} from './utils'
import {TOUCH_DEVICE, createSwipeDetector} from './touch_gesture'

export const SidebarState = {
  mounted() {
    // Restore collapsed state
    const savedCollapsed = localStorage.getItem("sidebar_collapsed")
    if (savedCollapsed === "true" && window.matchMedia("(min-width: 768px)").matches) {
      this.pushEventTo(this.el, "toggle_collapsed", {})
    }

    // Restore section expanded states (overview, projects, system) from localStorage
    this._restoreSectionStates()

    // Handle section toggle buttons (delegated click on sidebar)
    this.el.addEventListener("click", (e) => {
      const sectionBtn = e.target.closest("[data-section-toggle]")
      if (sectionBtn) {
        const section = sectionBtn.dataset.sectionToggle
        this._persistSectionToggle(section)
      }
    })

    this._projectFilterInput = this.el.querySelector("[data-project-filter]")
    this._debouncedProjectFilter = debounce((value) => this._applyProjectFilter(value), 120)
    this._projectFilterHandler = (e) => {
      this._debouncedProjectFilter(e.target.value || "")
    }
    this._projectFilterKeydown = (e) => {
      if (e.key === "Enter") {
        e.preventDefault()
        this._navigateToFirstVisibleProject()
      } else if (e.key === "Escape") {
        e.preventDefault()
        e.target.value = ""
        this._applyProjectFilter("")
      } else if (e.key === "ArrowDown") {
        const firstVisible = this._firstVisibleProjectLink()
        if (firstVisible) {
          e.preventDefault()
          firstVisible.focus()
        }
      }
    }
    if (this._projectFilterInput) {
      this._projectFilterInput.addEventListener("input", this._projectFilterHandler)
      this._projectFilterInput.addEventListener("keydown", this._projectFilterKeydown)
    }

    // Listen for mobile open event dispatched from the top bar outside this component
    this._openHandler = () => this.pushEventTo(this.el, "open_mobile", {})
    this.el.addEventListener("sidebar:open", this._openHandler)

    // Touch gestures — mobile only
    if (TOUCH_DEVICE) {
      // Swipe left on the open sidebar → close
      this._sidebarGesture = createSwipeDetector({
        onSwipeLeft: () => this.pushEventTo(this.el, "close_mobile", {}),
      })
      this.el.addEventListener("touchstart", this._sidebarGesture.onTouchStart, { passive: true })
      this.el.addEventListener("touchmove", this._sidebarGesture.onTouchMove, { passive: true })
      this.el.addEventListener("touchend", this._sidebarGesture.onTouchEnd, { passive: true })

      // Edge swipe right via dedicated grab handle → open sidebar.
      this._edgeGesture = createSwipeDetector({
        onSwipeRight: () => this.pushEventTo(this.el, "open_mobile", {}),
      })
      this._grabHandle = document.getElementById("sidebar-grab-handle")
      if (this._grabHandle) {
        this._grabHandle.addEventListener("touchstart", this._edgeGesture.onTouchStart)
        this._grabHandle.addEventListener("touchmove", this._edgeGesture.onTouchMove)
        this._grabHandle.addEventListener("touchend", this._edgeGesture.onTouchEnd)
      }
    }
  },

  updated() {
    const filterValue = this._projectFilterInput?.value || ""
    this._applyProjectFilter(filterValue)
  },

  _applyProjectFilter(rawValue) {
    const query = rawValue.trim().toLowerCase()
    this.el.querySelectorAll("[data-project-id]").forEach((el) => {
      const name = (el.dataset.projectName || "").toLowerCase()
      const visible = query === "" || name.includes(query)
      el.style.display = visible ? "" : "none"
    })
  },

  _firstVisibleProjectLink() {
    const candidates = this.el.querySelectorAll("[data-project-id]")
    for (const row of candidates) {
      if (row.style.display === "none") continue
      const link = row.querySelector("[data-project-link]")
      if (link) return link
    }
    return null
  },

  _navigateToFirstVisibleProject() {
    const link = this._firstVisibleProjectLink()
    if (link) window.location.assign(link.getAttribute("href"))
  },

  // Section state persistence (overview, projects, system)
  _restoreSectionStates() {
    const sectionMap = {
      overview: "toggle_all_projects",
      projects: "toggle_projects",
    }
    for (const [section, event] of Object.entries(sectionMap)) {
      const saved = localStorage.getItem(`sidebar_section_${section}`)
      if (saved === "false") {
        this.pushEventTo(this.el, event, {})
      }
    }
  },

  _persistSectionToggle(section) {
    const key = `sidebar_section_${section}`
    const current = localStorage.getItem(key)
    const newVal = current === "false" ? "true" : "false"
    localStorage.setItem(key, newVal)
  },

  destroyed() {
    if (this._debouncedProjectFilter?.cancel) {
      this._debouncedProjectFilter.cancel()
    }
    if (this._projectFilterInput && this._projectFilterHandler) {
      this._projectFilterInput.removeEventListener("input", this._projectFilterHandler)
    }
    if (this._projectFilterInput && this._projectFilterKeydown) {
      this._projectFilterInput.removeEventListener("keydown", this._projectFilterKeydown)
    }
    if (this._openHandler) {
      this.el.removeEventListener("sidebar:open", this._openHandler)
    }
    if (this._sidebarGesture) {
      this.el.removeEventListener("touchstart", this._sidebarGesture.onTouchStart)
      this.el.removeEventListener("touchmove", this._sidebarGesture.onTouchMove)
      this.el.removeEventListener("touchend", this._sidebarGesture.onTouchEnd)
    }
    if (this._grabHandle && this._edgeGesture) {
      this._grabHandle.removeEventListener("touchstart", this._edgeGesture.onTouchStart)
      this._grabHandle.removeEventListener("touchmove", this._edgeGesture.onTouchMove)
      this._grabHandle.removeEventListener("touchend", this._edgeGesture.onTouchEnd)
    }
  }
}
