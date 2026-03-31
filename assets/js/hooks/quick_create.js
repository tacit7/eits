import {showToast} from './utils'

export const QuickCreateNote = {
  mounted() {
    this._openHandler = () => {
      this.el.showModal()
      this.el.querySelector("[data-qcn-title]")?.focus()
    }
    window.addEventListener("palette:create-note", this._openHandler)

    this.el.querySelector("[data-qcn-form]")?.addEventListener("submit", (e) => {
      e.preventDefault()
      this._submit()
    })

    this.el.querySelectorAll("[data-qcn-cancel]").forEach(btn =>
      btn.addEventListener("click", () => this.el.close())
    )
  },

  destroyed() {
    window.removeEventListener("palette:create-note", this._openHandler)
  },

  async _submit() {
    const title = (this.el.querySelector("[data-qcn-title]")?.value || "").trim()
    const body = (this.el.querySelector("[data-qcn-body]")?.value || "").trim()
    if (!title) return

    const payload = { title, body }

    try {
      const res = await fetch("/api/v1/notes", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(payload)
      })
      if (res.ok) {
        this.el.close()
        this._reset()
        showToast("Note created")
      } else {
        showToast("Failed to create note")
      }
    } catch (_) {
      showToast("Failed to create note")
    }
  },

  _reset() {
    const t = this.el.querySelector("[data-qcn-title]")
    const b = this.el.querySelector("[data-qcn-body]")
    if (t) t.value = ""
    if (b) b.value = ""
  }
}

export const QuickCreateAgent = {
  mounted() {
    this._openHandler = () => {
      this.el.showModal()
      this.el.querySelector("[data-qca-instructions]")?.focus()
    }
    window.addEventListener("palette:create-agent", this._openHandler)

    this.el.querySelector("[data-qca-form]")?.addEventListener("submit", (e) => {
      e.preventDefault()
      this._submit()
    })

    this.el.querySelectorAll("[data-qca-cancel]").forEach(btn =>
      btn.addEventListener("click", () => this.el.close())
    )
  },

  destroyed() {
    window.removeEventListener("palette:create-agent", this._openHandler)
  },

  async _submit() {
    const instructions = (this.el.querySelector("[data-qca-instructions]")?.value || "").trim()
    if (!instructions) return

    const model = this.el.querySelector("[data-qca-model]")?.value || "haiku"
    const projectId = this.el.dataset.projectId ? Number(this.el.dataset.projectId) : null

    const body = { instructions, model }
    if (projectId) body.project_id = projectId

    try {
      const res = await fetch("/api/v1/agents", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(body)
      })
      if (res.ok) {
        const data = await res.json()
        this.el.close()
        this._reset()
        window.location.assign("/dm/" + data.session_uuid)
      } else {
        showToast("Failed to spawn agent")
      }
    } catch (_) {
      showToast("Failed to spawn agent")
    }
  },

  _reset() {
    const i = this.el.querySelector("[data-qca-instructions]")
    const m = this.el.querySelector("[data-qca-model]")
    if (i) i.value = ""
    if (m) m.value = "haiku"
  }
}

export const QuickCreateChat = {
  mounted() {
    this._openHandler = () => {
      this.el.showModal()
      this.el.querySelector("[data-qcc-name]")?.focus()
    }
    window.addEventListener("palette:create-chat", this._openHandler)

    this.el.querySelector("[data-qcc-form]")?.addEventListener("submit", (e) => {
      e.preventDefault()
      this._submit()
    })

    this.el.querySelectorAll("[data-qcc-cancel]").forEach(btn =>
      btn.addEventListener("click", () => this.el.close())
    )
  },

  destroyed() {
    window.removeEventListener("palette:create-chat", this._openHandler)
  },

  async _submit() {
    const name = (this.el.querySelector("[data-qcc-name]")?.value || "").trim()
    const projectId = this.el.dataset.projectId ? Number(this.el.dataset.projectId) : null

    const sessionId = crypto.randomUUID()
    const body = { session_id: sessionId }
    if (name) body.name = name
    if (projectId) body.project_id = projectId

    try {
      const res = await fetch("/api/v1/sessions", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(body)
      })
      if (res.ok) {
        const data = await res.json()
        this.el.close()
        window.location.assign("/dm/" + data.uuid)
      } else {
        showToast("Failed to create chat")
      }
    } catch (_) {
      showToast("Failed to create chat")
    }
  }
}

export const QuickCreateTask = {
  mounted() {
    this._openHandler = () => {
      this.el.showModal()
      this.el.querySelector("[data-qct-title]")?.focus()
    }
    window.addEventListener("palette:create-task", this._openHandler)

    this.handleEvent("palette:create-task-result", ({ ok, error }) => {
      if (ok) {
        this.el.close()
        this._reset()
        showToast("Task created")
      } else {
        showToast(error || "Failed to create task")
      }
    })

    this.el.querySelector("[data-qct-form]")?.addEventListener("submit", (e) => {
      e.preventDefault()
      this._submit()
    })

    this.el.querySelectorAll("[data-qct-cancel]").forEach(btn =>
      btn.addEventListener("click", () => this.el.close())
    )
  },

  destroyed() {
    window.removeEventListener("palette:create-task", this._openHandler)
  },

  _submit() {
    const title = (this.el.querySelector("[data-qct-title]")?.value || "").trim()
    if (!title) return

    const description = (this.el.querySelector("[data-qct-description]")?.value || "").trim()
    const tagsRaw = (this.el.querySelector("[data-qct-tags]")?.value || "").trim()
    const tags = tagsRaw ? tagsRaw.split(",").map(t => t.trim()).filter(Boolean) : []
    const projectId = this.el.dataset.projectId || null

    this.pushEvent("palette:create-task", { title, description, tags, project_id: projectId })
  },

  _reset() {
    const t = this.el.querySelector("[data-qct-title]")
    const d = this.el.querySelector("[data-qct-description]")
    const g = this.el.querySelector("[data-qct-tags]")
    if (t) t.value = ""
    if (d) d.value = ""
    if (g) g.value = ""
  }
}
