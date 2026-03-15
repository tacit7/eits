---
name: require-task-update
enabled: true
event: stop
pattern: .*
action: warn
---

Before stopping, update your tasks in Eye in the Sky.

```bash
eits tasks list --session $EITS_SESSION_UUID
eits tasks update <task_id> --state 4   # In Review
eits tasks done <task_id>               # Done
eits tasks annotate <task_id> --body "What was done"
```

Mark tasks done, in-review, or annotate with findings before ending the session.
