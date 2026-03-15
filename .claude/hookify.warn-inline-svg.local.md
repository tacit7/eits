---
name: warn-inline-svg
enabled: true
event: file
pattern: <svg\s[^>]*viewBox
action: warn
---

**Inline SVG detected.**

Use the Phoenix `<.icon>` component instead:

```heex
<!-- GOOD -->
<.icon name="hero-folder" class="w-4 h-4" />
<.icon name="hero-document-text" class="w-4 h-4" />

<!-- BAD -->
<svg class="w-4 h-4" fill="none" viewBox="0 0 24 24" ...>
  <path ... />
</svg>
```

Never use inline SVG paths. Always use Heroicons via `<.icon name="hero-*">`.
