---
name: warn-commit-without-compile
enabled: true
event: bash
pattern: git\s+commit
action: warn
---

**Committing without verifying compilation.**

Run this first:

```bash
mix compile --warnings-as-errors
```

Only warnings are acceptable. Errors must be fixed before committing.
