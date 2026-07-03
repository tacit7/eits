#!/usr/bin/env bash
# Configure EITS Claude Code hooks in ~/.claude/settings.json
# Hook scripts live in priv/scripts/ — no copying needed.
# Run this script to generate the settings.json snippet with the correct paths.

set -e

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOKS_DIR="$REPO_DIR/priv/scripts"
SETTINGS_FILE="$HOME/.claude/settings.json"

echo "==> EITS Hook Configuration"
echo ""
echo "Hook scripts location: $HOOKS_DIR"
echo ""

# Verify hooks exist and are executable
for hook in eits-session-startup.sh eits-session-resume.sh eits-session-compact.sh eits-session-end.sh eits-session-stop.sh eits-pre-tool-use.sh eits-post-tool-commit.sh eits-prompt-submit.sh eits-pre-compact.sh; do
    if [ -f "$HOOKS_DIR/$hook" ]; then
        chmod +x "$HOOKS_DIR/$hook"
        echo "  ✓ $hook"
    else
        echo "  ✗ MISSING: $hook" >&2
    fi
done

echo ""
echo "==> Add the following hooks section to $SETTINGS_FILE"
echo ""
cat <<EOF
{
  "hooks": {
    "SessionStart": [
      {
        "matcher": "startup",
        "hooks": [
          {"type": "command", "command": "$HOOKS_DIR/eits-session-startup.sh"}
        ]
      },
      {
        "matcher": "resume",
        "hooks": [
          {"type": "command", "command": "$HOOKS_DIR/eits-session-resume.sh"}
        ]
      },
      {
        "matcher": "compact",
        "hooks": [
          {"type": "command", "command": "$HOOKS_DIR/eits-session-compact.sh"}
        ]
      },
      {
        "matcher": "clear",
        "hooks": [
          {"type": "command", "command": "$HOOKS_DIR/eits-session-startup.sh"}
        ]
      }
    ],
    "PreToolUse": [
      {
        "matcher": "Edit|Write",
        "hooks": [
          {"type": "command", "command": "$HOOKS_DIR/eits-pre-tool-use.sh"}
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {"type": "command", "command": "$HOOKS_DIR/eits-post-tool-commit.sh"}
        ]
      }
    ],
    "UserPromptSubmit": [
      {
        "hooks": [
          {"type": "command", "command": "$HOOKS_DIR/eits-prompt-submit.sh", "async": true}
        ]
      }
    ],
    "PreCompact": [
      {
        "hooks": [
          {"type": "command", "command": "$HOOKS_DIR/eits-pre-compact.sh", "async": true}
        ]
      }
    ],
    "SessionEnd": [
      {
        "hooks": [
          {"type": "command", "command": "$HOOKS_DIR/eits-session-end.sh"}
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          {"type": "command", "command": "$HOOKS_DIR/eits-session-stop.sh"}
        ]
      }
    ]
  }
}
EOF

echo ""
