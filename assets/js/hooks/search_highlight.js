/**
 * SearchHighlight — client-side text match highlighting for the DM messages pane.
 *
 * Mounted on the outer messages wrapper div. Reads data-query from the element,
 * walks all descendant text nodes via TreeWalker, wraps matches in
 * <mark class="search-match" data-match-id="N">, and drives the counter overlay
 * (search-counter-label, search-counter-prev, search-counter-next) via direct DOM writes.
 *
 * Does NOT use innerHTML replacement — that would destroy event listeners attached
 * to message elements (copy buttons, phx-hook elements, etc.).
 *
 * Navigation:
 *   prev / next buttons cycle through matches, applying search-match-active class
 *   and scrolling the active mark into view.
 * Escape: pushes search_messages {query: ""} to clear the query.
 */

export const SearchHighlight = {
  mounted() {
    this._activeIndex = 0
    this._matches = []

    // Prev button
    this._prevHandler = () => this._navigate(-1)
    // Next button
    this._nextHandler = () => this._navigate(1)

    const prev = document.getElementById("search-counter-prev")
    const next = document.getElementById("search-counter-next")
    const close = document.getElementById("search-counter-close")
    if (prev) prev.addEventListener("click", this._prevHandler)
    if (next) next.addEventListener("click", this._nextHandler)
    if (close) close.addEventListener("click", () => this._clearSearch())

    // Escape key
    this._keyHandler = (e) => {
      if (e.key === "Escape" && this._matches.length > 0) {
        this._clearSearch()
      }
    }
    window.addEventListener("keydown", this._keyHandler)

    this._apply()
  },

  updated() {
    this._apply()
  },

  destroyed() {
    const prev = document.getElementById("search-counter-prev")
    const next = document.getElementById("search-counter-next")
    const close = document.getElementById("search-counter-close")
    if (prev) prev.removeEventListener("click", this._prevHandler)
    if (next) next.removeEventListener("click", this._nextHandler)
    if (close) close.removeEventListener("click", this._clearSearch)
    window.removeEventListener("keydown", this._keyHandler)
  },

  _apply() {
    const query = (this.el.dataset.query || "").trim()

    // Always unwrap existing marks first to start clean
    this._unwrapMarks()

    if (!query) {
      this._activeIndex = 0
      this._matches = []
      this._updateCounter(0, 0)
      this._setOverlayVisible(false)
      return
    }

    this._markMatches(query)
    this._matches = Array.from(this.el.querySelectorAll("mark.search-match"))

    if (this._matches.length === 0) {
      this._updateCounter(0, 0)
      this._setOverlayVisible(true)
      return
    }

    // Clamp active index in case the match count changed (e.g. new messages loaded)
    this._activeIndex = Math.min(this._activeIndex, this._matches.length - 1)
    this._applyActive()
    this._setOverlayVisible(true)
  },

  _markMatches(query) {
    const lowerQuery = query.toLowerCase()
    const walker = document.createTreeWalker(
      this.el,
      NodeFilter.SHOW_TEXT,
      {
        acceptNode(node) {
          // Skip text inside existing marks (won't exist since we unwrapped first, but safe)
          if (node.parentElement && node.parentElement.classList.contains("search-match")) {
            return NodeFilter.FILTER_REJECT
          }
          // Skip script / style / code blocks that shouldn't be highlighted
          const tag = node.parentElement && node.parentElement.tagName
          if (tag === "SCRIPT" || tag === "STYLE") return NodeFilter.FILTER_REJECT
          return NodeFilter.FILTER_ACCEPT
        }
      }
    )

    const textNodes = []
    let node
    while ((node = walker.nextNode())) {
      textNodes.push(node)
    }

    let matchId = 0
    for (const textNode of textNodes) {
      const text = textNode.nodeValue
      const lower = text.toLowerCase()
      let lastIndex = 0
      const fragments = []
      let idx

      while ((idx = lower.indexOf(lowerQuery, lastIndex)) !== -1) {
        if (idx > lastIndex) {
          fragments.push(document.createTextNode(text.slice(lastIndex, idx)))
        }
        const mark = document.createElement("mark")
        mark.className = "search-match"
        mark.dataset.matchId = String(matchId++)
        mark.textContent = text.slice(idx, idx + query.length)
        fragments.push(mark)
        lastIndex = idx + query.length
      }

      if (fragments.length === 0) continue

      if (lastIndex < text.length) {
        fragments.push(document.createTextNode(text.slice(lastIndex)))
      }

      const parent = textNode.parentNode
      if (!parent) continue

      // Replace the single text node with the fragment array
      const frag = document.createDocumentFragment()
      for (const f of fragments) frag.appendChild(f)
      parent.replaceChild(frag, textNode)
    }
  },

  _unwrapMarks() {
    // querySelectorAll returns a static NodeList — safe to iterate while mutating
    const marks = this.el.querySelectorAll("mark.search-match")
    marks.forEach((mark) => {
      const parent = mark.parentNode
      if (!parent) return
      // Replace mark with its text content
      parent.replaceChild(document.createTextNode(mark.textContent), mark)
      // Normalize adjacent text nodes so the next TreeWalker pass sees clean text
      parent.normalize()
    })
  },

  _navigate(dir) {
    if (this._matches.length === 0) return
    this._matches[this._activeIndex].classList.remove("search-match-active")
    this._activeIndex = (this._activeIndex + dir + this._matches.length) % this._matches.length
    this._applyActive()
  },

  _applyActive() {
    this._matches.forEach((m) => m.classList.remove("search-match-active"))
    const active = this._matches[this._activeIndex]
    if (active) {
      active.classList.add("search-match-active")
      active.scrollIntoView({ block: "nearest", inline: "nearest" })
    }
    this._updateCounter(this._activeIndex + 1, this._matches.length)
  },

  _updateCounter(current, total) {
    const label = document.getElementById("search-counter-label")
    if (label) {
      label.textContent = total === 0 ? "no matches" : `${current} / ${total}`
    }
  },

  _setOverlayVisible(visible) {
    const overlay = document.getElementById("search-counter-overlay")
    if (!overlay) return
    if (visible) {
      overlay.classList.remove("hidden")
    } else {
      overlay.classList.add("hidden")
    }
  },

  _clearSearch() {
    this.pushEvent("search_messages", { query: "" })
  },
}
