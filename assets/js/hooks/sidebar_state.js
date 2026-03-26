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

    // Apply project expansion state immediately from localStorage (no server round-trip)
    this._applyExpandedProjects()

    // Handle project toggle buttons and section toggle buttons (delegated click on sidebar)
    this.el.addEventListener("click", (e) => {
      // Section toggles (overview, projects, system)
      const sectionBtn = e.target.closest("[data-section-toggle]")
      if (sectionBtn) {
        const section = sectionBtn.dataset.sectionToggle
        this._persistSectionToggle(section)
        return
      }

      const btn = e.target.closest("[data-project-toggle]")
      if (!btn) return
      const id = btn.dataset.projectToggle
      this._toggleProject(id)
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
      // #sidebar-grab-handle has touch-action:none so Safari's native back
      // gesture won't intercept touches that start on it.
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
    // After LiveView re-renders (e.g. active project changed), reapply expansion state
    // and ensure the active project is expanded
    const activeId = this.el.dataset.activeProjectId
    if (activeId) {
      const expanded = this._getExpanded()
      if (!expanded.has(activeId)) {
        expanded.add(activeId)
        this._saveExpanded(expanded)
      }
    }
    this._applyExpandedProjects()
    const filterValue = this._projectFilterInput?.value || ""
    this._applyProjectFilter(filterValue)
  },

  _getExpanded() {
    try {
      const saved = localStorage.getItem("sidebar_expanded_projects")
      return new Set(saved ? JSON.parse(saved) : [])
    } catch (_) {
      return new Set()
    }
  },

  _saveExpanded(set) {
    localStorage.setItem("sidebar_expanded_projects", JSON.stringify([...set]))
  },

  _toggleProject(id) {
    const expanded = this._getExpanded()
    if (expanded.has(id)) {
      expanded.delete(id)
    } else {
      expanded.add(id)
    }
    this._saveExpanded(expanded)
    this._applyProject(id, expanded.has(id))
  },

  _applyExpandedProjects() {
    const expanded = this._getExpanded()

    // Also auto-expand the active project
    const activeId = this.el.dataset.activeProjectId
    if (activeId) {
      expanded.add(activeId)
      this._saveExpanded(expanded)
    }

    this.el.querySelectorAll("[data-project-id]").forEach(el => {
      const id = el.dataset.projectId
      this._applyProject(id, expanded.has(id))
    })
  },

  _applyProject(id, isExpanded) {
    const sub = document.getElementById(`project-sub-${id}`)
    const chevron = this.el.querySelector(`[data-project-chevron="${id}"]`)
    const toggle = this.el.querySelector(`[data-project-toggle="${id}"]`)
    if (sub) sub.style.display = isExpanded ? "" : "none"
    if (toggle) toggle.setAttribute("aria-expanded", isExpanded ? "true" : "false")
    if (chevron) {
      chevron.innerHTML = isExpanded
        ? `<svg class="w-3.5 h-3.5 flex-shrink-0" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor"><path fill-rule="evenodd" d="M5.22 8.22a.75.75 0 0 1 1.06 0L10 11.94l3.72-3.72a.75.75 0 1 1 1.06 1.06l-4.25 4.25a.75.75 0 0 1-1.06 0L5.22 9.28a.75.75 0 0 1 0-1.06Z" clip-rule="evenodd" /></svg>`
        : `<svg class="w-3.5 h-3.5 flex-shrink-0" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor"><path fill-rule="evenodd" d="M8.22 5.22a.75.75 0 0 1 1.06 0l4.25 4.25a.75.75 0 0 1 0 1.06l-4.25 4.25a.75.75 0 0 1-1.06-1.06L11.94 10 8.22 6.28a.75.75 0 0 1 0-1.06Z" clip-rule="evenodd" /></svg>`
    }
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
      system: "toggle_system",
    }
    for (const [section, event] of Object.entries(sectionMap)) {
      const saved = localStorage.getItem(`sidebar_section_${section}`)
      // Server defaults all sections to expanded; if stored as collapsed, toggle once
      if (saved === "false") {
        this.pushEventTo(this.el, event, {})
      }
    }
  },

  _persistSectionToggle(section) {
    const key = `sidebar_section_${section}`
    const current = localStorage.getItem(key)
    // Default is expanded (true); toggling flips it
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
