#!/usr/bin/env bash
# Publish domain-specific event to NATS
# Args: $1 = event_type (commits|notes|todo|session.context), $2 = payload (JSON)
set -euo pipefail

event_type="${1:-}"
payload="${2:-{}}"

[ -z "$event_type" ] && exit 0

# Validate JSON before publishing — drop malformed payloads silently
echo "$payload" | jq -e . > /dev/null 2>&1 || exit 0

nats pub "events.$event_type" "$payload" 2>/dev/null &
