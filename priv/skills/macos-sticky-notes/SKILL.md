---
name: macos-sticky-notes
description: Use when creating a macOS desktop status note, reminder, or visible notification via the Stickies app using AppleScript or shell commands
user-invocable: true
allowed-tools: Bash
---

# macOS Sticky Notes

## Overview

Create desktop-visible notes in macOS Stickies via AppleScript. Direct `make new note` fails with error -2710; the workaround uses System Events `keystroke` to type content after opening Stickies.

## When to Use

- Creating a status note visible on the desktop after work completes
- Leaving a reminder for when the user returns to the machine
- Quick desktop notification that persists across sessions

**Not for:** Linkable notes or automation that needs deep links — Stickies has no URL scheme. Use Apple Notes instead.

## The Workaround

Direct AppleScript fails:
```applescript
-- ERROR -2710: make new note fails
tell application "Stickies"
  make new note with properties {text:"hello"}
end tell
```

Working approach — open Stickies, then use System Events to type:
```applescript
tell application "Stickies" to activate
delay 0.5
tell application "System Events"
  keystroke "n" using command down
  delay 0.3
  keystroke "Your note content here"
end tell
```

## Shell One-Liner

```bash
osascript -e 'tell application "Stickies" to activate' \
          -e 'delay 0.5' \
          -e 'tell application "System Events" to keystroke "n" using command down' \
          -e 'delay 0.3' \
          -e 'tell application "System Events" to keystroke "Status: task complete"'
```

## Multi-Line Notes

Use `key code 36` (Return) to insert newlines:
```applescript
tell application "Stickies" to activate
delay 0.5
tell application "System Events"
  keystroke "n" using command down
  delay 0.3
  keystroke "Line 1"
  key code 36
  keystroke "Line 2"
end tell
```

## Limitations

- No deep links or URL scheme
- No programmatic color control via this method
- Requires Accessibility permissions for System Events (`System Settings > Privacy > Accessibility`)

## Alternative: Apple Notes

When you need linkable notes or richer formatting:
```bash
osascript -e 'tell application "Notes"
  tell account "iCloud"
    make new note at folder "Notes" with properties {name:"Status", body:"Content here"}
  end tell
end tell'
```
