# Marked.js Integration in Notes Tab

## Overview

The NotesTab component uses [marked.js](https://github.com/markedjs/marked) (v17.0.1) to render markdown content stored in session notes.

## Configuration

```javascript
marked.setOptions({
  gfm: true,           // GitHub Flavored Markdown
  breaks: true,        // Convert \n to <br>
  headerIds: true,     // Add IDs to headers
  mangle: false,       // Don't mangle email addresses
  pedantic: false,     // Use original markdown.pl behavior
})
```

## Features Supported

### GitHub Flavored Markdown (GFM)
- ✅ Tables
- ✅ Strikethrough (`~~text~~`)
- ✅ Autolinks
- ✅ Task lists (`- [ ]` and `- [x]`)

### Standard Markdown
- ✅ Headers (`#` through `######`)
- ✅ Bold (`**text**`) and italic (`*text*`)
- ✅ Code blocks with syntax highlighting classes
- ✅ Inline code (`` `code` ``)
- ✅ Lists (ordered and unordered)
- ✅ Blockquotes (`>`)
- ✅ Links and images
- ✅ Horizontal rules (`---`)

## Styling

The rendered markdown is wrapped in Tailwind's `prose` classes:

```html
<div class="prose prose-sm max-w-none dark:prose-invert
            prose-headings:font-semibold
            prose-h1:text-2xl prose-h1:mb-3
            prose-h2:text-xl prose-h2:mb-2
            prose-h3:text-lg prose-h3:mb-2
            prose-p:mb-2
            prose-ul:mb-2 prose-ol:mb-2
            prose-li:mb-1
            prose-code:bg-base-200 prose-code:px-1 prose-code:py-0.5 prose-code:rounded
            prose-pre:bg-base-300 prose-pre:p-3 prose-pre:rounded-lg
            prose-blockquote:border-l-4 prose-blockquote:border-primary prose-blockquote:pl-4">
  {@html renderMarkdown(note.body)}
</div>
```

## Example Note Rendering

A note with this markdown:

```markdown
# Session Work Summary

## Features Implemented
1. **Task Annotation Display Fix** - Fixed bug where sorted tasks caused annotations to load for wrong task
2. **Markdown Rendering** - Added Glamour markdown renderer to task annotations

### Files Modified
- `internal/ui/app/model.go` - Task sorting
- `internal/ui/app/update_detail.go` - Added task-specific key bindings

### Key Decisions
- Use Eye in the Sky MCP tools for task tracking
```

Will render with:
- Proper heading hierarchy
- Bold text formatting
- Numbered lists
- Nested lists with different indentation
- Inline code with background styling

## Security

The markdown is rendered using `{@html}` in Svelte, which means:
- Content is **not sanitized** by default
- Only render trusted markdown content
- If rendering user-submitted content, consider adding DOMPurify sanitization

## Files

- **Component**: `assets/svelte/components/tabs/NotesTab.svelte`
- **Dependency**: `marked` v17.0.1 in `assets/package.json`
- **Usage**: Line 48 - `{@html renderMarkdown(note.body)}`
