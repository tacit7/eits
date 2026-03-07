#!/usr/bin/env bash
# Publish agent status event to NATS
# Args: $1 = agent_id, $2 = status
set -euo pipefail

agent_id="${1:-}"
status="${2:-}"

[ -z "$agent_id" ] || [ -z "$status" ] && exit 0

nats pub "events.agent.status" "$(jq -nc \
  --arg agent_id "$agent_id" \
  --arg status "$status" \
  '{agent_id: $agent_id, status: $status}')" 2>/dev/null &
