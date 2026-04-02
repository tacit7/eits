import {showToast} from './utils'

export const QuickCreateNote = {
  mounted() {
    this._openHandler = () => {
      this.el.showModal()
      this.el.querySelector("[data-qcn-title]")?.focus()
    }
    window.addEventListener("palette:create-note", this._openHandler)

    this.handleEvent("palette:create-note-result", ({ ok, error }) => {
      if (ok) {
        this.el.close()
        this._reset()
        showToast("Note created")
      } else {
        showToast(error || "Failed to create note")
      }
    })

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

  _submit() {
    const title = (this.el.querySelector("[data-qcn-title]")?.value || "").trim()
    const body = (this.el.querySelector("[data-qcn-body]")?.value || "").trim()
    if (!title) return

    this.pushEvent("palette:create-note", { title, body })
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

    this.handleEvent("palette:create-agent-result", ({ ok, session_uuid, error }) => {
      if (ok) {
        this.el.close()
        this._reset()
        window.location.assign("/dm/" + session_uuid)
      } else {
        showToast(error || "Failed to spawn agent")
      }
    })

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

  _submit() {
    const instructions = (this.el.querySelector("[data-qca-instructions]")?.value || "").trim()
    if (!instructions) return

    const model = this.el.querySelector("[data-qca-model]")?.value || "haiku"
    const projectId = this.el.dataset.projectId || null
    const parentSessionUuid = (this.el.querySelector("[data-qca-parent-session]")?.value || "").trim()

    this.pushEvent("palette:create-agent", {
      instructions,
      model,
      project_id: projectId,
      parent_session_uuid: parentSessionUuid || null
    })
  },

  _reset() {
    const i = this.el.querySelector("[data-qca-instructions]")
    const m = this.el.querySelector("[data-qca-model]")
    const p = this.el.querySelector("[data-qca-parent-session]")
    if (i) i.value = ""
    if (m) m.value = "haiku"
    if (p) p.value = ""
  }
}

export const QuickUpdateAgent = {
  mounted() {
    this._openHandler = () => {
      this.el.showModal()
      this.el.querySelector("[data-qua-agent-uuid]")?.focus()
    }
    window.addEventListener("palette:update-agent", this._openHandler)

    this.handleEvent("palette:update-agent-result", ({ ok, error }) => {
      if (ok) {
        this.el.close()
        this._reset()
        showToast("Agent instructions updated successfully")
      } else {
        showToast(error || "Failed to update agent")
      }
    })

    this.el.querySelector("[data-qua-form]")?.addEventListener("submit", (e) => {
      e.preventDefault()
      this._submit()
    })

    this.el.querySelectorAll("[data-qua-cancel]").forEach(btn =>
      btn.addEventListener("click", () => this.el.close())
    )
  },

  destroyed() {
    window.removeEventListener("palette:update-agent", this._openHandler)
  },

  _submit() {
    const agentUuid = (this.el.querySelector("[data-qua-agent-uuid]")?.value || "").trim()
    const instructions = (this.el.querySelector("[data-qua-instructions]")?.value || "").trim()

    if (!agentUuid || !instructions) return

    this.pushEvent("palette:update-agent", { agent_uuid: agentUuid, instructions })
  },

  _reset() {
    const u = this.el.querySelector("[data-qua-agent-uuid]")
    const i = this.el.querySelector("[data-qua-instructions]")
    if (u) u.value = ""
    if (i) i.value = ""
  }
}

export const QuickGetAgent = {
  mounted() {
    this._openHandler = () => {
      this.el.showModal()
      this.el.querySelector("[data-qga-agent-uuid]")?.focus()
      this._hideResult()
    }
    window.addEventListener("palette:get-agent", this._openHandler)

    this.handleEvent("palette:get-agent-result", ({ ok, agent, error }) => {
      if (ok && agent) {
        this._showResult(agent)
      } else {
        this._hideResult()
        showToast(error || "Failed to get agent details")
      }
    })

    this.el.querySelector("[data-qga-form]")?.addEventListener("submit", (e) => {
      e.preventDefault()
      this._submit()
    })

    this.el.querySelectorAll("[data-qga-cancel]").forEach(btn =>
      btn.addEventListener("click", () => {
        this.el.close()
        this._reset()
      })
    )
  },

  destroyed() {
    window.removeEventListener("palette:get-agent", this._openHandler)
  },

  _submit() {
    const agentUuid = (this.el.querySelector("[data-qga-agent-uuid]")?.value || "").trim()
    if (!agentUuid) return

    this.pushEvent("palette:get-agent", { agent_uuid: agentUuid })
  },

  _showResult(agent) {
    const resultDiv = this.el.querySelector("[data-qga-result]")
    if (!resultDiv) return

    // Show the result div
    resultDiv.classList.remove("hidden")

    // Populate fields
    const setField = (selector, value) => {
      const el = this.el.querySelector(selector)
      if (el) el.textContent = value || "—"
    }

    setField("[data-qga-result-uuid]", agent.uuid)
    setField("[data-qga-result-name]", agent.name)
    setField("[data-qga-result-status]", agent.status)
    setField("[data-qga-result-sessions]", agent.session_count)

    // Instructions
    const instructionsContainer = this.el.querySelector("[data-qga-result-instructions-container]")
    if (agent.instructions) {
      instructionsContainer?.classList.remove("hidden")
      setField("[data-qga-result-instructions]", agent.instructions)
    } else {
      instructionsContainer?.classList.add("hidden")
    }

    // Project
    const projectContainer = this.el.querySelector("[data-qga-result-project-container]")
    if (agent.project_name) {
      projectContainer?.classList.remove("hidden")
      setField("[data-qga-result-project]", agent.project_name)
    } else {
      projectContainer?.classList.add("hidden")
    }

    // Created date
    const createdContainer = this.el.querySelector("[data-qga-result-created-container]")
    if (agent.created_at) {
      createdContainer?.classList.remove("hidden")
      setField("[data-qga-result-created]", new Date(agent.created_at).toLocaleString())
    } else {
      createdContainer?.classList.add("hidden")
    }
  },

  _hideResult() {
    const resultDiv = this.el.querySelector("[data-qga-result]")
    if (resultDiv) resultDiv.classList.add("hidden")
  },

  _reset() {
    const u = this.el.querySelector("[data-qga-agent-uuid]")
    if (u) u.value = ""
    this._hideResult()
  }
}

export const QuickDeleteAgent = {
  mounted() {
    this._openHandler = () => {
      this.el.showModal()
      this.el.querySelector("[data-qda-agent-uuid]")?.focus()
    }
    window.addEventListener("palette:delete-agent", this._openHandler)

    this.handleEvent("palette:delete-agent-result", ({ ok, error }) => {
      if (ok) {
        this.el.close()
        this._reset()
        showToast("Agent deleted successfully")
      } else {
        showToast(error || "Failed to delete agent")
      }
    })

    this.el.querySelector("[data-qda-form]")?.addEventListener("submit", (e) => {
      e.preventDefault()
      this._submit()
    })

    this.el.querySelectorAll("[data-qda-cancel]").forEach(btn =>
      btn.addEventListener("click", () => {
        this.el.close()
        this._reset()
      })
    )
  },

  destroyed() {
    window.removeEventListener("palette:delete-agent", this._openHandler)
  },

  _submit() {
    const agentUuid = (this.el.querySelector("[data-qda-agent-uuid]")?.value || "").trim()
    if (!agentUuid) return

    // Double confirmation
    const confirmMessage = `Are you sure you want to delete agent ${agentUuid}?`
    if (!confirm(confirmMessage)) return

    this.pushEvent("palette:delete-agent", { agent_uuid: agentUuid })
  },

  _reset() {
    const u = this.el.querySelector("[data-qda-agent-uuid]")
    if (u) u.value = ""
  }
}

export const QuickResumeAgent = {
  mounted() {
    this._openHandler = () => {
      this.el.showModal()
      this.el.querySelector("[data-qra-agent-uuid]")?.focus()
    }
    window.addEventListener("palette:resume-agent", this._openHandler)

    this.handleEvent("palette:resume-agent-result", ({ ok, session_uuid, error }) => {
      if (ok) {
        this.el.close()
        this._reset()
        // Redirect to the new session
        window.location.assign("/dm/" + session_uuid)
      } else {
        showToast(error || "Failed to resume agent")
      }
    })

    this.el.querySelector("[data-qra-form]")?.addEventListener("submit", (e) => {
      e.preventDefault()
      this._submit()
    })

    this.el.querySelectorAll("[data-qra-cancel]").forEach(btn =>
      btn.addEventListener("click", () => {
        this.el.close()
        this._reset()
      })
    )
  },

  destroyed() {
    window.removeEventListener("palette:resume-agent", this._openHandler)
  },

  _submit() {
    const agentUuid = (this.el.querySelector("[data-qra-agent-uuid]")?.value || "").trim()
    const instructions = (this.el.querySelector("[data-qra-instructions]")?.value || "").trim()

    if (!agentUuid) return

    this.pushEvent("palette:resume-agent", {
      agent_uuid: agentUuid,
      instructions: instructions || null
    })
  },

  _reset() {
    const u = this.el.querySelector("[data-qra-agent-uuid]")
    const i = this.el.querySelector("[data-qra-instructions]")
    if (u) u.value = ""
    if (i) i.value = ""
  }
}

export const QuickCreateChat = {
  mounted() {
    this._openHandler = () => {
      this.el.showModal()
      this.el.querySelector("[data-qcc-name]")?.focus()
    }
    window.addEventListener("palette:create-chat", this._openHandler)

    this.handleEvent("palette:create-chat-result", ({ ok, session_uuid, error }) => {
      if (ok) {
        this.el.close()
        window.location.assign("/dm/" + session_uuid)
      } else {
        showToast(error || "Failed to create chat")
      }
    })

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

  _submit() {
    const name = (this.el.querySelector("[data-qcc-name]")?.value || "").trim()
    const sessionUuid = crypto.randomUUID()
    const projectId = this.el.dataset.projectId || null

    this.pushEvent("palette:create-chat", { name, session_uuid: sessionUuid, project_id: projectId })
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
