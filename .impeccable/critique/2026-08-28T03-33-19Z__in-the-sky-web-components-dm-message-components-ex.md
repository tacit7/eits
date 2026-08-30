---
target: Codex message rendering in the EITS DM/message UI
total_score: 24
max_score: 40
na_heuristics: 
p0_count: 0
p1_count: 3
timestamp: 2026-08-28T03-33-19Z
slug: in-the-sky-web-components-dm-message-components-ex
---
Method: dual-agent (A: 01a0466a-a777-78b1-be48-4710c5bf031c · B: 01a0466a-c5f4-7871-bbf1-d7f57b493996)

**Design Health Score**

| # | Heuristic | Score | Key Issue |
|---|---:|---:|---|
| 1 | Visibility of System Status | 3 | Streaming, skeletons, clusters, and raw event access help, but Codex turn phase/failure state is not prominent enough. |
| 2 | Match System / Real World | 3 | Developer-facing tool/output language fits the product; Codex-specific events are flattened into generic chat concepts. |
| 3 | User Control and Freedom | 2 | Collapse/copy exist, but some actions are hover-hidden or too coarse for long outputs and clusters. |
| 4 | Consistency and Standards | 3 | Shared message body and tool widgets create a coherent system; compact/raw modes diverge in behavior and affordance. |
| 5 | Error Prevention | 2 | Hook failure rendering exists, but failed Codex turns and command failures do not get a strong prevention/recovery model. |
| 6 | Recognition Rather Than Recall | 3 | Labels, counts, files, providers, and timestamps help; raw/truncated event data forces recall under load. |
| 7 | Flexibility and Efficiency | 2 | Good density, but weak filtering, cluster summary, and expansion controls for heavy tool sessions. |
| 8 | Aesthetic and Minimalist Design | 3 | Calm, compact, and on-brand; some metadata is so faint it becomes invisible rather than quiet. |
| 9 | Error Recovery | 1 | Parser can see failure events, but the UI does not appear to render first-class recovery cards for them. |
| 10 | Help and Documentation | 2 | Raw stream is available, but high-stakes Codex states do not explain what happened or what action to take next. |
| **Total** |  | **24/40** | **Functional but under-instrumented for Codex operation** |

**Design Specificity Verdict**

The rendering is specific to EITS, but not yet specific enough to Codex. It has the right operator-console foundation: compact streams, grouped tool activity, raw event visibility, timestamps, provider avatars, metrics, and state strips. It does not feel like a generic chat UI.

The weakness is semantic flattening. Live Codex output knows about turns, reasoning, command execution, file changes, MCP calls, web searches, plan updates, errors, and token usage. The rendered experience mostly becomes message/tool/output/raw stream. For an operator console, the system knows more than the interface confidently exposes.

Deterministic scan: 0 findings. The detector returned no issues for `lib/eye_in_the_sky_web/components/dm_message_components.ex` and no issues when expanded across the related DM renderers. Browser visualization was skipped because the target is a Phoenix component rendered through `/dm/:session_id`, not a stable standalone route; a synthetic route would risk misrepresenting the actual session state.

**Overall Impression**

The renderer is competent and already has the right bones. The biggest improvement is not visual decoration; it is preserving and exposing Codex's operational event structure so a user can scan a run and know what happened, what failed, and what matters without opening raw JSONL.

**What's Working**

1. Primary/secondary tiering is directionally right. Tool chatter is demoted while substantive agent messages get a stronger card treatment.
2. Tool clustering is a good fit for EITS. Stable cluster IDs, counts, duration, and grouped details reduce transcript noise.
3. Tool widgets have useful affordances: collapsible details, copy controls, bounded output regions, and monospace preservation.

**Priority Issues**

**[P1] Failed Codex turns need first-class failure cards**
Why it matters: Operators should not parse raw stream output or infer failure from missing assistant text.
Fix: Convert `turn.failed` and top-level Codex errors into explicit event cards with severity, message, timestamp, failed phase, last tool, and actions such as retry, copy error, and open raw event.
Suggested command: `$impeccable harden`

**[P1] Persisted Codex reloads lose structured event meaning**
Why it matters: Live runs can emit tool/thinking/result events, but session-file reloads currently extract mostly user/assistant text. Historical review becomes less useful than live viewing.
Fix: Teach the Codex session reader/import path to preserve structured `response_item` events as metadata-backed message rows, or add a parallel persisted event model for tool/reasoning/failure records.
Suggested command: `$impeccable shape`

**[P1] Tool clusters hide the wrong information**
Why it matters: “12 tool calls” tells volume, not operational meaning. The user still has to expand to learn whether commands failed, files changed, or outputs matter.
Fix: Summarize clusters as operational facts: `8 calls · 1 failed · 3 files · 42s`, with top tool badges like `Bash`, `Edit`, `WebSearch`, and failure emphasis when any event failed.
Suggested command: `$impeccable clarify`

**[P2] Thinking visibility is conceptually split**
Why it matters: The composer has show/hide thinking controls, but message bodies render thinking whenever metadata exists. That makes the control feel unreliable or ambiguous.
Fix: Pass `show_thinking_blocks` into `MessagesTab` and `message_body`. When hidden, either suppress the details or show one quiet `Reasoning captured` marker.
Suggested command: `$impeccable distill`

**[P2] Tool output readability overprotects layout**
Why it matters: `break-all` prevents overflow, but damages commands, paths, stack traces, URLs, and code-like output.
Fix: Prefer `overflow-x-auto whitespace-pre` for command/code output and use wrapping only for prose-like output. Add header metadata for line count, exit code, duration, and cwd.
Suggested command: `$impeccable typeset`

**[P2] Raw stream panel is too raw for routine debugging**
Why it matters: Raw JSONL is useful evidence, but truncated lines create a second transcript only experts can read quickly.
Fix: Keep raw JSONL collapsible, but add parsed rows showing event type, item type, status, duration, and a copy/open-raw payload affordance. Default collapsed unless a failure occurs.
Suggested command: `$impeccable polish`

**[P3] Secondary interaction affordances are weak on touch and keyboard**
Why it matters: Copy/delete actions that rely on hover are easy to miss outside desktop pointer use.
Fix: Mirror the touch override used by tool copy buttons for attachment delete, and ensure focus-visible states reveal hidden controls.
Suggested command: `$impeccable audit`

**Persona Red Flags**

**Alex, Power Operator:** During a noisy Codex run, Alex can see that tools ran but cannot scan which ones failed, which files changed, or which command is still active without expanding clusters.

**Jordan, First-Time Agent Supervisor:** Jordan sees “Thinking,” “Output,” “raw stream,” and compact tool badges without a clear hierarchy of trust. On failure, the next step is unclear.

**Riley, Incident Reviewer:** Riley needs an audit trail, but timestamps, raw lines, tool details, metrics, and failures are spread across separate UI zones. Reconstructing the run narrative is too manual.

**Minor Observations**

- The centered system-message annotation slices content to 50 characters, which can hide lifecycle context.
- Metadata opacity around `text-base-content/25` and `text-base-content/30` may be too faint for long monitoring sessions.
- Markdown tables may overflow narrow message bubbles unless table containers get explicit horizontal overflow behavior.
- Long filename summaries in clusters can wrap noisily or spill visual attention.
- The raw stream newest/oldest order should be labeled explicitly if it remains visible.

**Questions to Consider**

- Should Codex messages be rendered as chat bubbles with tool decorations, or as a turn timeline where chat is only one event type?
- When a Codex run fails, what is the one fact the operator must see first: failing command, failing turn, last assistant text, or recovery action?
- Is raw JSONL meant as emergency evidence only, or as a supported daily inspection surface?
