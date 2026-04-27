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

    this._onFocus = () => this._filter()
    this._input.addEventListener("focus", this._onFocus)
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
    this._input.removeEventListener("focus", this._onFocus)
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

  _scopeIcon(scope) {
    if (scope === "global") {
      // Globe icon — heroicons outline globe-alt
      return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" class="size-4 shrink-0 text-base-content/70" aria-label="global"><path stroke-linecap="round" stroke-linejoin="round" d="M12 21a9.004 9.004 0 0 0 8.716-6.747M12 21a9.004 9.004 0 0 1-8.716-6.747M12 21c2.485 0 4.5-4.038 4.5-9S14.485 3 12 3m0 18c-2.485 0-4.5-4.038-4.5-9S9.515 3 12 3m0 0a8.997 8.997 0 0 1 7.843 4.582M12 3a8.997 8.997 0 0 0-7.843 4.582m15.686 0A11.953 11.953 0 0 1 12 10.5c-2.998 0-5.74-1.1-7.843-2.918m15.686 0A8.959 8.959 0 0 1 21 12c0 .778-.099 1.533-.284 2.253m0 0A17.919 17.919 0 0 1 12 16.5c-3.162 0-6.133-.815-8.716-2.247m0 0A9.015 9.015 0 0 1 3 12c0-1.605.42-3.113 1.157-4.418"/></svg>`
    }
    // Document icon — heroicons outline document-text (project scope)
    return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" class="size-4 shrink-0 text-base-content/70" aria-label="project"><path stroke-linecap="round" stroke-linejoin="round" d="M19.5 14.25v-2.625a3.375 3.375 0 0 0-3.375-3.375h-1.5A1.125 1.125 0 0 1 13.5 7.125v-1.5a3.375 3.375 0 0 0-3.375-3.375H8.25m0 12.75h7.5m-7.5 3H12M10.5 2.25H5.625c-.621 0-1.125.504-1.125 1.125v17.25c0 .621.504 1.125 1.125 1.125h12.75c.621 0 1.125-.504 1.125-1.125V11.25a9 9 0 0 0-9-9Z"/></svg>`
  },

  _render(matches, q) {
    this._list.innerHTML = matches.map(([slug, name, scope]) => {
      return `<li
        data-slug="${this._esc(slug)}"
        data-label="${this._esc(name)}"
        role="option"
        class="px-3 py-2 cursor-pointer text-sm flex items-center gap-2 hover:bg-base-300 aria-selected:bg-base-300"
        aria-selected="false"
      >${this._scopeIcon(scope)}<span class="flex-1">${this._highlight(name, q)}</span></li>`
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
