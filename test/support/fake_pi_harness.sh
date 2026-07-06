#!/usr/bin/env bash
# Fake Pi harness: replays $FAKE_PI_SCENARIO (a file of output lines) while
# consuming stdin requests. Lines beginning with WAIT:<type> block until a
# request of that type arrives on stdin. Line EXIT:<code> exits with <code>.
# Any other line is echoed verbatim as ndjson output.
#
# For every stdin request seen, the fake auto-responds with a success envelope
# echoing the request id. Special-case: initialize replies include
# {"version":"test","protocolVersion":1} so the SDK's version handshake passes.
#
# NOTE: the scenario file is opened on file descriptor 3 so that stdin (fd 0)
# remains available for reading harness requests inside `consume_one`.
set -u
scenario="${FAKE_PI_SCENARIO:?FAKE_PI_SCENARIO must be set}"

if [ ! -f "$scenario" ]; then
  echo "{\"type\":\"error\",\"error\":\"fake_pi_harness: scenario not found: $scenario\"}" >&2
  exit 2
fi

# Portable "seen" list as a newline-delimited string (bash 3.2 friendly).
SEEN=""
LAST_TYPE=""

seen_has() {
  case $'\n'"$SEEN"$'\n' in
    *$'\n'"$1"$'\n'*) return 0 ;;
    *) return 1 ;;
  esac
}

# Read one JSON request from stdin, auto-respond, record its type.
consume_one() {
  local req t id
  IFS= read -r req <&0 || return 1
  t=$(printf '%s' "$req" | sed -n 's/.*"type":"\([a-z_]*\)".*/\1/p')
  id=$(printf '%s' "$req" | sed -n 's/.*"id":"\([^"]*\)".*/\1/p')
  SEEN="$SEEN
$t"
  if [ -n "$id" ]; then
    if [ "$t" = "initialize" ]; then
      printf '{"id":"%s","type":"response","command":"initialize","success":true,"data":{"version":"test","protocolVersion":1}}\n' "$id"
    else
      printf '{"id":"%s","type":"response","command":"%s","success":true,"data":{}}\n' "$id" "$t"
    fi
  fi
  LAST_TYPE="$t"
  return 0
}

wait_for() {
  local want="$1"
  if seen_has "$want"; then return 0; fi
  while consume_one; do
    if [ "$LAST_TYPE" = "$want" ]; then return 0; fi
  done
  return 1
}

# Read scenario from fd 3; keep fd 0 (stdin) open for consume_one.
while IFS= read -r line <&3; do
  case "$line" in
    WAIT:*)
      wait_for "${line#WAIT:}" || exit 0
      ;;
    EXIT:*)
      exit "${line#EXIT:}"
      ;;
    "")
      printf '\n'
      ;;
    *)
      printf '%s\n' "$line"
      ;;
  esac
done 3< "$scenario"

# Scenario exhausted; drain stdin until closed then exit 0.
while consume_one; do :; done
exit 0
