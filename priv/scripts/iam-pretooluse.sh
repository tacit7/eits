#!/usr/bin/env bash
# Hook: IAM PreToolUse — calls EITS IAM decide endpoint, emits hook response JSON.
# Fail-open: any network/endpoint error emits {"continue": true} and exits 0.
set -uo pipefail

EITS_BASE="${EITS_URL:-http://localhost:5001/api/v1}"
DECIDE_URL="${EITS_BASE}/iam/decide"
CURL_TIMEOUT=3

_fail_open() {
  local msg="${1:-}"
  [ -n "$msg" ] && echo "[iam-pretooluse] fail-open: $msg" >&2
  printf '{"continue":true}\n'
  exit 0
}

# Validate dependencies
command -v curl >/dev/null 2>&1 || _fail_open "curl not found"
command -v jq   >/dev/null 2>&1 || _fail_open "jq not found"

# Read payload from stdin into tempfile (safer than shell variable expansion)
PAYLOAD_FILE=$(mktemp /tmp/iam-payload.XXXXXX)
BODY_FILE=$(mktemp /tmp/iam-body.XXXXXX)
trap 'rm -f "$PAYLOAD_FILE" "$BODY_FILE"' EXIT

timeout 5 cat > "$PAYLOAD_FILE" 2>/dev/null || _fail_open "stdin read timed out"
[ ! -s "$PAYLOAD_FILE" ] && _fail_open "empty stdin payload"

# Validate it's parseable JSON
jq -e . < "$PAYLOAD_FILE" >/dev/null 2>&1 || _fail_open "payload is not valid JSON"

# POST to IAM decide endpoint; write body to file, capture HTTP code directly
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
) || _fail_open "curl failed"

# On non-2xx or unparseable body, fail open
case "$http_code" in
  2*)
    if jq -e . < "$BODY_FILE" >/dev/null 2>&1; then
      cat "$BODY_FILE"
      exit 0
    else
      _fail_open "endpoint returned non-JSON body (HTTP $http_code)"
    fi
    ;;
  *)
    _fail_open "endpoint returned HTTP $http_code"
    ;;
esac
