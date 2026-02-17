#!/usr/bin/env bash
# Install EITS Claude Code hooks to ~/.claude/hooks/
# Run this script after updating hooks to deploy them globally

set -e

HOOKS_DIR="$HOME/.claude/hooks"
SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SETTINGS_FILE="$HOME/.claude/settings.json"
SETTINGS_TEMPLATE="$SCRIPTS_DIR/settings.json"

echo "==> Installing EITS Claude Code hooks"

# Create hooks directory if it doesn't exist
mkdir -p "$HOOKS_DIR"

# Copy all hook scripts
echo "Copying hook scripts to $HOOKS_DIR..."
for hook in "$SCRIPTS_DIR"/eits-*.sh; do
    if [ -f "$hook" ]; then
        cp "$hook" "$HOOKS_DIR/"
        chmod +x "$HOOKS_DIR/$(basename "$hook")"
        echo "  ✓ $(basename "$hook")"
    fi
done

echo ""
echo "==> Hook installation complete!"
echo ""
echo "Next steps:"
echo "1. Merge the hook configuration into ~/.claude/settings.json"
echo "   Template available at: $SETTINGS_TEMPLATE"
echo ""
echo "2. Or manually add the hooks section from settings.json to your ~/.claude/settings.json"
echo ""
echo "Installed hooks:"
echo "  - eits-session-init.sh (SessionStart)"
echo "  - eits-agent-working.sh (SessionStart)"
echo "  - eits-session-end.sh (SessionEnd)"
echo "  - eits-session-stop.sh (Stop)"
echo "  - eits-session-compact.sh (SessionStart compact)"
echo "  - eits-pre-tool-use.sh (PreToolUse)"
echo "  - eits-post-tool-use.sh (PostToolUse)"
echo ""
echo "Database: ~/.config/eye-in-the-sky/eits.db"
echo "Mapping file: ~/.claude/hooks/session_agent_map.json"
echo ""
