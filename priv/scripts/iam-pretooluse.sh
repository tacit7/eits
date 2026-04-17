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

# Read payload from stdin
payload=$(timeout 5 cat 2>/dev/null) || _fail_open "stdin read timed out"
[ -z "$payload" ] && _fail_open "empty stdin payload"

# Validate it's parseable JSON
echo "$payload" | jq -e . >/dev/null 2>&1 || _fail_open "payload is not valid JSON"

# POST to IAM decide endpoint
http_response=$(
  curl \
    --silent \
    --show-error \
    --max-time "$CURL_TIMEOUT" \
    --connect-timeout 2 \
    --write-out '\n%{http_code}' \
    --header 'Content-Type: application/json' \
    --data-raw "$payload" \
    "$DECIDE_URL" 2>&1
) || _fail_open "curl failed"

# Split body and status code
http_code=$(echo "$http_response" | tail -n1)
response_body=$(echo "$http_response" | sed '$d')

# On non-2xx or unparseable body, fail open
case "$http_code" in
  2*)
    if echo "$response_body" | jq -e . >/dev/null 2>&1; then
      printf '%s\n' "$response_body"
      exit 0
    else
      _fail_open "endpoint returned non-JSON body (HTTP $http_code)"
    fi
    ;;
  *)
    _fail_open "endpoint returned HTTP $http_code"
    ;;
esac
