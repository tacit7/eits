#!/bin/bash
# Cross-platform desktop notification for EITS hook events
# Usage: notify.sh "title" "message"
#   or pipe JSON on stdin (reads hook_event_name for title)

TITLE="${1:-Claude Code}"
MESSAGE="${2:-}"

if [ -z "$MESSAGE" ]; then
  INPUT=$(cat)
  EVENT=$(echo "$INPUT" | jq -r '.hook_event_name // "Event"')
  TITLE="Claude Code - ${EVENT}"
  MESSAGE="Hook fired: ${EVENT}"
fi

case "$(uname -s)" in
  Darwin)
    osascript -e "display notification \"${MESSAGE}\" with title \"${TITLE}\""
    ;;
  Linux)
    if command -v notify-send &>/dev/null; then
      notify-send -a "Claude Code" "$TITLE" "$MESSAGE"
    elif command -v kdialog &>/dev/null; then
      kdialog --passivepopup "$MESSAGE" 5 --title "$TITLE"
    fi
    ;;
  MINGW*|MSYS*|CYGWIN*)
    powershell.exe -NoProfile -Command "
      Add-Type -AssemblyName System.Windows.Forms;
      \$n = New-Object System.Windows.Forms.NotifyIcon;
      \$n.Icon = [System.Drawing.SystemIcons]::Information;
      \$n.BalloonTipTitle = '$TITLE';
      \$n.BalloonTipText = '$MESSAGE';
      \$n.Visible = \$true;
      \$n.ShowBalloonTip(5000);
      Start-Sleep -Seconds 6;
      \$n.Dispose()
    " &>/dev/null &
    ;;
esac

exit 0
