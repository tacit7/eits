---
name: block-anthropic-attribution
enabled: true
event: bash
pattern: Generated with Claude|Co-Authored-By.*[Aa]nthropic|noreply@anthropic\.com
action: block
---

**Anthropic attribution detected in commit.**

Your rules say: remove all Anthropic attribution and co-author tags.

- No "Generated with Claude Code" footers
- No `Co-Authored-By: Claude` lines
- Keep commit messages clean and focused on the work

Remove the attribution before committing.
