/**
 * InfiniteScroll hook
 *
 * Attaches a scroll listener to #main-content and fires "load_more"
 * when within 200px of the bottom.
 *
 * Required data attributes on the hook element:
 *   data-has-more="true|false"  - whether more items exist server-side
 *   data-page="N"               - current page (updated each load so updated() fires)
 */
export const InfiniteScroll = {
  mounted() {
    this._loading = false
    this._container = document.getElementById("main-content")
    if (!this._container) return

    this._handleScroll = () => {
      if (this._loading || !this._hasMore()) return
      const { scrollTop, scrollHeight, clientHeight } = this._container
      if (scrollHeight - scrollTop - clientHeight < 200) {
        this._loading = true
        this.pushEvent("load_more", {})
      }
    }

    this._container.addEventListener("scroll", this._handleScroll, { passive: true })
  },

  updated() {
    requestAnimationFrame(() => {
      this._loading = false
    })
  },

  destroyed() {
    if (this._container && this._handleScroll) {
      this._container.removeEventListener("scroll", this._handleScroll)
    }
  },

  _hasMore() {
    return this.el.dataset.hasMore === "true"
  }
}
