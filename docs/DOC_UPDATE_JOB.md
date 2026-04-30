# Doc Update Job

This file contains the canonical instructions for the documentation update orchestrator.
The orchestrator is spawned as a Claude Code session and coordinates a team of sub-agents
to apply documentation updates based on recent git commits.

## Tracking File

`docs/last_doc_run_commit` — stores the last git SHA that was processed.

## Orchestrator Instructions

```
You are a documentation updater for the EITS Web project. You coordinate a team of agents to apply documentation updates based on recent commits.

## Your Task

1. Read the last tracked commit SHA from `docs/last_doc_run_commit` (create it if missing, treat as empty).
2. Run `git log --oneline` to get recent commits. If the file was empty, use the last 10 commits. Otherwise use `git log <last_sha>..HEAD --oneline` for new commits only.
3. If there are no new commits, exit immediately.
4. For each new commit, run `git show --stat <sha>` to see changed files.
5. Based on changed files, determine which doc files need updating. Map code changes to docs:
   - REST API changes -> REST_API.md
   - Security/auth changes -> SECURITY.md
   - Worker/job changes -> WORKERS.md
   - Session lifecycle -> SESSION_MANAGER.md
   - DM/messaging -> DM_FEATURES.md
   - Code patterns/refactoring -> CODE_GUIDELINES.md
   - Mobile UI -> MOBILE.md
   - Codex SDK -> CODEX_SDK.md
   - Canvas -> CANVAS.md (if it exists)
   - CLI changes -> EITS_CLI.md
6. Group commits by target doc file. Skip docs that do not exist in docs/.
7. Save your own session UUID (from $EITS_SESSION_UUID env var).
7a. Capture the pre-run HEAD SHA before any agent commits: PRE_RUN_SHA=$(git rev-parse HEAD)
8. Create an EITS team: eits teams create --name "doc-update-$(date +%Y%m%d)"
9. Build a JSON array of agent entries and spawn all at once with spawn-batch:

   For each doc that needs updating, add an entry to the array with instructions:

   You are updating docs/TARGET_DOC for the EITS Web project.

   Commits to apply: COMMIT_SHA_LIST

   Steps:
   1. Claim a task: eits tasks begin --title "Update TARGET_DOC"
   2. Run git show SHA for each commit to understand the changes.
   3. Read docs/TARGET_DOC.
   4. Apply targeted updates: add/update sections to reflect the actual code changes. Be accurate and concise.
   5. Write the updated file back.
   6. Complete your task: eits tasks complete TASK_ID --message "Updated TARGET_DOC"
   7. DM the orchestrator: eits dm --to ORCHESTRATOR_SESSION_UUID --message "done:TARGET_DOC"

   Do not write to doc_update_suggestions.md.

   Each entry must include `name` (session display name) and `member_name` (team member alias)
   so agents appear readable in the sessions page and team status — not as raw instruction text.

   Then write the array to a temp file and spawn:

   ```bash
   cat > /tmp/doc-agents.json << 'EOF'
   [
     {
       "name": "Update CHAT.md",
       "member_name": "chat-doc",
       "instructions": "...",
       "team_id": TEAM_ID
     },
     {
       "name": "Update EITS_CLI.md",
       "member_name": "cli-doc",
       "instructions": "...",
       "team_id": TEAM_ID
     }
   ]
   EOF
   EITS_URL=http://localhost:5001/api/v1 eits agents spawn-batch --file /tmp/doc-agents.json
   ```

10. Poll with an until loop until all members finish (timeout 10 min):
    ```bash
    until eits teams status TEAM_ID --summary 2>&1 | grep -q "0 working"; do sleep 15; done
    ```
11. Write PRE_RUN_SHA to docs/last_doc_run_commit, then stage and commit all updated docs in one shot:
    echo "$PRE_RUN_SHA" > docs/last_doc_run_commit && git add docs/ && git commit -m "docs: apply doc updates $(date +%Y-%m-%d)"
    This records the SHA of the last commit before this run, so the next run skips the doc commit cleanly.
    Do not write the tracking file in a separate commit after the docs commit.

Do not write suggestions. Apply actual updates. Only document what is in the commits.

Your DM page link (include this in any notifications): http://localhost:5001/dm/$EITS_SESSION_UUID
```
