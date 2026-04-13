import {showToast} from './utils'

// Factory for quick-create hooks that share the open/form-submit/cancel/result pattern.
// eventPrefix: the palette event name (e.g. "palette:create-note")
// opts.focusSelector: selector for the element to focus on open
// opts.formSelector: selector for the form element
// opts.cancelSelector: selector for cancel buttons
// opts.cancelResets: if true, cancel also calls _reset()
// opts.onSuccess: function called with payload when result is ok (after close+reset)
// opts.submit: function implementing _submit() — called with hook as `this`
// opts.reset: function implementing _reset() — called with hook as `this`
function createQuickHook(eventPrefix, opts) {
  const {
    focusSelector,
    formSelector,
    cancelSelector,
    cancelResets = false,
    onSuccess,
    submit,
    reset
  } = opts

  return {
    mounted() {
      this._openHandler = () => {
        this.el.showModal()
        this.el.querySelector(focusSelector)?.focus()
      }
      window.addEventListener(eventPrefix, this._openHandler)

      this.handleEvent(`${eventPrefix}-result`, (payload) => {
        const {ok, error} = payload
        if (ok) {
          this.el.close()
          this._reset()
          onSuccess?.call(this, payload)
        } else {
          showToast(error || "Operation failed")
        }
      })

      this.el.querySelector(formSelector)?.addEventListener("submit", (e) => {
        e.preventDefault()
        this._submit()
      })

      this.el.querySelectorAll(cancelSelector).forEach(btn =>
        btn.addEventListener("click", () => {
          this.el.close()
          if (cancelResets) this._reset()
        })
      )
    },

    destroyed() {
      window.removeEventListener(eventPrefix, this._openHandler)
    },

    _submit() { submit.call(this) },
    _reset() { reset?.call(this) }
  }
}

export const QuickCreateNote = createQuickHook("palette:create-note", {
  focusSelector: "[data-qcn-title]",
  formSelector: "[data-qcn-form]",
  cancelSelector: "[data-qcn-cancel]",
  onSuccess: () => showToast("Note created"),
  submit() {
    const title = (this.el.querySelector("[data-qcn-title]")?.value || "").trim()
    const body = (this.el.querySelector("[data-qcn-body]")?.value || "").trim()
    if (!title) return
    this.pushEvent("palette:create-note", {title, body})
  },
  reset() {
    const t = this.el.querySelector("[data-qcn-title]")
    const b = this.el.querySelector("[data-qcn-body]")
    if (t) t.value = ""
    if (b) b.value = ""
  }
})

export const QuickCreateAgent = createQuickHook("palette:create-agent", {
  focusSelector: "[data-qca-instructions]",
  formSelector: "[data-qca-form]",
  cancelSelector: "[data-qca-cancel]",
  onSuccess({session_uuid}) { window.location.assign("/dm/" + session_uuid) },
  submit() {
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
  reset() {
    const i = this.el.querySelector("[data-qca-instructions]")
    const m = this.el.querySelector("[data-qca-model]")
    const p = this.el.querySelector("[data-qca-parent-session]")
    if (i) i.value = ""
    if (m) m.value = "haiku"
    if (p) p.value = ""
  }
})

export const QuickUpdateAgent = createQuickHook("palette:update-agent", {
  focusSelector: "[data-qua-agent-uuid]",
  formSelector: "[data-qua-form]",
  cancelSelector: "[data-qua-cancel]",
  onSuccess: () => showToast("Agent instructions updated successfully"),
  submit() {
    const agentUuid = (this.el.querySelector("[data-qua-agent-uuid]")?.value || "").trim()
    const instructions = (this.el.querySelector("[data-qua-instructions]")?.value || "").trim()
    if (!agentUuid || !instructions) return
    this.pushEvent("palette:update-agent", {agent_uuid: agentUuid, instructions})
  },
  reset() {
    const u = this.el.querySelector("[data-qua-agent-uuid]")
    const i = this.el.querySelector("[data-qua-instructions]")
    if (u) u.value = ""
    if (i) i.value = ""
  }
})

export const QuickGetAgent = {
  mounted() {
    this._openHandler = () => {
      this.el.showModal()
      this.el.querySelector("[data-qga-agent-uuid]")?.focus()
      this._hideResult()
    }
    window.addEventListener("palette:get-agent", this._openHandler)

    this.handleEvent("palette:get-agent-result", ({ok, agent, error}) => {
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
    this.pushEvent("palette:get-agent", {agent_uuid: agentUuid})
  },

  _showResult(agent) {
    const resultDiv = this.el.querySelector("[data-qga-result]")
    if (!resultDiv) return

    resultDiv.classList.remove("hidden")

    const setField = (selector, value) => {
      const el = this.el.querySelector(selector)
      if (el) el.textContent = value || "—"
    }

    setField("[data-qga-result-uuid]", agent.uuid)
    setField("[data-qga-result-name]", agent.name)
    setField("[data-qga-result-status]", agent.status)
    setField("[data-qga-result-sessions]", agent.session_count)

    const instructionsContainer = this.el.querySelector("[data-qga-result-instructions-container]")
    if (agent.instructions) {
      instructionsContainer?.classList.remove("hidden")
      setField("[data-qga-result-instructions]", agent.instructions)
    } else {
      instructionsContainer?.classList.add("hidden")
    }

    const projectContainer = this.el.querySelector("[data-qga-result-project-container]")
    if (agent.project_name) {
      projectContainer?.classList.remove("hidden")
      setField("[data-qga-result-project]", agent.project_name)
    } else {
      projectContainer?.classList.add("hidden")
    }

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

export const QuickDeleteAgent = createQuickHook("palette:delete-agent", {
  focusSelector: "[data-qda-agent-uuid]",
  formSelector: "[data-qda-form]",
  cancelSelector: "[data-qda-cancel]",
  cancelResets: true,
  onSuccess: () => showToast("Agent deleted successfully"),
  submit() {
    const agentUuid = (this.el.querySelector("[data-qda-agent-uuid]")?.value || "").trim()
    if (!agentUuid) return
    if (!confirm(`Are you sure you want to delete agent ${agentUuid}?`)) return
    this.pushEvent("palette:delete-agent", {agent_uuid: agentUuid})
  },
  reset() {
    const u = this.el.querySelector("[data-qda-agent-uuid]")
    if (u) u.value = ""
  }
})

export const QuickResumeAgent = createQuickHook("palette:resume-agent", {
  focusSelector: "[data-qra-agent-uuid]",
  formSelector: "[data-qra-form]",
  cancelSelector: "[data-qra-cancel]",
  cancelResets: true,
  onSuccess({session_uuid}) { window.location.assign("/dm/" + session_uuid) },
  submit() {
    const agentUuid = (this.el.querySelector("[data-qra-agent-uuid]")?.value || "").trim()
    const instructions = (this.el.querySelector("[data-qra-instructions]")?.value || "").trim()
    if (!agentUuid) return
    this.pushEvent("palette:resume-agent", {
      agent_uuid: agentUuid,
      instructions: instructions || null
    })
  },
  reset() {
    const u = this.el.querySelector("[data-qra-agent-uuid]")
    const i = this.el.querySelector("[data-qra-instructions]")
    if (u) u.value = ""
    if (i) i.value = ""
  }
})

export const QuickCreateChat = createQuickHook("palette:create-chat", {
  focusSelector: "[data-qcc-name]",
  formSelector: "[data-qcc-form]",
  cancelSelector: "[data-qcc-cancel]",
  onSuccess({session_uuid}) { window.location.assign("/dm/" + session_uuid) },
  submit() {
    const name = (this.el.querySelector("[data-qcc-name]")?.value || "").trim()
    const sessionUuid = crypto.randomUUID()
    const projectId = this.el.dataset.projectId || null
    this.pushEvent("palette:create-chat", {name, session_uuid: sessionUuid, project_id: projectId})
  }
})

export const QuickCreateTask = createQuickHook("palette:create-task", {
  focusSelector: "[data-qct-title]",
  formSelector: "[data-qct-form]",
  cancelSelector: "[data-qct-cancel]",
  onSuccess: () => showToast("Task created"),
  submit() {
    const title = (this.el.querySelector("[data-qct-title]")?.value || "").trim()
    if (!title) return
    const description = (this.el.querySelector("[data-qct-description]")?.value || "").trim()
    const tagsRaw = (this.el.querySelector("[data-qct-tags]")?.value || "").trim()
    const tags = tagsRaw ? tagsRaw.split(",").map(t => t.trim()).filter(Boolean) : []
    const projectId = this.el.dataset.projectId || null
    this.pushEvent("palette:create-task", {title, description, tags, project_id: projectId})
  },
  reset() {
    const t = this.el.querySelector("[data-qct-title]")
    const d = this.el.querySelector("[data-qct-description]")
    const g = this.el.querySelector("[data-qct-tags]")
    if (t) t.value = ""
    if (d) d.value = ""
    if (g) g.value = ""
  }
})
