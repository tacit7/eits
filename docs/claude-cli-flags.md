# Claude Code CLI Flags Reference

## Overview

Claude Code (`claude`) is a terminal-based AI coding assistant. It runs interactively by default, or non-interactively with `-p`/`--print` for piping and scripting.

```bash
claude [options] [command] [prompt]
```

When invoked without arguments, it starts an interactive REPL session. With `-p`, it prints a response and exits, making it suitable for shell pipelines, hooks, and automation.

## Maintenance & Operational Flags

These are the flags you care about most for ops, automation, and agent management.

| Flag | What it does |
|------|-------------|
| `--no-session-persistence` | Session is not saved to disk and cannot be resumed. Use for ephemeral/automated runs. Only works with `--print`. |
| `--dangerously-skip-permissions` | Bypasses ALL permission checks. Only use in sandboxed environments with no internet. |
| `--allow-dangerously-skip-permissions` | Makes `--dangerously-skip-permissions` available as an option without enabling it by default. |
| `--permission-mode <mode>` | Controls permission behavior. Choices: `default`, `acceptEdits`, `bypassPermissions`, `dontAsk`, `plan`, `auto`. |
| `-d, --debug [filter]` | Debug mode with optional category filter (e.g., `"api,hooks"` or `"!1p,!file"`). |
| `--debug-file <path>` | Write debug logs to a file. Implicitly enables debug mode. |
| `--verbose` | Override verbose mode setting from config. |
| `--max-budget-usd <amount>` | Cap spend on API calls. Only works with `--print`. |
| `--model <model>` | Override model. Accepts aliases (`sonnet`, `opus`) or full IDs (`claude-sonnet-4-6`). |
| `--fallback-model <model>` | Auto-fallback when primary model is overloaded. Only works with `--print`. |
| `--effort <level>` | Reasoning effort: `low`, `medium`, `high`, `max`. |

## Full Flag Reference

All flags listed alphabetically.

### `--add-dir <directories...>`
Additional directories to allow tool access to beyond the working directory.
```bash
claude --add-dir /path/to/shared-lib /path/to/config
```

### `--agent <agent>`
Agent for the current session. Overrides the `agent` setting in config.
```bash
claude --agent reviewer
```

### `--agents <json>`
JSON object defining custom agents inline.
```bash
claude --agents '{"reviewer": {"description": "Reviews code", "prompt": "You are a code reviewer"}}'
```

### `--allow-dangerously-skip-permissions`
Enable the dangerous skip permissions flag as an option without it being the default. For sandbox setups only.

### `--allowedTools, --allowed-tools <tools...>`
Comma or space-separated list of tools to allow.
```bash
claude --allowed-tools "Bash(git:*) Edit Read"
```

### `--append-system-prompt <prompt>`
Append text to the default system prompt (does not replace it).
```bash
claude --append-system-prompt "Always write tests for new functions"
```

### `--betas <betas...>`
Beta headers for API requests. API key users only.

### `--brief`
Enable `SendUserMessage` tool for agent-to-user communication.

### `--chrome`
Enable Claude in Chrome integration.

### `-c, --continue`
Continue the most recent conversation in the current directory.
```bash
claude --continue
```

### `-d, --debug [filter]`
Enable debug mode. Optionally filter by category.
```bash
claude --debug              # all debug output
claude --debug "api,hooks"  # only api and hooks
claude --debug "!1p,!file"  # exclude 1p and file categories
```

### `--debug-file <path>`
Write debug logs to a specific file. Implicitly enables debug.
```bash
claude --debug-file /tmp/claude-debug.log -p "fix the bug"
```

### `--disable-slash-commands`
Disable all skills/slash commands for the session.

### `--disallowedTools, --disallowed-tools <tools...>`
Comma or space-separated list of tools to deny.
```bash
claude --disallowed-tools "Bash(rm:*)"
```

### `--effort <level>`
Set reasoning effort level. Choices: `low`, `medium`, `high`, `max`.
```bash
claude --effort max -p "refactor this module"
```

### `--fallback-model <model>`
Automatic fallback model when the primary is overloaded. Only works with `--print`.
```bash
claude --model opus --fallback-model sonnet -p "explain this code"
```

### `--file <specs...>`
Download file resources at startup. Format: `file_id:relative_path`.
```bash
claude --file file_abc:doc.txt file_def:img.png
```

### `--fork-session`
When resuming, create a new session ID instead of reusing the original. Use with `--resume` or `--continue`.
```bash
claude --continue --fork-session
```

### `--from-pr [value]`
Resume a session linked to a PR by number/URL, or open interactive picker.
```bash
claude --from-pr 42
claude --from-pr "https://github.com/org/repo/pull/42"
```

### `-h, --help`
Display help.

### `--ide`
Auto-connect to IDE on startup if exactly one valid IDE is available.

### `--include-partial-messages`
Include partial message chunks as they arrive. Only works with `--print` and `--output-format=stream-json`.

### `--input-format <format>`
Input format for `--print` mode. Choices: `text` (default), `stream-json`.
```bash
echo '{"type":"user","content":"hello"}' | claude -p --input-format stream-json
```

### `--json-schema <schema>`
JSON Schema for structured output validation.
```bash
claude -p --json-schema '{"type":"object","properties":{"name":{"type":"string"}},"required":["name"]}' "Extract the name"
```

### `--max-budget-usd <amount>`
Maximum dollar amount to spend. Only works with `--print`.
```bash
claude --max-budget-usd 0.50 -p "quick question"
```

### `--mcp-config <configs...>`
Load MCP servers from JSON files or strings.
```bash
claude --mcp-config /path/to/mcp-servers.json
```

### `--mcp-debug`
**DEPRECATED.** Use `--debug` instead.

### `--model <model>`
Override the model for this session.
```bash
claude --model opus -p "complex analysis"
claude --model claude-sonnet-4-6 -p "quick task"
```

### `--no-chrome`
Disable Claude in Chrome integration.

### `--no-session-persistence`
Sessions are not saved to disk and cannot be resumed. Only works with `--print`.
```bash
claude --no-session-persistence -p "one-off question"
```

### `--output-format <format>`
Output format for `--print` mode. Choices: `text` (default), `json`, `stream-json`.
```bash
claude -p --output-format json "what is 2+2"
claude -p --output-format stream-json "explain this"
```

### `--permission-mode <mode>`
Permission mode for the session. Choices: `default`, `acceptEdits`, `bypassPermissions`, `dontAsk`, `plan`, `auto`.
```bash
claude --permission-mode plan -p "plan the refactor"
claude --permission-mode auto -p "fix all lint errors"
```

### `--plugin-dir <paths...>`
Load plugins from directories for this session only.
```bash
claude --plugin-dir ./my-plugins
```

### `-p, --print`
Print response and exit. Skips workspace trust dialog. Use in directories you trust.
```bash
echo "explain this error" | claude -p
claude -p "what does this function do"
```

### `--replay-user-messages`
Re-emit user messages from stdin on stdout. Only works with `--input-format=stream-json` and `--output-format=stream-json`.

### `-r, --resume [value]`
Resume a conversation by session ID, or open interactive picker with optional search term.
```bash
claude --resume abc-123-def
claude --resume "refactor"  # search term for picker
```

### `--session-id <uuid>`
Use a specific session ID (must be valid UUID).
```bash
claude --session-id "550e8400-e29b-41d4-a716-446655440000"
```

### `--setting-sources <sources>`
Comma-separated list of setting sources to load. Options: `user`, `project`, `local`.
```bash
claude --setting-sources "user,project"
```

### `--settings <file-or-json>`
Path to a settings JSON file or inline JSON string.
```bash
claude --settings /path/to/settings.json
claude --settings '{"model": "opus"}'
```

### `--strict-mcp-config`
Only use MCP servers from `--mcp-config`, ignoring all other MCP configurations.

### `--system-prompt <prompt>`
Replace the entire system prompt for the session.
```bash
claude --system-prompt "You are a code reviewer. Only review, never edit." -p "review main.py"
```

### `--tmux`
Create a tmux session for the worktree. Requires `--worktree`. Uses iTerm2 native panes when available; use `--tmux=classic` for traditional tmux.

### `--tools <tools...>`
Specify available tools from the built-in set.
```bash
claude --tools "Bash,Edit,Read"  # only these tools
claude --tools ""                 # disable all tools
claude --tools "default"          # all tools (default)
```

### `--verbose`
Override verbose mode setting from config.

### `-v, --version`
Print version number.

### `-w, --worktree [name]`
Create a new git worktree for this session.
```bash
claude --worktree feature-branch
```

## Common Recipes

### Non-interactive pipe mode (hooks, CI)
```bash
# Basic one-shot question
claude -p "summarize this diff" < diff.txt

# With budget cap and no persistence
claude -p --no-session-persistence --max-budget-usd 1.00 "review this PR"

# JSON output for parsing
claude -p --output-format json "extract function names from main.py"
```

### Fully autonomous agent (sandboxed only)
```bash
claude --dangerously-skip-permissions -p "fix all failing tests"
```

### Debug a failing session
```bash
# Debug everything to a file
claude --debug-file /tmp/claude-debug.log --continue

# Debug only API calls
claude --debug "api" --continue
```

### Restricted tool access
```bash
# Read-only mode: no edits, no bash
claude --tools "Read,Glob,Grep" -p "explain the auth flow"

# Allow git but nothing else in bash
claude --allowed-tools "Bash(git:*) Read Glob Grep" -p "show recent commits"
```

### Agent spawning with custom model
```bash
# Use opus for heavy analysis
claude --model opus --effort max -p "refactor the entire auth module"

# Fast model with fallback
claude --model sonnet --fallback-model haiku -p "quick lint fix"
```

### Continue or resume sessions
```bash
# Continue last session in this directory
claude --continue

# Resume and fork (new session ID, same history)
claude --continue --fork-session

# Resume a specific session
claude --resume "session-uuid-here"
```

### Custom MCP servers for a session
```bash
# Load additional MCP servers
claude --mcp-config ./my-mcp-servers.json

# Strict mode: only use specified MCP servers
claude --strict-mcp-config --mcp-config ./my-mcp-servers.json
```

### Structured output
```bash
claude -p --json-schema '{"type":"object","properties":{"files":{"type":"array","items":{"type":"string"}},"summary":{"type":"string"}},"required":["files","summary"]}' "list modified files and summarize changes"
```

## Config File vs CLI Flags

Settings can come from `~/.claude/settings.json` (user), `.claude/settings.json` (project), or `.claude/settings.local.json` (local). CLI flags override config file values.

| Setting | Config file | CLI flag | Notes |
|---------|:-----------:|:--------:|-------|
| Model | Yes | `--model` | CLI overrides config |
| Permission mode | Yes | `--permission-mode` | CLI overrides config |
| Allowed tools | Yes | `--allowed-tools` | CLI overrides config |
| Disallowed tools | Yes | `--disallowed-tools` | CLI overrides config |
| MCP servers | Yes | `--mcp-config` | CLI can add or replace (with `--strict-mcp-config`) |
| Verbose | Yes | `--verbose` | CLI overrides config |
| Agent definitions | Yes | `--agents` | CLI overrides config |
| System prompt | No | `--system-prompt` | CLI only |
| Append system prompt | No | `--append-system-prompt` | CLI only |
| Debug | No | `--debug` | CLI only |
| Max budget | No | `--max-budget-usd` | CLI only |
| Session persistence | No | `--no-session-persistence` | CLI only |
| Output format | No | `--output-format` | CLI only |
| Effort level | Yes | `--effort` | CLI overrides config |

### Config file location

```
~/.claude/settings.json          # User-level (global)
<project>/.claude/settings.json  # Project-level (checked into repo)
<project>/.claude/settings.local.json  # Local overrides (gitignored)
```

Use `--setting-sources` to control which sources are loaded:
```bash
claude --setting-sources "user"           # only user settings
claude --setting-sources "user,project"   # skip local overrides
```
