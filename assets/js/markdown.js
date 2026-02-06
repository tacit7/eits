import { marked } from 'marked';
import hljs from 'highlight.js';

// Configure marked to use highlight.js
marked.setOptions({
  highlight: function(code, lang) {
    if (lang && hljs.getLanguage(lang)) {
      try {
        return hljs.highlight(code, { language: lang }).value;
      } catch (err) {
        console.error('Highlight error:', err);
      }
    }
    return hljs.highlightAuto(code).value;
  },
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
