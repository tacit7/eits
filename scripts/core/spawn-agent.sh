#!/usr/bin/env bash
# spawn-agent.sh - Spawn a new Claude Code agent with Eye in the Sky integration
#
# Usage:
#   ./spawn-agent.sh "your task instructions here"
#   ./spawn-agent.sh --model haiku "quick task"
#   ./spawn-agent.sh --project-path /path/to/project "task"

set -euo pipefail

# Default options
MODEL="haiku"
PROJECT_PATH="$(pwd)"
SKIP_PERMISSIONS="--dangerously-skip-permissions"

# Parse arguments
POSITIONAL_ARGS=()
while [[ $# -gt 0 ]]; do
  case $1 in
    --model)
      MODEL="$2"
      shift 2
      ;;
    --project-path)
      PROJECT_PATH="$2"
      shift 2
      ;;
    --safe)
      SKIP_PERMISSIONS=""
      shift
      ;;
    --help)
      echo "Usage: spawn-agent.sh [OPTIONS] \"task instructions\""
      echo ""
      echo "Options:"
      echo "  --model MODEL          Model to use (sonnet, opus, haiku). Default: sonnet"
      echo "  --project-path PATH    Working directory. Default: current directory"
      echo "  --safe                 Don't skip permission prompts"
      echo "  --help                 Show this help message"
      echo ""
      echo "Examples:"
      echo "  spawn-agent.sh \"Send hi via NATS\""
      echo "  spawn-agent.sh --model haiku \"Quick test\""
      exit 0
      ;;
    *)
      POSITIONAL_ARGS+=("$1")
      shift
      ;;
  esac
done

# Restore positional arguments
set -- "${POSITIONAL_ARGS[@]}"

if [[ $# -eq 0 ]]; then
  echo "Error: Task instructions required" >&2
  echo "Usage: spawn-agent.sh \"task instructions\"" >&2
  exit 1
fi

INSTRUCTIONS="$1"

# Generate UUIDs (macOS has uuidgen, Linux may need other tools)
if command -v uuidgen &> /dev/null; then
  SESSION_ID=$(uuidgen | tr '[:upper:]' '[:lower:]')
  AGENT_ID=$(uuidgen | tr '[:upper:]' '[:lower:]')
elif command -v uuid &> /dev/null; then
  SESSION_ID=$(uuid -v4)
  AGENT_ID=$(uuid -v4)
else
  echo "Error: No UUID generator found (uuidgen or uuid)" >&2
  exit 1
fi

# Get project name from path
PROJECT_NAME=$(basename "$PROJECT_PATH")

# Build initialization prompt
read -r -d '' INIT_PROMPT <<EOF || true
INITIALIZATION - Spawned Agent Context:

Session ID: ${SESSION_ID}
Agent ID: ${AGENT_ID}
Project: ${PROJECT_NAME}

CRITICAL FIRST STEP: Call i-start-session MCP tool to register with Eye in the Sky:

i-start-session({
  "session_id": "${SESSION_ID}",
  "description": "${INSTRUCTIONS}",
  "agent_description": "Spawned agent",
  "project_name": "${PROJECT_NAME}",
  "worktree_path": "${PROJECT_PATH}"
})

YOUR TASK: ${INSTRUCTIONS}

After completing the task, call i-end-session to mark your work complete.
EOF

# Build command
DESCRIPTION="session-id ${SESSION_ID} agent-id ${AGENT_ID}"

# Find claude binary
if ! CLAUDE_BIN=$(command -v claude); then
  echo "Error: claude binary not found in PATH" >&2
  exit 1
fi

# Log what we're doing
echo "🚀 Spawning Claude Code Agent"
echo "   Session ID: ${SESSION_ID}"
echo "   Agent ID: ${AGENT_ID}"
echo "   Model: ${MODEL}"
echo "   Project: ${PROJECT_PATH}"
echo "   Task: ${INSTRUCTIONS}"
echo ""

# Save command to file for debugging
COMMAND_FILE="/tmp/claude_spawn_${SESSION_ID}.sh"
cat > "$COMMAND_FILE" <<CMDEOF
#!/usr/bin/env bash
cd "${PROJECT_PATH}" && \\
${CLAUDE_BIN} ${SKIP_PERMISSIONS} \\
  --session-id "${SESSION_ID}" \\
  "${DESCRIPTION}" \\
  -p "${INIT_PROMPT}" \\
  --model "${MODEL}" \\
  --output-format stream-json \\
  --verbose
CMDEOF

chmod +x "$COMMAND_FILE"
echo "📝 Command saved to: ${COMMAND_FILE}"
echo ""

# Execute
cd "$PROJECT_PATH"
exec "${CLAUDE_BIN}" ${SKIP_PERMISSIONS} \
  --session-id "${SESSION_ID}" \
  "${DESCRIPTION}" \
  -p "${INIT_PROMPT}" \
  --model "${MODEL}" \
  --output-format stream-json \
  --verbose
