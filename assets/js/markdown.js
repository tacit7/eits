import { marked } from 'marked';
import { markedHighlight } from 'marked-highlight';
import hljs from 'highlight.js';

marked.use(
  markedHighlight({
    langPrefix: 'hljs language-',
    highlight(code, lang) {
      if (lang && hljs.getLanguage(lang)) {
        try {
          return hljs.highlight(code, { language: lang }).value;
        } catch (err) {
          console.error('Highlight error:', err);
        }
      }
      return hljs.highlightAuto(code).value;
    }
  })
);

marked.setOptions({
  breaks: true,
  gfm: true
});

/**
 * Render markdown with syntax highlighting
 * @param {string} markdown - The markdown text to render
 * @returns {string} HTML string with syntax highlighting
 */
export function renderMarkdown(markdown) {
  if (!markdown) return '';
  return marked.parse(markdown);
}

export default renderMarkdown;
