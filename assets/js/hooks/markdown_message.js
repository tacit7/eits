import { renderMarkdown } from '../markdown';

export const MarkdownMessage = {
  mounted() {
    this.renderContent()
  },
  updated() {
    this.renderContent()
  },
  async renderContent() {
    const raw = this.el.dataset.rawBody
    if (raw) {
      this.el.innerHTML = await renderMarkdown(raw)
    }
  }
}
