/**
 * ExpandOnSearch — auto-opens a <details> element when a search query
 * matches text in data-thinking. Does not auto-close when query clears.
 */
export const ExpandOnSearch = {
  mounted() {
    this._maybeOpen()
  },
  updated() {
    this._maybeOpen()
  },
  _maybeOpen() {
    const query = (this.el.dataset.query || "").trim()
    const thinking = this.el.dataset.thinking || ""
    if (query && thinking.toLowerCase().includes(query.toLowerCase())) {
      this.el.open = true
    }
  }
}
