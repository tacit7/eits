#!/usr/bin/env bash
# eits-lib.sh — shared guard for EITS hook scripts.
#
# Source this file near the top of every hook that talks to the EITS server:
#
#   . "$(cd "$(dirname "$0")" && pwd)/eits-lib.sh"
#
# If the server is unreachable, this script calls `exit 0` in the sourcing
# shell, silently skipping the rest of the hook. When the server IS up the
# TCP probe completes in sub-millisecond time (localhost), so hot-path hooks
# like pre-tool-use are not measurably affected.

# Parse host and port out of EITS_URL (default: http://localhost:5001/api/v1)
_eits_u="${EITS_URL:-http://localhost:5001/api/v1}"
_eits_u="${_eits_u#http://}"
_eits_u="${_eits_u#https://}"
_eits_u="${_eits_u%%/*}"          # "localhost:5001"
_eits_server_host="${_eits_u%%:*}" # "localhost"
_eits_server_port="${_eits_u##*:}" # "5001"
[[ "${_eits_server_port}" =~ ^[0-9]+$ ]] || _eits_server_port=5001

# TCP probe — instant refusal when server is down, no hang risk on localhost.
# Runs in a subshell so the fd is cleaned up automatically.
(exec 3<>/dev/tcp/"${_eits_server_host}"/"${_eits_server_port}") 2>/dev/null || exit 0

unset _eits_u _eits_server_host _eits_server_port
