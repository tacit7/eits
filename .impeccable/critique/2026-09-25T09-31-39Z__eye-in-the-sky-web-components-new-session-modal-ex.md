---
target: new agent form in sessions page
total_score: 21
max_score: 40
na_heuristics: 
p0_count: 0
p1_count: 3
timestamp: 2026-09-25T09-31-39Z
slug: eye-in-the-sky-web-components-new-session-modal-ex
---
Method: dual-agent (A: 01a0d7e4-6c64-7b31-8903-ac6916fadccb · B: 01a0d7e4-6cfc-76a2-8f76-ca53966cf66a)

## Design Health Score

| # | Heuristic | Score | Key Issue |
|---|-----------|-------|-----------|
| 1 | Visibility of System Status | 2 | No visible pending/loading state or launch preflight in the modal. |
| 2 | Match System / Real World | 3 | Operational labels mostly fit, but CLI/safety concepts surface without enough framing. |
| 3 | User Control and Freedom | 2 | Escape/backdrop close exists, but no review/undo framing for a high-impact launch. |
| 4 | Consistency and Standards | 2 | User-facing and source concepts drift between New Agent, New Session, drawer, modal, Launch, and Chat. |
| 5 | Error Prevention | 1 | Risky runtime choices can be hidden in Advanced; Codex bypass is checked by default when shown. |
| 6 | Recognition Rather Than Recall | 3 | Labels and placeholders help, but Advanced still expects CLI literacy. |
| 7 | Flexibility and Efficiency | 3 | Defaults, prompt templates, focus behavior, and model picker support repeat operators. |
| 8 | Aesthetic and Minimalist Design | 2 | The compact style is right, but the flat vertical stack makes too many decisions feel equal. |
| 9 | Error Recovery | 1 | Inline validation and recovery states are not visible in the form itself. |
| 10 | Help and Documentation | 2 | Worktree has a useful hint; EITS Workflow, Chat, and safety posture need the same treatment. |
| **Total** | | **21/40** | **Needs focused UX hardening** |

## Design Specificity Verdict

**LLM assessment**: The form is recognizably EITS in density, tone, and dark operator-console styling, but it is not yet fully authored as an agent control-room launch surface. It still reads like a generic AI agent launcher more than a confident operational preflight. The missing product-specific layer is a compact launch summary that exposes model, project, workflow, worktree, permissions, and risk before the operator commits.

**Deterministic scan**: The Impeccable detector reported 0 findings for `lib/eye_in_the_sky_web/components/new_session_modal.ex`. An earlier wrong-target scan of `new_agent_drawer.ex` also returned 0 findings, but the sessions page actually renders `NewSessionModal`, so that earlier scan is out of scope.

**Visual overlays**: No reliable user-visible overlay is available. Browser inspection succeeded on `http://localhost:5001/projects/1/sessions`, but the available browser evaluation surface is read-only, so mutable detector injection was skipped. Screenshot evidence confirmed that at roughly `1309x630`, the dialog is about `476x596` while the form content is about `764px` tall; the primary actions begin below the initial visible area.

## Overall Impression

This is a solid functional modal wearing the right EITS clothes, but it asks the operator to launch work without enough preflight confidence. The biggest opportunity is to turn the bottom of the form from generic submit buttons into a command summary: what will run, where, under which safety posture, and what happens next.

## What's Working

1. The modal fits the existing product shell: compact, dark, restrained, and visually consistent with the sessions console.

2. The model selector appearing first is sensible for EITS operators, because provider/model is a real operational choice with cost and capability implications.

3. Project context is handled well: fixed and visible from a project page, selectable from a global sessions context.

## Priority Issues

**[P1] Primary actions are below the fold on common desktop height**

Why it matters: launching an agent is the whole point of the form, but at the inspected viewport the operator sees setup fields and only part of the lower form. This makes the flow feel longer and hides the conclusion of the task.

Fix: Use a sticky footer inside the dialog for `Launch Agent` and secondary mode/action controls, or move to a right-side drawer with a fixed action rail. Keep the action visible while the middle form scrolls.

Suggested command: `$impeccable layout`

**[P1] No launch preflight summary**

Why it matters: an agent launch can create a session, run in a project, use a worktree, consume budget, and apply permissions. The current form has no final scanable answer to "what exactly am I about to start?"

Fix: Add a compact summary strip above the sticky action footer: provider/model, project, worktree or "same tree", EITS workflow on/off, and permission/sandbox profile. Make risky states amber/red and calm states neutral.

Suggested command: `$impeccable harden`

**[P1] Risk settings are underweighted**

Why it matters: for Codex, `Bypass approvals and sandbox` is checked by default inside Advanced. Even if that default is operationally intentional, hiding it makes the safety posture too easy to miss.

Fix: Promote safety into a visible `Run Mode` control near Model: `Normal`, `Plan/read-only`, `Bypass approvals`. If bypass remains default for a provider, show an inline warning in the main form and repeat it in the preflight summary.

Suggested command: `$impeccable harden`

**[P2] Intent fields create avoidable semantic load**

Why it matters: `Agent`, `Agent Prompt`, `Session Name`, and `Prompt` cluster near each other and ask the user to infer which one is persona, template, task title, and actual instruction.

Fix: Group the form by mental model: `Instruction` for prompt/template/name, `Context` for project/worktree/attachments, and `Runtime` for model/agent/workflow/advanced. Rename `Prompt` to `Instructions` or `Task` if that better matches the resulting agent work.

Suggested command: `$impeccable clarify`

**[P2] Launch Agent and Chat are too symmetrical**

Why it matters: the two equal-width buttons look like equal choices, but their consequences are not self-evident. If both submit the same form with different post-launch behavior, the UI should explain the difference before the final click.

Fix: Make `Launch Agent` the dominant primary action. Treat `Open Chat` as a launch mode toggle or secondary ghost action with a short tooltip/sublabel such as "create session and jump to chat."

Suggested command: `$impeccable clarify`

**[P3] Naming drift weakens trust**

Why it matters: the UI says `New Agent`, the form id/source say `new-session`, the LiveView assign says `show_new_session_drawer`, and the component is a modal. Users do not see all of that, but naming debt tends to leak into tests, labels, future copy, and behavior.

Fix: Standardize product language around `Agent` for creation and reserve `Session` for the resulting record. Rename internal surfaces when practical, or at least align test names and user-facing copy.

Suggested command: `$impeccable polish`

## Persona Red Flags

**Power Operator**: They can move fast with defaults, but the invisible final action area and missing preflight slow down the last decision. They also cannot scan runtime/safety posture without opening Advanced.

**First-Time Developer**: They may stall on the difference between Agent, Agent Prompt, Session Name, and Prompt. `EITS Workflow` is checked by default but not explained, so the user cannot confidently predict what enabling it does.

**Security-Conscious Maintainer**: The high-impact permission/sandbox controls are hidden in Advanced, and the main form does not surface whether the launch is safe, read-only, or bypassing guardrails.

## Minor Observations

The `sm:max-w-md` dialog feels tight for this many controls. It works visually until Advanced opens, then the container becomes more like a scroll tunnel.

The worktree hint is specific and useful; EITS Workflow and Chat need similarly concrete microcopy.

The close button appears visually quiet and lacks an accessible label in the AX tree beyond being a generic button, worth tightening during an accessibility pass.

The detector did not flag issues, so the core problems are product UX and hierarchy rather than obvious static anti-patterns.

## Questions to Consider

- What if the first visible required field were simply "What should the agent do?" and everything else became defaults plus preflight?
- What would make the final click feel like an operator preflight instead of a generic submit?
- Should Chat be a launch destination/mode selected before submit, rather than a second submit button at the bottom?
