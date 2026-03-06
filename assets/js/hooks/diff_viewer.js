import { html as diff2html } from 'diff2html'

export const DiffViewer = {
  mounted() {
    this.render()
  },

  updated() {
    this.render()
  },

  render() {
    const raw = this.el.dataset.diff
    if (!raw || raw === '__loading__' || raw === '__error__') return

    this.el.innerHTML = diff2html(raw, {
      drawFileList: false,
      matching: 'lines',
      outputFormat: 'line-by-line',
      highlight: true,
      renderNothingWhenEmpty: true,
    })
  }
}
