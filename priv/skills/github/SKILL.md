# GitHub PR Workflow

Pragmatic workflow for creating, reviewing, and managing GitHub pull requests via the `gh` CLI.

Use this skill whenever the task involves GitHub PRs, comments, approvals, merges, or listing PRs.

## Account Context

- **Claude account**: `urielmaldonado-claude` — use for all Claude-side actions
- **Codex account**: `urielmaldonado-codex` — use when posting on behalf of Codex
- **Repo**: `tacit7/eits`

Switch accounts before commands that require a specific identity:
```bash
gh auth switch --user urielmaldonado-claude
gh auth switch --user urielmaldonado-codex
```

## Auto-Detection

1. Detect current branch: `git branch --show-current`
2. Detect git remote: check whether a `gitea` remote exists
3. For review/comment flows, do not rely on the current branch. Work from the PR number.

## Actions

Supported actions:
- `create`
- `review`
- `comment`
- `approve`
- `merge`
- `close`
- `list`

If no explicit action is provided:
- default to `create` when the request is about opening a PR
- default to `review` when the request is about reviewing a PR
  - `review` means both: perform the code review and post the review findings as a PR comment
- default to `comment` when the request is about posting feedback to a PR

## Command Mapping

Parse user arguments as:
- First arg without `--`: action
- `--title` or `-t`: PR title
- `--description` or `-d`: PR description
- `--number` or `-n`: PR number
- `--message` or `-m`: comment message

## Workflow by Action

### create
1. Get current branch.
2. Verify branch is not `main` or `master`.
3. Check whether branch exists on the remote: `git ls-remote gitea <branch>`.
4. If not, push it: `git push gitea <branch>`.
5. Prompt for title if not provided.
6. Prompt for description if not provided.
7. Get the current session UUID from `$CLAUDE_SESSION_ID` or active session context if available.
8. Append `Session-ID: <session_uuid>` to the description when available.
9. Create the PR:
   ```bash
   gh auth switch --user urielmaldonado-claude
   gh pr create --repo tacit7/eits --base main --head <branch> \
     --title "<title>" --body "<description>"
   ```
10. Show the resulting PR URL.

### list
1. Run:
   ```bash
   gh auth switch --user urielmaldonado-claude
   gh pr list --repo tacit7/eits
   ```
2. Present results cleanly.

### review
1. Require a PR number if the user supplied one. If they did not, list open PRs first and identify the target PR from title/branch/user context. Do not guess when multiple PRs are plausible.
2. Fetch PR metadata:
   `gh api repos/tacit7/eits/pulls/<number>`
3. Fetch changed files:
   `gh api repos/tacit7/eits/pulls/<number>/files`
4. Read the PR title, base ref, head ref, and changed files before diffing.
5. Fetch the branch locally if needed:
   `git fetch gitea <head_ref>`
6. Review the patch using three-dot diff syntax:
   `git diff main...FETCH_HEAD`
7. Prefer targeted diffs for risky files instead of reading a giant patch blindly.
8. Findings must come first: bugs, regressions, contract mismatches, missing tests.
9. Unless the user explicitly says not to post, always post the review findings to the PR after writing them.
10. Use the `comment` workflow to publish the review body safely.

When the user says "review" with no extra qualifier, interpret it as:
- inspect the code
- produce review findings
- post those findings as a PR comment
- then summarize the posted review back to the user

### comment
1. Require `--number` and `--message`.
2. For short one-line comments:
   ```bash
   gh auth switch --user urielmaldonado-claude
   gh pr comment <number> --repo tacit7/eits --body "<message>"
   ```
3. For multi-line comments, use `--body-file`:
   ```bash
   cat > /tmp/pr_comment.md << 'EOF'
   <comment body>
   EOF
   gh auth switch --user urielmaldonado-claude
   gh pr comment <number> --repo tacit7/eits --body-file /tmp/pr_comment.md
   ```
4. After posting, confirm the comment was created.

### approve
1. Require `--number`.
2. Optional `--message` for approval note.
3. Run:
   ```bash
   gh auth switch --user urielmaldonado-claude
   gh pr review <number> --repo tacit7/eits --approve --body "<message>"
   ```

### merge
1. Require `--number`.
2. Run:
   ```bash
   gh auth switch --user urielmaldonado-claude
   gh pr merge <number> --repo tacit7/eits --merge
   ```

### close
1. Require `--number`.
2. Run:
   ```bash
   gh auth switch --user urielmaldonado-claude
   gh pr close <number> --repo tacit7/eits
   ```

## Preferred API Fallbacks

If higher-level `gh pr` subcommands are unreliable, use `gh api`.

Stable endpoints:
- PR metadata: `gh api repos/tacit7/eits/pulls/<number>`
- Changed files: `gh api repos/tacit7/eits/pulls/<number>/files`
- PR comments: `gh api repos/tacit7/eits/issues/<number>/comments`

## Review Heuristics

When reviewing a PR:
- Verify the PR number matches the intended title/head branch before commenting.
- Prefer the changed-file list first to scope the review.
- Focus on Elixir/Phoenix behavioral regressions, API contract changes, queue/state machine errors, missing tests, and unsafe shell integrations.
- Call out residual risk if coverage is missing for the critical path.
- Do not post a comment to the wrong PR just because it was updated recently.
- If there are no findings, say so clearly and post a brief "no findings" review comment unless the user asked for local review only.

## Shell Safety

When posting comments:
- Avoid passing multi-line text directly through zsh.
- Prefer `--body-file` with a temp file for multi-line review bodies.

## Error Handling

- If not in a git repo: stop with an error.
- If on `main`/`master` during `create`: stop with an error.
- If branch push fails: surface the git error.
- If multiple open PRs could match the request and no number is supplied: require disambiguation.
- If review data cannot be fetched, say exactly which command failed.

## Example Usage

```bash
# List PRs
/github list

# Review PR 20
/github review -n 20

# Comment on PR 20
/github comment -n 20 -m "Found a regression in the SDK handler lifecycle"

# Create a PR from the current branch
/github create -t "Fix worker retry path" -d "Prevents stale failed workers from black-holing new messages"

# Approve PR 20
/github approve -n 20 -m "Looks good"
```

## Reviewing PR Diffs

Use three-dot diff syntax to review only the branch changes since divergence from base:

```bash
git diff main...<branch>
git diff main...<branch> --name-only
git diff main...<branch> --stat
git diff main...<branch> -- path/to/file.ex
```

If you fetched the PR branch into `FETCH_HEAD`:

```bash
git diff main...FETCH_HEAD
git diff --name-only main...FETCH_HEAD
git diff --stat main...FETCH_HEAD
```

Three-dot `...` shows only the branch-introduced changes. Avoid two-dot `..` for review.

## Outcome

The skill should leave you with one of these outcomes:
- PR created successfully
- Review findings prepared locally only when the user explicitly asked not to comment
- Review comment posted to the correct PR
- Approval/merge/close completed
- Clear failure with the exact blocked step
