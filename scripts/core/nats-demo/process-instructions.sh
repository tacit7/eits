#!/bin/bash
# Processes new instructions and tracks what's been handled

INSTRUCTION_FILE="/tmp/agent-instructions.log"
PROCESSED_FILE="/tmp/agent-instructions-processed.log"

# Create processed file if it doesn't exist
touch "$PROCESSED_FILE"

# Get new instructions (not yet processed)
NEW_INSTRUCTIONS=$(comm -23 \
  <(sort "$INSTRUCTION_FILE") \
  <(sort "$PROCESSED_FILE"))

if [ -z "$NEW_INSTRUCTIONS" ]; then
  echo "No new instructions to process"
  exit 0
fi

echo "New instructions to process:"
echo "$NEW_INSTRUCTIONS"
echo ""

# Mark as processed
echo "$NEW_INSTRUCTIONS" >> "$PROCESSED_FILE"

# Return just the instruction text for Claude to execute
echo "$NEW_INSTRUCTIONS" | awk -F'INSTR=' '{print $2}'
