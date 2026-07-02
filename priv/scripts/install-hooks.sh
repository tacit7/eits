#!/usr/bin/env bash
# install-hooks.sh — installs EITS Claude Code hooks into ~/.claude/settings.json
#
# Usage:
#   install-hooks.sh [--scripts-dir <dir>] [--eits-cli <path>] [--uninstall]
#
# --scripts-dir   directory containing eits-*.sh scripts (default: same dir as this script)
# --eits-cli      path to the eits CLI binary to install (default: look next to scripts-dir)
# --uninstall     remove EITS hooks from ~/.claude/settings.json
#
# Installs scripts to ~/.config/eits/hooks/ and eits CLI to ~/.local/bin/eits.
# Merges hooks into ~/.claude/settings.json without overwriting unrelated entries.

set -euo pipefail

SCRIPTS_DIR="$(cd "$(dirname "$0")" && pwd)"
EITS_CLI=""
UNINSTALL=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --scripts-dir) SCRIPTS_DIR="$2"; shift 2 ;;
    --eits-cli)    EITS_CLI="$2";    shift 2 ;;
    --uninstall)   UNINSTALL=1;      shift   ;;
    *) echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

HOOKS_DIR="$HOME/.config/eits/hooks"
BIN_DIR="$HOME/.local/bin"
SETTINGS="$HOME/.claude/settings.json"

# ── Core scripts that back the Claude Code hooks ───────────────────────────────
CORE_SCRIPTS=(
  eits-lib.sh
  eits-session-startup.sh
  eits-session-resume.sh
  eits-session-compact.sh
  eits-session-stop.sh
  eits-session-end.sh
  eits-prompt-submit.sh
  eits-agent-working.sh
  eits-stop-auto-close-tasks.sh
)

# ── Uninstall ──────────────────────────────────────────────────────────────────
if [[ $UNINSTALL -eq 1 ]]; then
  echo "Removing EITS hooks from $SETTINGS..."
  python3 - "$SETTINGS" "$HOOKS_DIR" << 'PYEOF'
import sys, json, os

settings_path = sys.argv[1]
hooks_dir = sys.argv[2]

if not os.path.exists(settings_path):
  print("settings.json not found — nothing to remove")
  sys.exit(0)

with open(settings_path) as f:
  root = json.load(f)

hooks = root.get("hooks", {})
changed = False

for event, groups in list(hooks.items()):
  kept = []
  for group in groups:
    inner = group.get("hooks", [])
    filtered = [
      h for h in inner
      if hooks_dir not in h.get("command", "")
    ]
    if len(filtered) != len(inner):
      changed = True
    if filtered:
      group = dict(group)
      group["hooks"] = filtered
      kept.append(group)
    else:
      changed = True
  hooks[event] = kept

root["hooks"] = {k: v for k, v in hooks.items() if v}

if changed:
  with open(settings_path, "w") as f:
    json.dump(root, f, indent=2)
    f.write("\n")
  print("✓ EITS hooks removed")
else:
  print("No EITS hooks found — nothing to remove")
PYEOF
  exit 0
fi

# ── Install scripts ────────────────────────────────────────────────────────────
echo "Installing EITS hook scripts to $HOOKS_DIR..."
mkdir -p "$HOOKS_DIR"

missing=()
for script in "${CORE_SCRIPTS[@]}"; do
  src="$SCRIPTS_DIR/$script"
  if [[ -f "$src" ]]; then
    cp "$src" "$HOOKS_DIR/$script"
    chmod +x "$HOOKS_DIR/$script"
  else
    missing+=("$script")
  fi
done

if [[ ${#missing[@]} -gt 0 ]]; then
  echo "WARNING: missing scripts (hooks will partially work): ${missing[*]}" >&2
fi
echo "✓ Scripts installed"

# ── Install eits CLI ───────────────────────────────────────────────────────────
if [[ -n "$EITS_CLI" ]] && [[ -f "$EITS_CLI" ]]; then
  mkdir -p "$BIN_DIR"
  cp "$EITS_CLI" "$BIN_DIR/eits"
  chmod +x "$BIN_DIR/eits"
  echo "✓ eits CLI installed to $BIN_DIR/eits"

  # Add ~/.local/bin to PATH in shell profiles if not already there
  for profile in "$HOME/.zprofile" "$HOME/.bash_profile"; do
    if [[ -f "$profile" ]] || [[ "$profile" == "$HOME/.zprofile" ]]; then
      if ! grep -q '\.local/bin' "$profile" 2>/dev/null; then
        echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$profile"
        echo "✓ Added ~/.local/bin to PATH in $profile"
      fi
    fi
  done
elif ! command -v eits &>/dev/null; then
  echo "WARNING: eits CLI not found — hooks will fail until eits is on PATH." >&2
  echo "  Run: eits hooks install --eits-cli /path/to/eits" >&2
fi

# ── Merge hooks into ~/.claude/settings.json ──────────────────────────────────
echo "Merging hooks into $SETTINGS..."
mkdir -p "$(dirname "$SETTINGS")"

python3 - "$SETTINGS" "$HOOKS_DIR" << 'PYEOF'
import sys, json, os

settings_path = sys.argv[1]
hooks_dir = sys.argv[2]

# Load or start fresh
if os.path.exists(settings_path):
  with open(settings_path) as f:
    try:
      root = json.load(f)
    except json.JSONDecodeError:
      root = {}
else:
  root = {}

if not isinstance(root, dict):
  root = {}

hooks = root.setdefault("hooks", {})

def cmd(script, async_=False):
  h = {"type": "command", "command": os.path.join(hooks_dir, script)}
  if async_:
    h["async"] = True
  return h

def already_has(groups, command_substr):
  for g in groups:
    for h in g.get("hooks", []):
      if command_substr in h.get("command", ""):
        return True
  return False

# SessionStart — four matchers
ss = hooks.setdefault("SessionStart", [])
for matcher, scripts in [
  ("startup", [cmd("eits-session-startup.sh"), cmd("eits-agent-working.sh")]),
  ("resume",  [cmd("eits-session-resume.sh"),  cmd("eits-agent-working.sh")]),
  ("compact", [cmd("eits-session-compact.sh"), cmd("eits-session-startup.sh")]),
  ("clear",   [cmd("eits-session-startup.sh"), cmd("eits-agent-working.sh")]),
]:
  # Find or create the group for this matcher
  existing = next((g for g in ss if g.get("matcher") == matcher), None)
  if existing is None:
    ss.append({"matcher": matcher, "hooks": scripts})
  else:
    for s in scripts:
      if not any(s["command"] in h.get("command", "") for h in existing["hooks"]):
        existing["hooks"].append(s)

# UserPromptSubmit
ups = hooks.setdefault("UserPromptSubmit", [])
if not already_has(ups, "eits-prompt-submit.sh"):
  ups.append({"hooks": [cmd("eits-prompt-submit.sh", async_=True)]})

# Stop
stop = hooks.setdefault("Stop", [])
if not already_has(stop, "eits-session-stop.sh"):
  stop.append({"hooks": [cmd("eits-session-stop.sh")]})
if not already_has(stop, "eits-stop-auto-close-tasks.sh"):
  stop.append({"hooks": [cmd("eits-stop-auto-close-tasks.sh")]})

# SessionEnd
se = hooks.setdefault("SessionEnd", [])
if not already_has(se, "eits-session-end.sh"):
  se.append({"hooks": [cmd("eits-session-end.sh")]})

root["hooks"] = hooks

with open(settings_path, "w") as f:
  json.dump(root, f, indent=2)
  f.write("\n")

print("✓ hooks merged into", settings_path)
PYEOF

echo ""
echo "EITS hooks installed. Open a new terminal for PATH changes to take effect."
echo "Session tracking will start on the next Claude Code session."
