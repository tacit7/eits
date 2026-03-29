export const DiffViewer = {
  mounted() {
    this.render()
  },

  updated() {
    this.render()
  },

  async render() {
    const raw = this.el.dataset.diff
    if (!raw || raw === '__loading__' || raw === '__error__') return

    const { html: diff2html } = await import('diff2html')
    this.el.innerHTML = diff2html(raw, {
      drawFileList: false,
      matching: 'lines',
      outputFormat: 'line-by-line',
      highlight: true,
      renderNothingWhenEmpty: true,
    })
  }
}
