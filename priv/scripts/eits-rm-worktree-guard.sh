#!/usr/bin/env bash
# Hook: Block rm operations on .claude/worktrees/* when _build or deps are still
# symlinked, to prevent rm-trash (the system alias for rm) from following the
# symlinks and destroying the main project's _build/deps directories.
#
# Blocks three dangerous patterns:
#   1. rm -rf .claude/worktrees/<name>             (when _build/deps symlinks exist inside)
#   2. rm -rf .claude/worktrees/<name>/_build      (token is itself a symlink)
#   3. rm -rf .claude/worktrees/<name>/_build/foo  (path traverses through a symlink)
#
# Matcher: Bash
# Output: hookSpecificOutput JSON with permissionDecision: "deny"; exit 0 to allow.

set -uo pipefail

input_json=$(timeout 2 cat 2>/dev/null) || exit 0
[ -z "$input_json" ] && exit 0

tool_name=$(echo "$input_json" | jq -r '.tool_name // empty' 2>/dev/null)
[ "$tool_name" = "Bash" ] || exit 0

command=$(echo "$input_json" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$command" ] && exit 0

# Match rm or rm-trash as a word boundary — not matches like "term", "rmdir", etc.
# rmdir is safe (won't follow symlinks and only removes empty dirs).
if ! echo "$command" | grep -qE '(^|[^[:alnum:]_-])(rm|rm-trash)([[:space:]]|$)'; then
  exit 0
fi

# Shell-tokenize loosely: split on whitespace and common shell operators.
tokens=$(echo "$command" | tr ';&|<>()`{}' '\n ' | tr -s '[:space:]' '\n')

deny_reason=""
while IFS= read -r token; do
  [ -z "$token" ] && continue

  # Only interested in tokens that look like paths into a worktree.
  [[ "$token" == *".claude/worktrees/"* ]] || continue

  # Strip quotes
  token="${token//\"/}"
  token="${token//\'/}"
  # Strip trailing slash
  token="${token%/}"

  # Resolve relative to CWD so we can stat it.
  if [[ "$token" != /* ]]; then
    abs="$(pwd)/$token"
  else
    abs="$token"
  fi

  # --- Check 1: walk up from the token and verify no ancestor is a symlink ---
  # Only walk while still inside a .claude/worktrees/ path.
  walk="$abs"
  while [[ "$walk" == *"/.claude/worktrees/"* ]]; do
    if [ -L "$walk" ]; then
      target=$(readlink "$walk" 2>/dev/null || echo "?")
      deny_reason="BLOCKED: '$walk' is a symlink to '$target'. rm is aliased to rm-trash on this system and follows symlinks, which would destroy the target (likely the main project's _build or deps). Fix: use \`unlink $walk\` instead, or cd into the worktree and run \`unlink _build; unlink deps\` before rm."
      break 2
    fi
    walk="${walk%/*}"
    [ -z "$walk" ] && break
  done

  # --- Check 2: if the token is a directory, scan its _build and deps children ---
  if [ -d "$abs" ] && [ ! -L "$abs" ]; then
    for name in _build deps; do
      child="$abs/$name"
      if [ -L "$child" ]; then
        target=$(readlink "$child" 2>/dev/null || echo "?")
        deny_reason="BLOCKED: '$abs' still contains symlink '$name' → '$target'. rm -rf on this directory would follow the symlink and trash the main project's $name. Fix: (cd '$abs' && unlink _build 2>/dev/null; unlink deps 2>/dev/null) then retry the rm."
        break 2
      fi
    done
  fi
done <<< "$tokens"

if [ -n "$deny_reason" ]; then
  jq -n \
    --arg reason "$deny_reason" \
    '{
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        permissionDecision: "deny",
        permissionDecisionReason: $reason
      }
    }'
  exit 0
fi

exit 0
