#!/bin/bash
# Automatically monitors instruction queue and executes new instructions

INSTRUCTION_FILE="/tmp/agent-instructions.log"
PROCESSED_FILE="/tmp/agent-instructions-processed.log"
EXECUTION_LOG="/tmp/auto-executor.log"

echo "🤖 Auto-Executor Started (PID: $$)" | tee -a "$EXECUTION_LOG"
echo "Monitoring: $INSTRUCTION_FILE" | tee -a "$EXECUTION_LOG"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" | tee -a "$EXECUTION_LOG"

# Create processed file if it doesn't exist
touch "$PROCESSED_FILE"

LAST_LINE_COUNT=0

while true; do
    if [ -f "$INSTRUCTION_FILE" ]; then
        CURRENT_COUNT=$(wc -l < "$INSTRUCTION_FILE")

        if [ "$CURRENT_COUNT" -gt "$LAST_LINE_COUNT" ]; then
            # Get new instructions only
            NEW_LINES=$((CURRENT_COUNT - LAST_LINE_COUNT))
            NEW_INSTRUCTIONS=$(tail -n "$NEW_LINES" "$INSTRUCTION_FILE")

            echo "" | tee -a "$EXECUTION_LOG"
            echo "🔔 NEW INSTRUCTION(S) RECEIVED!" | tee -a "$EXECUTION_LOG"
            echo "$(date '+%Y-%m-%d %H:%M:%S')" | tee -a "$EXECUTION_LOG"
            echo "$NEW_INSTRUCTIONS" | tee -a "$EXECUTION_LOG"
            echo "" | tee -a "$EXECUTION_LOG"

            # Extract just the instruction text
            while IFS= read -r line; do
                INSTRUCTION=$(echo "$line" | awk -F'INSTR=' '{print $2}')
                SENDER=$(echo "$line" | awk -F'FROM=' '{print $2}' | awk '{print $1}')

                echo "📝 Executing: $INSTRUCTION" | tee -a "$EXECUTION_LOG"
                echo "   From: $SENDER" | tee -a "$EXECUTION_LOG"

                # Mark as processed
                echo "$line" >> "$PROCESSED_FILE"

                # TODO: Here you could trigger actual execution
                # For now, just log it
                echo "   ✅ Logged for processing" | tee -a "$EXECUTION_LOG"
                echo "" | tee -a "$EXECUTION_LOG"
            done <<< "$NEW_INSTRUCTIONS"

            LAST_LINE_COUNT=$CURRENT_COUNT
        fi
    fi

    sleep 2
done
