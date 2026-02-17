#!/bin/bash
# Watches instruction queue and notifies when new instructions arrive

INSTRUCTION_FILE="/tmp/agent-instructions.log"
LAST_LINE_COUNT=0

echo "📡 Watching for new instructions..."
echo "File: $INSTRUCTION_FILE"
echo ""

while true; do
    if [ -f "$INSTRUCTION_FILE" ]; then
        CURRENT_COUNT=$(wc -l < "$INSTRUCTION_FILE")

        if [ "$CURRENT_COUNT" -gt "$LAST_LINE_COUNT" ]; then
            NEW_LINES=$((CURRENT_COUNT - LAST_LINE_COUNT))
            echo ""
            echo "🔔 NEW INSTRUCTION(S) RECEIVED! ($NEW_LINES new)"
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            tail -n "$NEW_LINES" "$INSTRUCTION_FILE"
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            echo ""
            echo "💡 Tell Claude: 'process new instructions'"

            LAST_LINE_COUNT=$CURRENT_COUNT
        fi
    fi

    sleep 2
done
