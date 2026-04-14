---
name: pr
description: Create a GitHub PR, spawn a Codex reviewer, and iterate on feedback until the PR is approved. Handles the full PR lifecycle with automated code review.
user-invocable: true
allowed-tools: Bash, Read, Edit, Write, Glob, Grep, Skill
---

# PR Skill: Create, Review, Iterate

End-to-end PR workflow: create the PR on GitHub, spawn a Codex session to review it, then iterate on feedback until approved.

## Arguments

- First arg: PR title (required)
- `--description` or `-d`: PR description (optional)
- `--model` or `-m`: Codex model for reviewer (default: sonnet)
- `--skip-review`: Create PR without spawning reviewer

## Step 1: Create the PR via Gitea Skill

Invoke the `/github` skill to create the PR. This handles:
- Branch detection and push
- Session-ID appending to description
- `gh pr create` execution

```
/github "<title>" -d "<description>"
```

Capture the PR number and URL from the output.

## Step 2: Spawn Codex Reviewer

Use `eits agents spawn` to create a Codex session that will review the PR.

**Parameters:**
- `--provider codex`
- `--model`: from args or default `gpt-5.3-codex` (valid Codex models: gpt-5.3-codex, gpt-5.2-codex, gpt-5.2, gpt-5.1, gpt-5-codex-mini)
- `--project-path`: current working directory
- `--parent-session-id`: your current EITS session integer ID (so Codex knows who spawned it and can DM you back)
- `--instructions`: see below

**Get your session integer ID:**
```bash
psql -d eits_dev -t -A -c "SELECT id FROM sessions WHERE uuid = '$CLAUDE_SESSION_ID'"
```

**Spawn command:**
```bash
eits agents spawn \
  --provider codex \
  --model gpt-5.3-codex \
  --project-path "$(pwd)" \
  --parent-session-id <MY_SESSION_INT_ID> \
  --dangerouslySkipPermissions \
  --instructions "..."
```

**Reviewer Instructions Template:**

```
You are a code reviewer. Review PR #<PR_NUMBER> in the eits repo.

PR Title: <PR_TITLE>
PR URL: github.com/tacit7/eits/pulls/<PR_NUMBER>
Branch: <BRANCH>

Steps:
1. Run: gh pr view <PR_NUMBER> --repo tacit7/eits
2. Check the diff: git fetch gitea && git diff gitea/main...gitea/<BRANCH>
3. Review the changes for: correctness, security, code quality, missing tests, breaking changes.
4. IMPORTANT: You CANNOT post to GitHub directly (sandbox blocks it).
   DM your findings to the session that spawned you:
   eits dm --to <MY_SESSION_UUID> --message "LGTM|NEEDS CHANGES|BLOCKED: <findings>"
   The spawner will post on your behalf as urielmaldonado-codex.
5. DM is required. Focus on real issues only. Skip praise.
```

Save the spawned agent's integer `session_id` from the response. Codex will DM you back since you passed your session ID in the instructions.

## Step 3: Wait for Review

After spawning the Codex reviewer, tell the user:

```
PR created and Codex reviewer spawned.
- PR: <URL>
- Reviewer session: <session_uuid>

I'll address Codex's feedback when it arrives via DM. You can also check the PR comments on GitHub.
```

When you receive a DM from the Codex reviewer, proceed to Step 4.

## Step 4: Address Feedback Loop

When Codex review arrives:

1. **Parse the verdict**: LGTM, NEEDS CHANGES, or BLOCKED
2. **If LGTM**: Post on Codex's behalf and finish:
   ```bash
   gh auth switch --user urielmaldonado-codex
   gh pr comment <PR_NUMBER> --repo tacit7/eits --body "Codex Review (session <CODEX_UUID>):

   LGTM. <summary from DM>"
   ```
3. **If NEEDS CHANGES or BLOCKED**:
   a. Read each issue Codex raised
   b. Make the fixes in code
   c. Commit the changes
   d. Push to the PR branch: `git push gitea <branch>`
   e. Post on Claude's behalf:
      ```bash
      gh auth switch --user urielmaldonado-claude
      gh pr comment <PR_NUMBER> --repo tacit7/eits --body "Addressed Codex review (session <CODEX_UUID>):
      - <summary of each fix>
      Commit: <hash>"
      ```
   f. Spawn a fresh Codex reviewer (idle sessions ignore DMs):
      ```bash
      eits agents spawn --provider codex --model gpt-5.3-codex \
        --project-path "$(pwd)" \
        --parent-session-id <MY_SESSION_INT_ID> \
        --instructions "<same reviewer instructions with updated branch>"
      ```
   g. Wait for the next review DM from Codex

4. **Repeat** steps 3-4 until Codex responds with LGTM.

## Step 5: Finalize

Once approved:
1. Notify user: "PR #<number> approved by Codex. Ready to merge."
2. Ask user if they want to merge: `/github merge -n <PR_NUMBER>`
3. Use the `i-speak` skill to announce completion

## Error Handling

- If Codex fails to spawn: log the error, notify user, offer to retry
- If Codex never DMs back: inform user, offer to check the Codex session status
- If push fails: diagnose git issues before retrying

## Rules

- Never force-push unless user explicitly asks
- Always commit fixes before pushing
- Keep DMs to Codex concise and actionable
- Track all commits via `eits commits create --hash <hash>`
- Codex cannot reach GitHub; always post its review comments as `urielmaldonado-codex`
- Both agents communicate via `eits dm`
