// AgentCombobox — JS-driven combobox for agent selection in NewSessionModal.
//
// Agents are encoded as JSON in data-agents (list of [slug, name, scope] arrays).
// Filters client-side, shows up to 10 matches with name + scope visible.
// Writes selected slug into the hidden input (name="agent") on selection.
//
// Codex-flagged bugs addressed:
//   1. Tuple encoding — handled server-side (tuples → lists before Jason.encode!)
//   2. HEEx JSON quoting — browser HTML parser restores &quot; → " before JS reads it; no issue
//   3. Enter key form submit — preventDefault when dropdown is open
//   4. updated() mid-selection — guard with previousAgentsJson diff

export const AgentCombobox = {
  mounted() {
    this._agents = this._parseAgents()
    this._previousAgentsJson = this.el.dataset.agents || ""
    this._activeIndex = -1
    this._open = false

    this._input = this.el.querySelector("[data-combobox-input]")
    this._list = this.el.querySelector("[data-combobox-list]")
    this._hidden = this.el.querySelector("[data-combobox-value]")

    this._onInput = () => this._filter()
    this._onKeydown = (e) => this._handleKeydown(e)
    this._onClickOutside = (e) => {
      if (!this.el.contains(e.target)) this._close()
    }

    this._input.addEventListener("input", this._onInput)
    this._input.addEventListener("keydown", this._onKeydown)
    document.addEventListener("mousedown", this._onClickOutside)

    this._list.addEventListener("mousedown", (e) => {
      const li = e.target.closest("li[data-slug]")
      if (li) {
        e.preventDefault()
        this._select(li.dataset.slug, li.dataset.label)
      }
    })

    this._list.addEventListener("mousemove", (e) => {
      const li = e.target.closest("li[data-slug]")
      if (!li) return
      const items = Array.from(this._list.querySelectorAll("li[data-slug]"))
      const idx = items.indexOf(li)
      if (idx !== -1) this._setActive(idx)
    })
  },

  updated() {
    const newJson = this.el.dataset.agents || ""
    if (newJson === this._previousAgentsJson) return
    this._previousAgentsJson = newJson
    this._agents = this._parseAgents()
    // Re-render only if dropdown is already open
    if (this._open) this._filter()
  },

  destroyed() {
    this._input.removeEventListener("input", this._onInput)
    this._input.removeEventListener("keydown", this._onKeydown)
    document.removeEventListener("mousedown", this._onClickOutside)
  },

  // ---- private ----

  _parseAgents() {
    try {
      const raw = this.el.dataset.agents
      if (!raw) return []
      return JSON.parse(raw) // [[slug, name, scope], ...]
    } catch {
      return []
    }
  },

  _filter() {
    const q = (this._input.value || "").trim().toLowerCase()
    const matches = q === ""
      ? this._agents.slice(0, 10)
      : this._agents
          .filter(([slug, name]) =>
            slug.toLowerCase().includes(q) || name.toLowerCase().includes(q)
          )
          .slice(0, 10)

    if (matches.length === 0) {
      this._close()
      return
    }

    this._render(matches, q)
    this._open = true
    this._activeIndex = 0
    this._setActive(0)
  },

  _render(matches, q) {
    this._list.innerHTML = matches.map(([slug, name, scope], i) => {
      const labelHtml = this._highlight(name, q) + ` <span class="text-base-content/40 text-xs">${this._esc(scope)}</span>`
      return `<li
        data-slug="${this._esc(slug)}"
        data-label="${this._esc(name)}"
        role="option"
        class="px-3 py-2 cursor-pointer text-sm flex items-center gap-2 hover:bg-base-300 aria-selected:bg-base-300"
        aria-selected="false"
      ><span class="font-mono text-xs text-base-content/50 w-32 truncate">${this._highlight(slug, q)}</span><span class="flex-1">${labelHtml}</span></li>`
    }).join("")
    this._list.classList.remove("hidden")
    this._input.setAttribute("aria-expanded", "true")
  },

  _close() {
    this._open = false
    this._activeIndex = -1
    this._list.classList.add("hidden")
    this._input.setAttribute("aria-expanded", "false")
    this._list.innerHTML = ""
    this._input.removeAttribute("aria-activedescendant")
  },

  _select(slug, label) {
    this._input.value = label || slug
    if (this._hidden) this._hidden.value = slug
    this._close()
  },

  _setActive(idx) {
    const items = Array.from(this._list.querySelectorAll("li[data-slug]"))
    items.forEach((li, i) => {
      li.setAttribute("aria-selected", i === idx ? "true" : "false")
    })
    this._activeIndex = idx
    if (items[idx]) {
      this._input.setAttribute("aria-activedescendant", `agent-opt-${idx}`)
      items[idx].id = `agent-opt-${idx}`
      items[idx].scrollIntoView({ block: "nearest" })
    }
  },

  _handleKeydown(e) {
    if (!this._open) return

    const items = this._list.querySelectorAll("li[data-slug]")
    const count = items.length

    if (e.key === "ArrowDown") {
      e.preventDefault()
      this._setActive((this._activeIndex + 1) % count)
    } else if (e.key === "ArrowUp") {
      e.preventDefault()
      this._setActive((this._activeIndex - 1 + count) % count)
    } else if (e.key === "Enter") {
      // Prevent form submit while dropdown is open
      e.preventDefault()
      const active = items[this._activeIndex]
      if (active) this._select(active.dataset.slug, active.dataset.label)
    } else if (e.key === "Escape") {
      e.preventDefault()
      this._close()
    } else if (e.key === "Tab") {
      // Let tab close without selecting
      this._close()
    }
  },

  _highlight(text, q) {
    if (!q) return this._esc(text)
    const idx = text.toLowerCase().indexOf(q.toLowerCase())
    if (idx === -1) return this._esc(text)
    return (
      this._esc(text.slice(0, idx)) +
      `<mark class="bg-primary/20 text-primary rounded-sm">` +
      this._esc(text.slice(idx, idx + q.length)) +
      `</mark>` +
      this._esc(text.slice(idx + q.length))
    )
  },

  _esc(str) {
    return String(str)
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;")
  },
}
