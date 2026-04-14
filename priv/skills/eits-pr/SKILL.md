---
name: eits-pr
description: Create or review a GitHub PR with Codex code review. Spawns a Codex reviewer, handles the review loop (fix, push, re-review), posts comments on behalf of sandboxed Codex, and iterates until LGTM. Use when creating PRs, requesting reviews, or responding to Codex review DMs.
user-invocable: true
allowed-tools: Bash, Read, Edit, Write, Glob, Grep, Skill
---

# EITS PR Review Workflow

End-to-end PR workflow with Codex code review. Handles creation, review spawning, feedback iteration, and approval.

## Account Context

- **Claude account**: `urielmaldonado-claude` — all Claude-side `gh` commands
- **Codex account**: `urielmaldonado-codex` — post on behalf of Codex (sandbox blocks GitHub)
- **Repo**: `tacit7/eits`

## Arguments

- First arg: PR number (review existing) OR PR title (create new)
- `--model` or `-m`: Reviewer model — Codex (`gpt-5.3-codex`) or Claude (`opus`, `sonnet`). Default: `opus`
- `--skip-review`: Skip spawning reviewer
- `--merge`: Merge after approval

## Decision: Create vs Review

- If arg is an integer: review existing PR by that number
- If arg is a string: create new PR then review it

---

## Step 1: Get PR Number

**Existing PR** — use the number directly.

**New PR** — push branch and create:
```bash
# Ensure tacit7 account is used for the push (origin = GitHub)
gh auth switch --user tacit7
git -C /Users/urielmaldonado/projects/eits/web push -u origin "$(git branch --show-current)"

# Create PR as urielmaldonado-claude
gh auth switch --user urielmaldonado-claude
gh pr create --repo tacit7/eits --base main \
  --head "$(git branch --show-current)" \
  --title "<title>" --body "<description>"
```

Note: if `origin` remote rejects the push with 403, set the URL first:
```bash
git remote set-url origin https://tacit7@github.com/tacit7/eits.git
```

---

## Step 2: Get Session Integer ID

Required so Codex can DM back:
```bash
psql -d eits_dev -t -A -c "SELECT id FROM sessions WHERE uuid = '$EITS_SESSION_UUID'"
```

Store as `MY_SESSION_ID`.

---

## Step 3: Spawn Reviewer

### Claude reviewer (default — opus or sonnet)

```bash
eits agents spawn \
  --model opus \
  --project-id 1 \
  --parent-session-id <MY_SESSION_ID> \
  --instructions "You are a senior code reviewer. Review PR #<PR_NUMBER> in tacit7/eits.

PR Title: <PR_TITLE>
Branch: <BRANCH>

Steps:
1. Run: gh auth switch --user urielmaldonado-claude && gh pr diff <PR_NUMBER> --repo tacit7/eits
2. Read changed files directly at the worktree if available.
3. Review for: correctness, security, Elixir idioms, missing edge cases, breaking changes.
4. DM verdict to <MY_SESSION_UUID>:
   eits dm --to <MY_SESSION_UUID> --message 'LGTM: summary' OR 'NEEDS CHANGES: findings'

DM is required."
```

### Codex reviewer (if explicitly requested)

```bash
eits agents spawn \
  --provider codex \
  --model gpt-5.3-codex \
  --project-path "$(pwd)" \
  --parent-session-id <MY_SESSION_ID> \
  --instructions "You are a code reviewer. Review PR #<PR_NUMBER> in the eits repo.

PR Title: <PR_TITLE>
Branch: <BRANCH>

Steps:
1. Run: gh pr view <PR_NUMBER> --repo tacit7/eits
2. Check the diff: git fetch origin && git diff origin/main...origin/<BRANCH>
3. Review for: correctness, security, code quality, missing tests, breaking changes.
4. You CANNOT post to GitHub directly (sandbox blocks it). DM your findings:
   eits dm --to <MY_SESSION_UUID> --message 'LGTM|NEEDS CHANGES|BLOCKED: <findings>'

DM is required."
```

Tell the user: "Reviewer spawned — session `<session_id>`. Will DM back when done."

---

## Step 4: Handle Review DM

DMs arrive as: `DM from:<name> (session:<uuid>) <verdict + findings>`

### LGTM

Post on the reviewer's behalf (reviewers can't post to GitHub directly):
```bash
# For Codex reviewers — use urielmaldonado-codex account
gh auth switch --user urielmaldonado-codex
gh pr comment <PR_NUMBER> --repo tacit7/eits --body "Codex Review (session <REVIEWER_UUID>):

LGTM. <summary from DM>"

# For Claude reviewers — use urielmaldonado-codex account (same pattern)
gh auth switch --user urielmaldonado-codex
gh pr comment <PR_NUMBER> --repo tacit7/eits --body "Opus Review (session <REVIEWER_UUID>):

LGTM. <summary from DM>"
```

Tell the user: "PR #<number> approved. Ready to merge."

### NEEDS CHANGES or BLOCKED

1. Fix the issues in the worktree
2. Commit and push:
```bash
git add <files>
git commit -m "fix: address review -- <summary>"
git -C /Users/urielmaldonado/projects/eits/web push origin <branch>
eits commits create --hash <hash>
```
3. Post response on PR as Claude:
```bash
gh auth switch --user urielmaldonado-claude
gh pr comment <PR_NUMBER> --repo tacit7/eits --body "Addressed review (session <REVIEWER_UUID>):
- <fix 1>
- <fix 2>
Commit: <hash>"
```
4. Spawn a **fresh** reviewer — idle sessions ignore DMs:
```bash
eits agents spawn --model opus --project-id 1 \
  --parent-session-id <MY_SESSION_ID> \
  --instructions "<same reviewer instructions>"
```
5. Wait for next DM. Repeat until LGTM.

---

## Step 5: Merge (optional)

```bash
gh auth switch --user urielmaldonado-claude
gh pr merge <PR_NUMBER> --repo tacit7/eits --merge
git -C /Users/urielmaldonado/projects/eits/web pull origin main
```

---

## Known Limitations

- **Reviewers can't post to GitHub directly** — always post on their behalf with `urielmaldonado-codex` account.
- **Idle sessions ignore DMs** — always spawn fresh for re-reviews, never DM the old session.
- **Push from worktree** — use `git -C /Users/urielmaldonado/projects/eits/web push origin <branch>`.
- **403 on push** — set remote URL: `git remote set-url origin https://tacit7@github.com/tacit7/eits.git`

## Rules

- Never force-push
- Always commit before pushing
- Log commits: `eits commits create --hash <hash>`
- Use `urielmaldonado-claude` for all Claude-side `gh` commands
- Use `urielmaldonado-codex` when posting Codex reviews on its behalf
- Always pass `--to <MY_SESSION_UUID>` in Codex instructions so it DMs back
- Log tasks via eits workflow: `eits tasks begin`, `eits tasks update`, etc.
