---
target: archive confirmation modals sessions and teams
total_score: 22
max_score: 40
na_heuristics: 
p0_count: 0
p1_count: 2
timestamp: 2026-09-25T11-38-45Z
slug: archive-confirmation-modals-sessions-and-teams
---
Method: dual-agent (A: 01a0d859-07d0-7d10-9d6e-4f885f96cd41 · B: 01a0d859-090a-72f1-8c45-467539869a0d)

Design Health Score

| # | Heuristic | Score | Key Issue |
|---|-----------|-------|-----------|
| 1 | Visibility of System Status | 2 | Shows count, but not affected names, active/waiting state, or off-screen selections inside the modal. |
| 2 | Match System / Real World | 3 | Archive/restorable language is understandable, but Sessions says unarchived while Teams says restored. |
| 3 | User Control and Freedom | 2 | Cancel/backdrop exist, but dialog appears CSS-driven rather than robustly modal/focus-managed. |
| 4 | Consistency and Standards | 2 | Sessions uses a component, Teams hand-rolls a near-copy with different classes/copy. |
| 5 | Error Prevention | 2 | Bulk archive is confirmed, but the decision lacks enough evidence to prevent wrong-object archive. |
| 6 | Recognition Rather Than Recall | 2 | User must remember what was selected after opening the modal. |
| 7 | Flexibility and Efficiency | 3 | Bulk selection flow is efficient and compact. |
| 8 | Aesthetic and Minimalist Design | 2 | Minimal, but too generic and slightly oversized for the operator-console density. |
| 9 | Error Recovery | 2 | Says reversible, but offers no immediate View archived or Undo route. |
| 10 | Help and Documentation | 2 | The modal hints archive is reversible but does not explain where recovery happens. |
| **Total** | | **22/40** | **Acceptable: usable, but under-instrumented for an operational action.** |

Design Specificity Verdict

LLM assessment: The surrounding Sessions and Teams pages feel like EITS: compact, operational, and built around bulk supervision. The archive modals themselves feel category-interchangeable. They confirm a number, not the operational consequence of hiding agent work or team coordination state.

Deterministic scan: The detector returned no findings for the narrow target set: `sessions.ex`, `project_sessions_page.ex`, `project_sessions_table.ex`, `agent_list.ex`, and `teams.ex`. That means the issues are not obvious style-rule violations; they are product-specific decision quality gaps.

Visual overlays: Browser overlay was skipped because the routes sit behind authenticated LiveView app routes. Fallback evidence came from source inspection and clean detector output.

Overall Impression

These modals are clean and functional, but too thin. For an operator console, archive is not just housekeeping; it changes what work is visible. The modals should help the user trust they are archiving the right sessions or teams without canceling to reread the list.

What's Working

- Bulk archive has an explicit confirmation instead of firing immediately.
- Warning color is appropriate: archive is reversible, so it should not feel as severe as delete.
- The copy is short and scannable; no wall of explanatory text.

Priority Issues

- **[P1] Confirmation lacks operational evidence**
  Why it matters: Count-only confirmation forces users to remember the selection and increases wrong-object risk.
  Fix: Show the first 3 selected session/team names, plus `+N more`, and summarize active/waiting/failed counts when available.
  Suggested command: `$impeccable clarify`

- **[P1] Modal accessibility is probably weaker than the visual treatment implies**
  Why it matters: The UI uses `<dialog>` with CSS classes, but source evidence does not show native `open`/`showModal`, `aria-labelledby`, focus trapping, Escape behavior, or focus return.
  Fix: Harden shared modal behavior and add IDs/labels for title and description.
  Suggested command: `$impeccable harden`

- **[P2] Sessions and Teams drift from each other**
  Why it matters: Sessions uses `AgentList.archive_confirm_modal`; Teams hand-rolls a copy. Small differences will keep accumulating.
  Fix: Extract a shared archive confirmation component with object label, selected count, preview rows, restore copy, and confirm event.
  Suggested command: `$impeccable polish`

- **[P2] Recovery path is vague**
  Why it matters: `can be restored later` reassures only halfway; it does not tell the user where or how.
  Fix: Add destination copy like `Find archived sessions in the Archived filter`, and consider a post-action `View archived` flash action.
  Suggested command: `$impeccable clarify`

- **[P3] The modal visual weight is a little blunt**
  Why it matters: `text-lg font-bold` and a plain centered card feel generic beside the compact EITS control-room UI.
  Fix: Use tighter title scale, an archive icon/status chip, compact evidence rows, and button text like `Archive 4`.
  Suggested command: `$impeccable typeset`

Persona Red Flags

**Alex (Power User)**: Alex can bulk archive quickly, but the modal slows them at the worst point because it lacks names/statuses. They must cancel and re-scan to regain confidence.

**Sam (Accessibility-Dependent User)**: Sam may not get a reliable modal experience if focus is not trapped/returned and the dialog is only visually open. The hidden backdrop button labeled `close` is not enough semantic structure.

**Jordan (First-Timer)**: Jordan understands archive is reversible, but not where archived items go. They may worry the selected sessions/teams disappeared permanently.

Minor Observations

- Sessions mentions `unarchived`; Teams says `restored`. Pick one vocabulary.
- Sessions toolbar can show off-screen selected count, but the modal does not repeat that risk.
- Teams archive action is implemented through `Teams.batch_delete_teams(ids)`, which may be semantically correct internally, but the naming is unsettling when reviewing the flow.
- The confirm button should carry the count: `Archive 3 sessions` or `Archive 2 teams`.

Questions to Consider

- What would the modal need to show so you can archive without rereading the list?
- Should archiving active sessions/teams produce a stronger warning than archiving idle/completed ones?
- Should archive confirmations become one shared EITS pattern across sessions, teams, tasks, and notes?
