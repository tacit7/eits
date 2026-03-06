---
name: skill-builder
description: Interactive guide for creating new Claude Code skills. Use when the user wants to build a new skill, create a reusable prompt template, or extend Claude's capabilities with a specialized workflow. Guides through the full creation process and saves the result both as a skill file and as an EITS prompt.
user-invocable: true
allowed-tools: Read, Glob, Grep, Write, Bash
argument-hint: [skill-name]
---

# Skill Builder

Guide the user through creating a new Claude Code skill from scratch.

## Skill Structure

```
~/.claude/skills/<skill-name>/
├── SKILL.md          (required)
├── scripts/          (optional — reusable scripts)
├── references/       (optional — docs to load as needed)
└── assets/           (optional — files used in output)
```

## SKILL.md Format

```yaml
---
name: <skill-name>
description: <what it does AND when to trigger it — this drives autocomplete matching>
user-invocable: true
allowed-tools: <comma-separated list>
argument-hint: <args hint>
---

# Instructions for Claude...
```

## Workflow

Follow these steps in order:

### 1. Understand

Ask the user what the skill should do. Get at least 2 concrete usage examples.
Ask: "What would a user type to trigger this skill?"
Stop here until usage is clear.

### 2. Plan

Decide what bundled resources would make it reusable:
- **scripts/** — code that would otherwise be rewritten each time
- **references/** — domain docs, schemas, API specs Claude should load as needed
- **assets/** — templates, boilerplate, files used in output

### 3. Create

Create the skill directory and write SKILL.md.

```bash
mkdir -p ~/.claude/skills/<skill-name>
```

Write SKILL.md with sharp frontmatter. The `description` field is the primary trigger — be specific about WHEN to use it. Body < 500 lines; move detail to `references/` files.

Add any scripts/references identified in step 2.

### 4. Register in EITS (optional)

If the user wants the skill available in DM slash autocomplete, save it as an EITS prompt:

```bash
curl -s -X POST http://localhost:4000/api/v1/prompts \
  -H "Content-Type: application/json" \
  -d '{
    "name": "<Display Name>",
    "slug": "<skill-name>",
    "description": "<same as SKILL.md description>",
    "prompt_text": "<full SKILL.md body content>"
  }'
```

Confirm success with the returned `uuid`. The prompt will appear in DM `/` autocomplete immediately.

### 5. Test and iterate

Invoke the skill (`/<skill-name>`) and refine based on real usage.

## Key Principles

- Description is the trigger — be specific and include "when to use" scenarios
- Only add context Claude doesn't already have
- Prefer concise examples over verbose explanations
- Scripts over regenerating the same code repeatedly
- Keep SKILL.md body lean; move detail to `references/` files
