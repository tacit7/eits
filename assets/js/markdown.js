import { marked } from 'marked';
import { markedHighlight } from 'marked-highlight';

// hljs is large (~9 MB). Load it once on first use, then cache.
let _ready = null;

function ensureReady() {
  if (!_ready) {
    _ready = import('highlight.js').then(({ default: hljs }) => {
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
      marked.setOptions({ breaks: true, gfm: true });
    });
  }
  return _ready;
}

function stripFrontmatter(markdown) {
  if (!markdown.startsWith('---')) return markdown;
  const end = markdown.indexOf('\n---', 3);
  if (end === -1) return markdown;
  return markdown.slice(end + 4).replace(/^\n/, '');
}

const EITS_CMD_ICONS = {
  task: `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor" width="11" height="11"><path fill-rule="evenodd" d="M16.704 4.153a.75.75 0 01.143 1.052l-8 10.5a.75.75 0 01-1.127.075l-4.5-4.5a.75.75 0 011.06-1.06l3.894 3.893 7.48-9.817a.75.75 0 011.05-.143z" clip-rule="evenodd"/></svg>`,
  commit: `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor" width="11" height="11"><path fill-rule="evenodd" d="M10 2a.75.75 0 01.75.75v.258a3.25 3.25 0 010 6.484v7.758a.75.75 0 01-1.5 0V9.492a3.25 3.25 0 010-6.484V2.75A.75.75 0 0110 2zM8.5 6a1.5 1.5 0 113 0 1.5 1.5 0 01-3 0z" clip-rule="evenodd"/></svg>`,
  dm: `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor" width="11" height="11"><path d="M3.505 2.365A41.369 41.369 0 019 2c1.863 0 3.697.124 5.495.365 1.247.167 2.18 1.108 2.435 2.268a4.45 4.45 0 00-.577-.069 43.141 43.141 0 00-4.706 0C9.229 4.696 7.5 6.727 7.5 9v2.727c0 .509.211.998.582 1.353l1.2 1.133c-.388.076-.7.141-.916.191a1.5 1.5 0 01-1.366-2.513l-.076-.089A3.498 3.498 0 016 9.818v-2.09c0-2.263 1.73-4.24 4.075-4.488A39.86 39.86 0 019 3.1a39.86 39.86 0 00-3.747.213C3.886 3.451 3 4.409 3 5.5v4.977a3 3 0 001.875 2.786l.376.188C5.672 13.814 5.5 14.4 5.5 15v.5a.5.5 0 00.5.5h7a.5.5 0 00.5-.5V15c0-.6-.172-1.186-.75-1.549l.376-.188A3 3 0 0015 10.477V5.5c0-1.091-.886-2.049-2.253-2.187z"/></svg>`,
  note: `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor" width="11" height="11"><path fill-rule="evenodd" d="M4 3.5A1.5 1.5 0 015.5 2h9A1.5 1.5 0 0116 3.5v13a1.5 1.5 0 01-1.5 1.5h-9A1.5 1.5 0 014 16.5v-13zM6 7a.75.75 0 01.75-.75h6.5a.75.75 0 010 1.5h-6.5A.75.75 0 016 7zm.75 2.75a.75.75 0 000 1.5h6.5a.75.75 0 000-1.5h-6.5z" clip-rule="evenodd"/></svg>`,
};

function preprocessEitsCmds(text) {
  return text.replace(/^EITS-CMD: (.+)$/gm, (_, rest) => {
    rest = rest.trim();
    const parts = rest.split(' ');
    const cmdType = parts[0] || '';
    const action = parts[1] || '';
    const payload = parts.slice(2).join(' ');

    const icon = EITS_CMD_ICONS[cmdType] || `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor" width="11" height="11"><path fill-rule="evenodd" d="M3.25 3A2.25 2.25 0 001 5.25v9.5A2.25 2.25 0 003.25 17h13.5A2.25 2.25 0 0019 14.75v-9.5A2.25 2.25 0 0016.75 3H3.25zm.943 8.752a.75.75 0 01.05-1.06L6.44 9.5 4.243 7.308a.75.75 0 011.06-1.06l2.5 2.5a.75.75 0 010 1.06l-2.5 2.5a.75.75 0 01-1.06-.056zm4.557.748a.75.75 0 000 1.5h5a.75.75 0 000-1.5h-5z" clip-rule="evenodd"/></svg>`;

    const actionHtml = action ? `<span class="eits-cmd-action">${escapeHtml(cmdType)} ${escapeHtml(action)}</span>` : `<span class="eits-cmd-action">${escapeHtml(cmdType)}</span>`;
    const payloadHtml = payload ? `<span class="eits-cmd-payload">${escapeHtml(payload)}</span>` : '';

    return `<div class="eits-cmd-block"><span class="eits-cmd-prefix">${icon}EITS-CMD</span>${actionHtml}${payloadHtml}</div>`;
  });
}

function escapeHtml(str) {
  return str.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
}

/**
 * Render markdown with syntax highlighting.
 * Returns a Promise<string>. hljs is loaded lazily on first call.
 */
export async function renderMarkdown(markdown) {
  if (!markdown) return '';
  await ensureReady();
  return marked.parse(preprocessEitsCmds(stripFrontmatter(markdown)));
}

export default renderMarkdown;
