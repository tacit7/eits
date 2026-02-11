---
name: check-docs
description: Look up documentation for a topic in the global docs project
user-invocable: true
allowed-tools: Read, Glob, Grep
argument-hint: <topic>
---

Go to ~/projects/docs, read the README.md, and find documentation related to $ARGUMENTS.
If the README references other files for that topic, read those too.
Report back what you find.
