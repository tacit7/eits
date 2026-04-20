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

# Parse host and port out of EITS_URL (default: http://localhost:5001/api/v1).
# Handles: explicit port, no-port http/https, auth URLs (user:pass@host), IPv6 ([::1]).
_eits_u="${EITS_URL:-http://localhost:5001/api/v1}"
_eits_scheme="${_eits_u%%://*}"         # "http" or "https"
_eits_u="${_eits_u#*://}"               # strip scheme://
_eits_u="${_eits_u%%/*}"                # strip path  → "user:pass@host:port" or "host:port" or "host"
_eits_u="${_eits_u##*@}"                # strip userinfo  → "host:port" or "host" or "[::1]:port"
# Use bash regex: match optional host + explicit numeric port at end of string.
if [[ "${_eits_u}" =~ ^(.*):([0-9]+)$ ]]; then
  _eits_server_host="${BASH_REMATCH[1]}"
  _eits_server_port="${BASH_REMATCH[2]}"
else
  _eits_server_host="${_eits_u}"
  # No explicit port — use scheme default.
  case "${_eits_scheme}" in
    https) _eits_server_port=443 ;;
    *)     _eits_server_port=80  ;;
  esac
fi
# Strip IPv6 brackets so /dev/tcp is happy: [::1] → ::1
_eits_server_host="${_eits_server_host#[}"
_eits_server_host="${_eits_server_host%]}"

# TCP probe — instant refusal when server is down, no hang risk on localhost.
# Runs in a subshell so the fd is cleaned up automatically.
(exec 3<>/dev/tcp/"${_eits_server_host}"/"${_eits_server_port}") 2>/dev/null || exit 0

unset _eits_u _eits_server_host _eits_server_port
