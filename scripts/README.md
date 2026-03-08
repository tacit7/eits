# Eye in the Sky Claude Code Hooks

Complete hook suite for integrating Claude Code sessions with EITS tracking.

Hook scripts live in `priv/scripts/` and are referenced directly from `~/.claude/settings.json` — no copying required.

## Hook Overview

| Event | Script | Purpose |
|-------|--------|---------|
| SessionStart | `eits-session-init.sh` | Register session, inject EITS context |
| SessionStart | `eits-agent-working.sh` | Set agent status to "working" |
| SessionEnd | `eits-session-end.sh` | Mark session completed |
| Stop | `eits-session-stop.sh` | Set session status to "waiting" on interrupt |
| PreToolUse (Edit\|Write) | `eits-pre-tool-use.sh` | Enforce session name + active todo before edits |
| PreToolUse (all) | `eits-nats-tool-pre.sh` | Publish tool events to NATS (async) |
| PostToolUse | `eits-post-tool-use.sh` | Log tool results/errors after execution |
| UserPromptSubmit | `eits-prompt-submit.sh` | Update session status on each prompt (async) |
| PreCompact | `eits-pre-compact.sh` | Mark session as compacting (async) |
| SessionStart (compact) | `eits-session-compact.sh` | Handle context compaction |

## Installation

Run the install script to verify hooks and print the correct settings snippet:

```bash
./scripts/install.sh
```

This will:
- Verify all hook scripts exist in `priv/scripts/`
- Make them executable
- Print the `hooks` JSON block to add to `~/.claude/settings.json`

### Settings Configuration

Add to the `hooks` section in `~/.claude/settings.json`, replacing `/path/to/eits/web` with the absolute path to this repo:

```json
{
  "hooks": {
    "SessionStart": [
      {
        "matcher": "startup",
        "hooks": [
          {"type": "command", "command": "/path/to/eits/web/priv/scripts/eits-session-init.sh"},
          {"type": "command", "command": "/path/to/eits/web/priv/scripts/eits-agent-working.sh"}
        ]
      },
      {
        "matcher": "resume",
        "hooks": [
          {"type": "command", "command": "/path/to/eits/web/priv/scripts/eits-session-init.sh"},
          {"type": "command", "command": "/path/to/eits/web/priv/scripts/eits-agent-working.sh"}
        ]
      },
      {
        "matcher": "compact",
        "hooks": [
          {"type": "command", "command": "/path/to/eits/web/priv/scripts/eits-session-compact.sh"},
          {"type": "command", "command": "/path/to/eits/web/priv/scripts/eits-session-init.sh"},
          {"type": "command", "command": "/path/to/eits/web/priv/scripts/eits-agent-working.sh"}
        ]
      },
      {
        "matcher": "clear",
        "hooks": [
          {"type": "command", "command": "/path/to/eits/web/priv/scripts/eits-session-init.sh"},
          {"type": "command", "command": "/path/to/eits/web/priv/scripts/eits-agent-working.sh"}
        ]
      }
    ],
    "PreToolUse": [
      {
        "matcher": "Edit|Write",
        "hooks": [
          {"type": "command", "command": "/path/to/eits/web/priv/scripts/eits-pre-tool-use.sh"}
        ]
      },
      {
        "hooks": [
          {"type": "command", "command": "/path/to/eits/web/priv/scripts/eits-nats-tool-pre.sh", "async": true}
        ]
      }
    ],
    "PostToolUse": [
      {
        "hooks": [
          {"type": "command", "command": "/path/to/eits/web/priv/scripts/eits-post-tool-use.sh"}
        ]
      }
    ],
    "UserPromptSubmit": [
      {
        "hooks": [
          {"type": "command", "command": "/path/to/eits/web/priv/scripts/eits-prompt-submit.sh", "async": true}
        ]
      }
    ],
    "PreCompact": [
      {
        "hooks": [
          {"type": "command", "command": "/path/to/eits/web/priv/scripts/eits-pre-compact.sh", "async": true}
        ]
      }
    ],
    "SessionEnd": [
      {
        "hooks": [
          {"type": "command", "command": "/path/to/eits/web/priv/scripts/eits-session-end.sh"}
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          {"type": "command", "command": "/path/to/eits/web/priv/scripts/eits-session-stop.sh"}
        ]
      }
    ]
  }
}
```

## Hook Details

### SessionStart: eits-session-init.sh

**Triggers**: startup, resume

**Actions**:
- Parses `session_id` from Claude Code stdin
- Checks `session_agent_map.json` for existing registration
- Creates session via EITS if not registered
- Detects project type (Elixir/Phoenix, Node.js, Git)
- Injects EITS context into session via `hookSpecificOutput.additionalContext`
- Writes env vars to `CLAUDE_ENV_FILE` (EITS_SESSION_ID, EITS_AGENT_ID, EITS_PROJECT_ID)

**Output**: Session context with agent/session/project IDs

### SessionStart: eits-agent-working.sh

**Triggers**: startup, resume

**Actions**:
- Resolves agent_id from env var → mapping file → SQLite
- Checks current agent status
- Updates status to "working" if not already
- Skips update if already working (idempotent)

### SessionEnd: eits-session-end.sh

**Triggers**: Normal session end

**Actions**:
- Resolves agent_id from env var → stdin JSON → SQLite
- Sets agent status to "waiting"
- Marks session ended_at timestamp

### Stop: eits-session-stop.sh

**Triggers**: Ctrl+C, interrupt, cancel

**Actions**:
- Gets session_id from env var or stdin
- Updates session status to "waiting"
- Sets session ended_at timestamp
- Handles graceful shutdown without marking as "completed"

### PreToolUse: eits-pre-tool-use.sh

**Triggers**: Before every tool execution

**Actions**:
- Parses tool_name and tool_params from stdin
- Logs to actions table: `tool_use` action_type
- Updates agent last_activity_at timestamp
- Sanitizes params (max 500 chars)

### PostToolUse: eits-post-tool-use.sh

**Triggers**: After every tool execution

**Actions**:
- Parses tool_name, result, and is_error from stdin
- Logs to actions table: `tool_success` or `tool_error`
- Updates agent last_activity_at timestamp
- Captures result summary (max 200 chars)

### SessionStart (compact): eits-session-compact.sh

**Triggers**: Context compaction

**Actions**:
- Logs compaction event to debug log
- Ends old session with status "compacted"
- Removes old session from mapping file
- Allows init hook to create fresh session

## Dependencies

- `jq` - JSON parsing
- `sqlite3` - Direct database access for hooks
- EITS database at `~/.config/eye-in-the-sky/eits.db`
- EITS binary (for init hook only)

## Environment Variables

Hooks automatically set these via `CLAUDE_ENV_FILE`:
- `EITS_SESSION_ID` - Claude Code session UUID
- `EITS_AGENT_ID` - EITS agent UUID
- `EITS_PROJECT_ID` - EITS project INTEGER id

These are available to MCP tools in the same session.

## Data Flow

```
Claude Code → SessionStart hook
              ├─ eits-session-init.sh
              │  ├─ Creates session in DB
              │  ├─ Writes session_agent_map.json
              │  ├─ Sets env vars via CLAUDE_ENV_FILE
              │  └─ Injects context to Claude
              └─ eits-agent-working.sh
                 └─ Sets status to "working"

Claude Code → Tool execution
              ├─ PreToolUse → eits-pre-tool-use.sh → actions table
              ├─ Tool executes
              └─ PostToolUse → eits-post-tool-use.sh → actions table

Claude Code → Stop/SessionEnd
              ├─ Stop → eits-session-stop.sh → status: "waiting"
              └─ SessionEnd → eits-session-end.sh → status: "waiting"
```

## Troubleshooting

**Hooks not firing:**
- Check `~/.claude/settings.json` hook configuration
- Verify hook scripts are executable: `chmod +x ~/.claude/hooks/eits-*.sh`
- Check hook logs: `~/.config/eye-in-the-sky/*.log`

**Missing agent_id:**
- Verify SessionStart hooks ran successfully
- Check `~/.claude/hooks/session_agent_map.json`
- Check env vars: `echo $EITS_AGENT_ID`

**Database errors:**
- Verify EITS database exists: `ls ~/.config/eye-in-the-sky/eits.db`
- Check schema is initialized: `sqlite3 ~/.config/eye-in-the-sky/eits.db ".tables"`

## Migration from TypeScript

Old hooks referenced `core-ts/build/index.js`. New hooks use:
- Direct SQLite access for status updates
- MCP tools are called from Claude, not hooks
- Hooks only track lifecycle events, not business logic
