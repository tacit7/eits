---
name: track-hookify-changes
enabled: true
event: file
conditions:
  - field: file_path
    operator: regex_match
    pattern: \.claude/hookify\.[^/]+\.local\.md$
action: warn
---

**Hookify rule file created or modified.**

Log it to EITS so it's tracked:

```bash
i-hooks log --name "<rule-name>" --event "<bash|file|stop|prompt>" --action "<warn|block>" \
  --description "What this rule prevents and why"
```

Or annotate an existing task if this rule belongs to one:

```bash
i-hooks annotate <task_id> --body "Added hookify rule: <name> — <reason>"
```

Run `i-hooks list` to see all active rules.
