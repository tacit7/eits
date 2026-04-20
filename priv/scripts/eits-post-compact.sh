#!/usr/bin/env bash
# Hook: Save compact_summary to ~/.claude/compact-summaries/ after compaction (PostCompact)
set -uo pipefail

[ "${EITS_WORKFLOW:-}" = "0" ] && exit 0

. "$(cd "$(dirname "$0")" && pwd)/eits-lib.sh"

input_json=$(timeout 2 cat 2>/dev/null) || exit 0
[ -z "$input_json" ] && exit 0

out_dir="$HOME/.claude/compact-summaries"
mkdir -p "$out_dir" || exit 0

sid=$(printf %s "$input_json" | jq -r '.session_id // "unknown"' 2>/dev/null)
[ -z "$sid" ] && sid=unknown
ts=$(date +%Y%m%d-%H%M%S)

body=$(printf %s "$input_json" | jq -r '"# Compact Summary\n\n- Session: \(.session_id)\n- Trigger: \(.trigger)\n- CWD: \(.cwd)\n\n---\n\n\(.compact_summary)"' 2>/dev/null)

printf %s "$body" > "$out_dir/${ts}-${sid}.md" 2>/dev/null || true

# Save to EITS DB as session context (uses EITS_SESSION_UUID from env, falls back to hook payload)
target_uuid="${EITS_SESSION_UUID:-$sid}"
if [ -n "$target_uuid" ] && [ "$target_uuid" != "unknown" ]; then
  trigger=$(printf %s "$input_json" | jq -r '.trigger // "unknown"' 2>/dev/null)
  cwd_val=$(printf %s "$input_json" | jq -r '.cwd // ""' 2>/dev/null)
  metadata=$(jq -n --arg src "post-compact" --arg trig "$trigger" --arg cwd "$cwd_val" --arg ts "$ts" \
    '{source: $src, trigger: $trig, cwd: $cwd, compacted_at: $ts}')
  printf %s "$body" | eits sessions context "$target_uuid" --from-stdin --metadata "$metadata" >/dev/null 2>&1 || true
fi

exit 0
