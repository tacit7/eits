# End Session Workflow

Orchestrates a clean session close with tracking and commits.

## Steps

1. **Update EITS tracking**
   - Run `/i-update-status` to review session work and update Eye in the Sky

2. **Commit all work**
   - Run `/commit-work` to commit all changes made during this session
   - Follow existing git commit guidelines (no Anthropic attribution)
   - Commits are logged to EITS automatically via the `PostToolUse` hook (`eits-post-tool-commit.sh`) — no manual logging needed

3. **Mark session completed**
   - Run: `eits sessions update "$EITS_SESSION_UUID" --status completed`
   - This marks the session as done in the UI

4. **Final summary**
   - Use `i-speak` to give succinct summary of session
   - What was accomplished
   - What was committed
   - Any follow-up needed

## Rules

- Only commit if there are actual changes to commit
- If `/commit-work` fails, report the error but continue with status update
- Keep summary concise (under 10 lines of speech)

## Example Flow

```
1. Call /i-update-status skill
2. Call /commit-work skill  ← hook logs commits automatically on each git commit bash call
3. Run: eits sessions update "$EITS_SESSION_UUID" --status completed
4. Use i-speak to summarize: "Session wrapped. Updated EITS tracking, committed X changes across Y files. No follow-up needed."
```
