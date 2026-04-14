// Uses the shared core-only hljs instance from hljs_instance.js.
// Core build + explicit language registration keeps the syntax chunk ~80KB
// instead of the ~1MB full build that ships all 384 languages.
import { getHljs } from '../hljs_instance.js'

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
