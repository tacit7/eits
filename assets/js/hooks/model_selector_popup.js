// ModelSelectorPopup — shared searchable model picker for the DM composer,
// New Agent drawer, and New Session modal (spec:
// docs/superpowers/specs/2026-07-08-model-selector-design.md §5.3).
//
// Data arrives via data-models (JSON array of {provider, slug, label, group,
// premium, legacy, default}), serialized server-side by
// EyeInTheSkyWeb.Components.ModelSelector. All search/keyboard-nav/disclosure
// state lives client-side (agent_combobox.js pattern); the actual selected
// provider/model stays server-authoritative — on selection we push once and
// wait for the server's re-render, we do not lock in the visual state
// ourselves. updated() re-syncs from a fresh data-models (e.g. after a Pi
// discovery refresh) without losing open/search state mid-interaction.

const PRIMARY_VISIBLE_COUNT = 3

export const ModelSelectorPopup = {
  mounted() {
    this._models = this._parseModels()
    this._previousModelsJson = this.el.dataset.models || ""
    this._open = false
    this._activeIndex = -1
    this._expandedGroups = new Set()

    this._trigger = this.el.querySelector("[data-selector-trigger]")
    this._popover = this.el.querySelector("[data-selector-popover]")
    this._search = this.el.querySelector("[data-selector-search]")
    this._list = this.el.querySelector("[data-selector-list]")

    this._onTriggerClick = () => this._toggle()
    this._trigger.addEventListener("click", this._onTriggerClick)

    this._onSearchInput = () => this._render()
    this._search.addEventListener("input", this._onSearchInput)

    this._onKeydown = (e) => this._handleKeydown(e)
    this._search.addEventListener("keydown", this._onKeydown)

    this._onClickOutside = (e) => {
      if (!this.el.contains(e.target)) this._close()
    }
    document.addEventListener("mousedown", this._onClickOutside)

    this._onListMousedown = (e) => {
      const li = e.target.closest("li[data-slug]")
      if (li) {
        // stopPropagation BEFORE _select()/_render() mutate the DOM: once a
        // handler rebuilds this._list.innerHTML mid-event, e.target (the
        // original <li>) is detached from the document, so a *later*
        // ancestor listener's `el.contains(e.target)` check (our own
        // document mousedown "click outside" handler, and potentially the
        // drawer/modal's own close-on-outside-click behavior) sees a
        // detached node and treats the click as "outside" — closing
        // whatever ancestor container is listening, not just this popover.
        // That was the reported "clicking More/a row closes the whole form"
        // bug. Stopping propagation before mutating the DOM prevents any
        // ancestor from ever evaluating that stale/detached target.
        e.preventDefault()
        e.stopPropagation()
        this._select(li.dataset.provider, li.dataset.slug)
        return
      }
      const disclosure = e.target.closest("[data-disclosure-toggle]")
      if (disclosure) {
        e.preventDefault()
        e.stopPropagation()
        this._expandedGroups.add(disclosure.dataset.disclosureToggle)
        this._render()
      }
    }
    this._list.addEventListener("mousedown", this._onListMousedown)

    this._onListMousemove = (e) => {
      const li = e.target.closest("li[data-slug]")
      if (!li) return
      const items = this._visibleItems()
      const idx = items.indexOf(li)
      if (idx !== -1) this._setActive(idx)
    }
    this._list.addEventListener("mousemove", this._onListMousemove)

    this._render()
  },

  updated() {
    const newJson = this.el.dataset.models || ""
    if (newJson === this._previousModelsJson) return
    this._previousModelsJson = newJson
    this._models = this._parseModels()
    if (this._open) this._render()
  },

  destroyed() {
    this._trigger.removeEventListener("click", this._onTriggerClick)
    this._search.removeEventListener("input", this._onSearchInput)
    this._search.removeEventListener("keydown", this._onKeydown)
    document.removeEventListener("mousedown", this._onClickOutside)
    this._list.removeEventListener("mousedown", this._onListMousedown)
    this._list.removeEventListener("mousemove", this._onListMousemove)
  },

  // ---- private ----

  _parseModels() {
    try {
      const raw = this.el.dataset.models
      return raw ? JSON.parse(raw) : []
    } catch {
      return []
    }
  },

  _toggle() {
    if (this._trigger.disabled) return
    this._open ? this._close() : this._openPopover()
  },

  _openPopover() {
    this._open = true
    this._popover.classList.remove("hidden")
    this._expandGroupContainingSelection()
    this._render()
    this._search.value = ""
    // 0ms timeout so focus survives the click that triggered open.
    setTimeout(() => this._search.focus(), 0)
  },

  _close() {
    this._open = false
    this._popover.classList.add("hidden")
    this._activeIndex = -1
  },

  _expandGroupContainingSelection() {
    const selectedSlug = this.el.dataset.selectedModel
    const model = this._models.find((m) => m.slug === selectedSlug)
    if (model && (model.legacy || model.group)) this._expandedGroups.add(model.group)
  },

  _query() {
    return (this._search.value || "").trim().toLowerCase()
  },

  _render() {
    const q = this._query()
    const searching = q !== ""

    const byGroup = new Map()
    for (const m of this._models) {
      if (searching) {
        const hay = `${m.slug} ${m.label} ${m.group}`.toLowerCase()
        if (!hay.includes(q)) continue
      }
      if (!byGroup.has(m.group)) byGroup.set(m.group, [])
      byGroup.get(m.group).push(m)
    }

    let html = ""
    for (const [group, models] of byGroup) {
      const primary = models.filter((m) => !m.legacy)
      const legacy = models.filter((m) => m.legacy)
      const expanded = searching || this._expandedGroups.has(group)

      const visible = expanded ? models : primary
      const hiddenCount = expanded ? 0 : legacy.length

      html += `<div class="eits-menu__label text-mini px-3 pt-2 pb-0.5 text-base-content/40">${this._esc(group)}</div>`
      html += visible.map((m) => this._rowHtml(m, q)).join("")

      if (hiddenCount > 0) {
        html += `<div data-disclosure-toggle="${this._esc(group)}" class="px-3 py-1.5 text-mini text-base-content/40 cursor-pointer hover:text-base-content/60">More (${hiddenCount})</div>`
      } else if (group.startsWith("Ollama") || (models[0] && models[0].provider === "pi")) {
        // Pi sub-provider buckets: cap primary display separately from the
        // Claude/Codex legacy split above.
        if (!expanded && models.length > PRIMARY_VISIBLE_COUNT) {
          const shown = models.slice(0, PRIMARY_VISIBLE_COUNT)
          const rest = models.length - PRIMARY_VISIBLE_COUNT
          html = html.replace(
            visible.map((m) => this._rowHtml(m, q)).join(""),
            shown.map((m) => this._rowHtml(m, q)).join("") +
              `<div data-disclosure-toggle="${this._esc(group)}" class="px-3 py-1.5 text-mini text-base-content/40 cursor-pointer hover:text-base-content/60">Show all ${models.length}</div>`
          )
        }
      }
    }

    this._list.innerHTML = html
    this._activeIndex = 0
    this._setActive(0)
  },

  _rowHtml(m, q) {
    const active = m.slug === this.el.dataset.selectedModel
    return `<li
      data-slug="${this._esc(m.slug)}"
      data-provider="${this._esc(m.provider)}"
      role="option"
      aria-selected="${active}"
      class="flex items-center gap-2 rounded-box px-3 py-2 text-message cursor-pointer hover:bg-base-content/[0.04] aria-selected:bg-base-content/[0.06]"
    >
      <span class="w-[5px] h-[5px] rounded-full bg-primary/60 flex-shrink-0"></span>
      <span class="flex-1 truncate">${this._highlight(m.label, q)}</span>
      ${m.default ? '<span class="text-nano px-1.5 py-0.5 rounded-full bg-success/10 text-success">Recommended</span>' : ""}
      ${active ? '<svg class="size-3.5 text-primary flex-shrink-0" viewBox="0 0 20 20" fill="currentColor"><path fill-rule="evenodd" d="M16.704 4.153a.75.75 0 01.143 1.052l-8 10.5a.75.75 0 01-1.127.075l-4.5-4.5a.75.75 0 011.06-1.06l3.894 3.893 7.48-9.817a.75.75 0 011.05-.143z" clip-rule="evenodd"/></svg>' : ""}
      ${!active && m.premium ? '<span class="text-mini text-base-content/40 flex-shrink-0">$</span>' : ""}
    </li>`
  },

  _visibleItems() {
    return Array.from(this._list.querySelectorAll("li[data-slug]"))
  },

  _setActive(idx, { scroll = false } = {}) {
    // Bug fix: the previous version reset non-active rows to "their own
    // current value" (a no-op), so once a row was hovered/keyboard-active
    // its highlight never cleared. Every row not at idx must go to "false".
    const items = this._visibleItems()
    items.forEach((li, i) => li.setAttribute("aria-selected", i === idx ? "true" : "false"))
    this._activeIndex = idx
    if (scroll && items[idx]) items[idx].scrollIntoView({ block: "nearest" })
  },

  _handleKeydown(e) {
    if (!this._open) return
    const items = this._visibleItems()
    const count = items.length

    if (e.key === "ArrowDown") {
      e.preventDefault()
      if (count) this._setActive((this._activeIndex + 1) % count, { scroll: true })
    } else if (e.key === "ArrowUp") {
      e.preventDefault()
      if (count) this._setActive((this._activeIndex - 1 + count) % count, { scroll: true })
    } else if (e.key === "Enter") {
      e.preventDefault()
      const active = items[this._activeIndex]
      if (active) this._select(active.dataset.provider, active.dataset.slug)
    } else if (e.key === "Escape") {
      e.preventDefault()
      this._close()
    }
  },

  _select(provider, slug) {
    // State authority (spec §5.2): push and wait. The server re-renders
    // data-selected-provider/data-selected-model on success; on rejection
    // it re-renders the SAME (unchanged) values, and updated() below snaps
    // the trigger label back via the normal LiveView diff — no separate
    // failure branch needed here because we never touched the trigger.
    this.pushEventTo(this.el, this.el.dataset.event, { provider, model: slug })
    this._close()
  },

  _highlight(text, q) {
    if (!q) return this._esc(text)
    const idx = text.toLowerCase().indexOf(q)
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
