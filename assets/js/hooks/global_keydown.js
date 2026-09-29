export const GlobalKeydown = {
  mounted() {
    this._leaderKeys = []
    this._leaderTimer = null
    this._leaderTimeoutMs = 900

    this._keydownHandler = (event) => this.handleKeydown(event)
    window.addEventListener("keydown", this._keydownHandler, true)
  },

  destroyed() {
    window.removeEventListener("keydown", this._keydownHandler, true)
    this.clearLeader()
  },

  handleKeydown(event) {
    if (event.defaultPrevented || this.inEditableTarget(event.target)) return

    if (this.isLeaderKey(event)) {
      event.preventDefault()
      this._leaderKeys = []
      this.armLeader()
      return
    }

    if (!this._leaderTimer) return

    const key = this.normalizeKey(event)
    if (!key) {
      this.clearLeader()
      return
    }

    event.preventDefault()
    this._leaderKeys.push(key)
    this.armLeader()

    const sequence = this._leaderKeys.join(" ")

    if (["p p", "t p"].includes(sequence)) {
      this.clearLeader()
      this.openPaletteCommand("list-projects")
    } else if (sequence === "g t") {
      this.clearLeader()
      this.goToTasks()
    } else if (this._leaderKeys.length >= 2) {
      this.clearLeader()
    }
  },

  isLeaderKey(event) {
    return event.code === "Space" || event.key === " "
  },

  normalizeKey(event) {
    if (!event.key || event.key.length !== 1) return null
    return event.key.toLowerCase()
  },

  armLeader() {
    clearTimeout(this._leaderTimer)
    this._leaderTimer = setTimeout(() => this.clearLeader(), this._leaderTimeoutMs)
  },

  clearLeader() {
    clearTimeout(this._leaderTimer)
    this._leaderTimer = null
    this._leaderKeys = []
  },

  openPaletteCommand(commandId) {
    document.querySelector("#command-palette")?.dispatchEvent(
      new CustomEvent("palette:open-command", { detail: { commandId } })
    )
  },

  goToTasks() {
    const projectId = this.currentProjectId() || this.savedProjectId()
    const href = projectId ? `/projects/${projectId}/tasks` : "/tasks"
    window.location.assign(href)
  },

  currentProjectId() {
    const match = window.location.pathname.match(/^\/projects\/(\d+)(?:\/|$)/)
    return match ? Number(match[1]) : null
  },

  savedProjectId() {
    try {
      const state = JSON.parse(localStorage.getItem("rail_state") || "{}")
      const projectId = Number(state.project_id)
      return Number.isFinite(projectId) && projectId > 0 ? projectId : null
    } catch (_) {
      return null
    }
  },

  inEditableTarget(target) {
    return Boolean(target?.closest?.(
      "input, textarea, select, [contenteditable='true'], .cm-editor, .monaco-editor, [data-palette-no-intercept]"
    ))
  }
}
