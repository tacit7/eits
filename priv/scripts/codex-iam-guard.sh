#!/usr/bin/env bash
# Codex IAM hook wrapper.
#
# The IAM endpoint returns Claude Code hook JSON. This adapter preserves denies
# and advisory context, while suppressing Claude-only allow/fail-open fields that
# Codex may treat as unsupported hook output.
set -uo pipefail

[ "${EITS_WORKFLOW:-}" = "0" ] && exit 0

EITS_BASE="${EITS_URL:-http://localhost:5001/api/v1}"
DECIDE_URL="${EITS_BASE}/iam/decide"
CURL_TIMEOUT=3

fail_open() {
  local msg="${1:-}"
  [ -n "$msg" ] && echo "[codex-iam-guard] fail-open: $msg" >&2
  exit 0
}

command -v curl >/dev/null 2>&1 || fail_open "curl not found"
command -v jq >/dev/null 2>&1 || fail_open "jq not found"

PAYLOAD_FILE=$(mktemp /tmp/codex-iam-payload.XXXXXX)
BODY_FILE=$(mktemp /tmp/codex-iam-body.XXXXXX)
trap 'rm -f "$PAYLOAD_FILE" "$BODY_FILE"' EXIT

timeout 5 cat > "$PAYLOAD_FILE" 2>/dev/null || fail_open "stdin read timed out"
[ -s "$PAYLOAD_FILE" ] || fail_open "empty stdin payload"
jq -e . < "$PAYLOAD_FILE" >/dev/null 2>&1 || fail_open "payload is not valid JSON"

hook_event_name=$(jq -r '.hook_event_name // empty' < "$PAYLOAD_FILE" 2>/dev/null || echo "")
[ -n "$hook_event_name" ] || fail_open "payload has no hook_event_name"

http_code=$(
  curl \
    --silent \
    --show-error \
    --max-time "$CURL_TIMEOUT" \
    --connect-timeout 2 \
    --output "$BODY_FILE" \
    --write-out '%{http_code}' \
    --header 'Content-Type: application/json' \
    --data "@$PAYLOAD_FILE" \
    "$DECIDE_URL" 2>&1
) || fail_open "curl failed"

case "$http_code" in
  2*) jq -e . < "$BODY_FILE" >/dev/null 2>&1 || fail_open "endpoint returned non-JSON body" ;;
  *) fail_open "endpoint returned HTTP $http_code" ;;
esac

case "$hook_event_name" in
  PreToolUse)
    jq -c '
      if .hookSpecificOutput.permissionDecision == "deny" then
        {
          hookSpecificOutput: {
            hookEventName: "PreToolUse",
            permissionDecision: "deny",
            permissionDecisionReason: (.hookSpecificOutput.permissionDecisionReason // "Denied by IAM policy")
          }
        }
      elif (.hookSpecificOutput.additionalContext // "") != "" then
        {
          hookSpecificOutput: {
            hookEventName: "PreToolUse",
            additionalContext: .hookSpecificOutput.additionalContext
          }
        }
      else
        empty
      end
    ' "$BODY_FILE"
    ;;
  PostToolUse)
    jq -c '
      if .continue == false then
        {
          decision: "block",
          reason: (.stopReason // "Denied by IAM policy")
        }
      elif (.hookSpecificOutput.additionalContext // "") != "" then
        {
          hookSpecificOutput: {
            hookEventName: "PostToolUse",
            additionalContext: .hookSpecificOutput.additionalContext
          }
        }
      else
        empty
      end
    ' "$BODY_FILE"
    ;;
  Stop)
    jq -c '
      if .continue == false then
        {
          decision: "block",
          reason: (.stopReason // "Denied by IAM policy")
        }
      elif (.hookSpecificOutput.additionalContext // "") != "" then
        {
          decision: "block",
          reason: .hookSpecificOutput.additionalContext
        }
      else
        empty
      end
    ' "$BODY_FILE"
    ;;
esac

exit 0
