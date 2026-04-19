#!/usr/bin/env bash
# Codex notify/hook dispatcher for EITS.
# Routes Codex hook payloads to the existing EITS hook scripts so Codex behavior
# matches Claude hook behavior as closely as possible.
set -uo pipefail

[ "${EITS_WORKFLOW:-}" = "0" ] && exit 0

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INPUT_JSON="$(timeout 2 cat 2>/dev/null || true)"
[ -z "$INPUT_JSON" ] && exit 0

hook_event_name="$(echo "$INPUT_JSON" | jq -r '.hook_event_name // .hook_event // empty' 2>/dev/null || true)"
hook_source="$(echo "$INPUT_JSON" | jq -r '.source // empty' 2>/dev/null || true)"
tool_name="$(echo "$INPUT_JSON" | jq -r '.tool_name // empty' 2>/dev/null || true)"
has_stop_flag="$(echo "$INPUT_JSON" | jq -r 'has(\"stop_hook_active\")' 2>/dev/null || echo "false")"

# Fallback inference when the event name is absent.
if [ -z "$hook_event_name" ]; then
  if [ -n "$hook_source" ]; then
    hook_event_name="SessionStart"
  elif [ "$has_stop_flag" = "true" ]; then
    hook_event_name="Stop"
  elif [ -n "$tool_name" ]; then
    hook_event_name="PostToolUse"
  fi
fi

# Keep compatibility with scripts that branch on Claude entrypoint.
if [ -z "${CLAUDE_CODE_ENTRYPOINT:-}" ] && [ -n "${EITS_ENTRYPOINT:-}" ]; then
  export CLAUDE_CODE_ENTRYPOINT="$EITS_ENTRYPOINT"
fi

run_hook() {
  local script="$1"
  [ -x "$script" ] || return 0
  echo "$INPUT_JSON" | "$script"
}

case "$hook_event_name" in
  SessionStart)
    case "$hook_source" in
      startup|clear)
        run_hook "$SCRIPT_DIR/eits-session-startup.sh"
        run_hook "$SCRIPT_DIR/eits-agent-working.sh"
        ;;
      resume)
        run_hook "$SCRIPT_DIR/eits-session-resume.sh"
        run_hook "$SCRIPT_DIR/eits-agent-working.sh"
        ;;
      compact)
        run_hook "$SCRIPT_DIR/eits-session-compact.sh"
        run_hook "$SCRIPT_DIR/eits-session-startup.sh"
        run_hook "$SCRIPT_DIR/eits-agent-working.sh"
        ;;
      *)
        # Default to startup semantics when source is omitted/unknown.
        run_hook "$SCRIPT_DIR/eits-session-startup.sh"
        run_hook "$SCRIPT_DIR/eits-agent-working.sh"
        ;;
    esac
    ;;
  UserPromptSubmit)
    run_hook "$SCRIPT_DIR/codex-prompt-working.sh"
    ;;
  PreToolUse)
    # Claude parity: enforce EITS workflow on Edit/Write and run worktree guard for Bash.
    case "$tool_name" in
      Edit|Write)
        run_hook "$SCRIPT_DIR/eits-pre-tool-use.sh"
        ;;
      Bash)
        run_hook "$SCRIPT_DIR/eits-rm-worktree-guard.sh"
        ;;
    esac
    run_hook "$SCRIPT_DIR/eits-nats-tool-pre.sh"
    ;;
  PostToolUse)
    run_hook "$SCRIPT_DIR/eits-post-tool-use.sh"
    # Commit logging path adapted for Codex payload shape.
    run_hook "$SCRIPT_DIR/codex-post-commit.sh"
    ;;
  PreCompact)
    run_hook "$SCRIPT_DIR/eits-pre-compact.sh"
    ;;
  SessionEnd)
    run_hook "$SCRIPT_DIR/eits-session-end.sh"
    ;;
  Stop)
    # Codex variant keeps stop behavior and task-annotation enforcement.
    run_hook "$SCRIPT_DIR/codex-session-stop.sh"
    ;;
  *)
    # Unknown event — no-op.
    ;;
esac

exit 0
