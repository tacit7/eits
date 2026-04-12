// highlight.js is loaded lazily so it stays out of the main bundle.
// Both this hook and markdown.js use dynamic imports, which lets Vite
// create one standalone hljs chunk with no app.js re-import side-effects.
let _hljs = null
async function getHljs() {
  if (!_hljs) _hljs = (await import('highlight.js')).default
  return _hljs
}

export const Highlight = {
  async mounted() {
    const hljs = await getHljs()
    hljs.highlightElement(this.el)
  },
  async updated() {
    const hljs = await getHljs()
    hljs.highlightElement(this.el)
  }
}
