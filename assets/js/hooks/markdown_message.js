import { renderMarkdown } from '../markdown';

export const MarkdownMessage = {
  mounted() {
    this.renderContent()
  },
  updated() {
    this.renderContent()
  },
  renderContent() {
    const raw = this.el.dataset.rawBody
    if (raw) {
      this.el.innerHTML = renderMarkdown(raw)
    }
  }
}
