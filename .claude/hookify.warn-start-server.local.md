---
name: warn-start-server
enabled: true
event: bash
pattern: mix\s+phx\.server
action: warn
---

**About to start the Phoenix dev server.**

Rule: don't run servers unless explicitly asked by the user.

If the user asked for it, proceed. Otherwise, stop.
