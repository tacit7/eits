# Markdown Formatting Test

This file demonstrates the markdown rendering capabilities in the DM interface.

## Text Formatting

This is **bold text** and this is *italic text*. You can also use ~~strikethrough~~ if needed.

## Code

Inline code looks like this: `const greeting = "Hello World"`

Here's a code block with syntax highlighting:

```javascript
function fibonacci(n) {
  if (n <= 1) return n;
  return fibonacci(n - 1) + fibonacci(n - 2);
}

console.log(fibonacci(10)); // 55
```

```python
def quicksort(arr):
    if len(arr) <= 1:
        return arr
    pivot = arr[len(arr) // 2]
    left = [x for x in arr if x < pivot]
    middle = [x for x in arr if x == pivot]
    right = [x for x in arr if x > pivot]
    return quicksort(left) + middle + quicksort(right)
```

## Lists

Unordered list:
- First item
- Second item
- Third item with **bold**
  - Nested item
  - Another nested item

Ordered list:
1. Step one
2. Step two
3. Step three

## Blockquotes

> This is a blockquote. It can span multiple lines and contain **formatted text** and `inline code`.
>
> It can also have multiple paragraphs.

## Links

Check out [Anthropic](https://anthropic.com) for more information.

## Tables

| Language   | Type       | Year |
|------------|------------|------|
| JavaScript | Interpreted| 1995 |
| Python     | Interpreted| 1991 |
| Rust       | Compiled   | 2015 |

## Horizontal Rule

---

## Mixed Content

Here's a real example combining everything:

The `renderMarkdown()` function in **marked.js** uses the following configuration:

```javascript
marked.use(
  markedHighlight({
    langPrefix: 'hljs language-',
    highlight(code, lang) {
      return hljs.highlight(code, { language: lang }).value;
    }
  })
);
```

Key features:
- Syntax highlighting via `highlight.js`
- GitHub Flavored Markdown support
- Line breaks preserved with `breaks: true`

> **Note**: The implementation requires the `marked-highlight` extension for compatibility with marked v17+.
