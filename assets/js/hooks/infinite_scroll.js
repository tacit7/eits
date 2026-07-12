/**
 * InfiniteScroll hook
 *
 * Uses IntersectionObserver to fire "load_more" when the sentinel element
 * enters the viewport, regardless of which ancestor is the scroll container.
 *
 * Required data attributes on the hook element:
 *   data-has-more="true|false"  - whether more items exist server-side
 *   data-page="N"               - current page (updated each load so updated() fires)
 */
export const InfiniteScroll = {
  mounted() {
    this._loading = false
    this._isIntersecting = false

    this._observer = new IntersectionObserver((entries) => {
      const entry = entries[0]
      this._isIntersecting = entry.isIntersecting
      if (entry.isIntersecting && this._hasMore() && !this._loading) {
        this._loading = true
        this.pushEvent("load_more", {})
      }
    }, { threshold: 0 })

    this._observer.observe(this.el)
  },

  updated() {
    requestAnimationFrame(() => {
      this._loading = false
      // Re-trigger if sentinel is still visible after items loaded
      if (this._hasMore() && this._isIntersecting) {
        this._loading = true
        this.pushEvent("load_more", {})
      }
    })
  },

  destroyed() {
    if (this._observer) {
      this._observer.disconnect()
    }
  },

  _hasMore() {
    return this.el.dataset.hasMore === "true"
  }
}
