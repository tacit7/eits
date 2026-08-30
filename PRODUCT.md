# Product

<!-- impeccable:product-schema 1 -->

## Platform

web

## Users

EITS is for developers and agent operators who run AI coding agents across one or more local projects and need to supervise active work without living inside every terminal. Primary users are people coordinating sessions, tasks, direct messages, team workers, hooks, jobs, and policy decisions while agents are actively editing code.

## Product Purpose

Eye in the Sky is a Phoenix/LiveView operator console for AI coding work. It tracks agent sessions, project tasks, notes, commits, direct messages, channels, teams, jobs, prompts, token usage, and IAM decisions in real time so humans and agents can see what is happening, coordinate follow-up, and preserve an auditable work trail.

Success means a user can quickly answer which agents are active, what each one is doing, whether anything needs attention, and what happened during a task without reconstructing state from scattered shell logs, chat transcripts, or git history.

## Positioning

EITS is not only a passive session viewer. Its distinguishing mechanism is a local orchestration layer that combines live Phoenix views, REST APIs, project hooks, task workflow, DM/chat coordination, team spawning, IAM guardrails, and agent-facing skills into one operational system for coding agents.

## Operating Context

The product runs as a local web application alongside coding-agent harnesses and project worktrees. Codex, Claude, Pi, Gemini, and related agent integrations report lifecycle events, tool activity, messages, tasks, commits, and job status through hooks, APIs, and CLI workflows.

Core workflows include monitoring live sessions, opening project task boards, reviewing notes and commits, sending or receiving DMs, coordinating agent teams, managing prompt/skill records, viewing background jobs, inspecting usage, configuring project settings, and evaluating IAM policies before risky tool actions.

## Capabilities and Constraints

The application is built with Phoenix 1.8, LiveView, Svelte through live_svelte, Tailwind CSS v4, Oban, PostgreSQL-backed Ecto schemas, and a REST API under `/api/v1`.

The interface includes overview and project-specific routes for sessions, tasks, kanban, notes, files, agents, jobs, teams, skills, prompts, chat, canvases, terminal views, notifications, settings, usage, keybindings, bookmarks, and IAM policy simulation.

Agent-facing behavior is part of the product: hooks and skills must preserve EITS lifecycle tracking, task-state requirements, direct-message handling, commit logging, and IAM guard behavior. Future UI work must not obscure required operational states such as active, idle, waiting, stale, failed, blocked, or completed.

Open decision: the exact public-facing product name and distribution posture should be confirmed before marketing or landing-page work. The repository uses both "Eye in the Sky" and "EITS"; internal operator UI can use EITS where density matters.

## Brand Commitments

The established product name is Eye in the Sky, commonly abbreviated as EITS. The voice should be operational, precise, and calm: status-first, direct about failures, and oriented toward actionable next steps rather than marketing language.

The product identity should preserve the feeling of a serious control room for software agents: dense enough for repeated use, readable under load, and explicit about system state.

## Evidence on Hand

Available evidence includes [README.md](/Users/urielmaldonado/projects/eits/web/README.md), the Phoenix router at [lib/eye_in_the_sky_web/router.ex](/Users/urielmaldonado/projects/eits/web/lib/eye_in_the_sky_web/router.ex), API and workflow docs under [docs/](/Users/urielmaldonado/projects/eits/web/docs), generated module docs under [doc/](/Users/urielmaldonado/projects/eits/web/doc), and existing LiveView/component implementations under [lib/eye_in_the_sky_web/](/Users/urielmaldonado/projects/eits/web/lib/eye_in_the_sky_web).

No confirmed customer names, public testimonials, benchmarks, pricing, or external proof claims are available in the repository context. Future work must not fabricate those.

## Product Principles

1. Show current operational state before decorative context.
2. Make agent work traceable from task to session to messages, commits, and tool activity.
3. Keep human intervention paths obvious when an agent is blocked, waiting, risky, or failed.
4. Favor compact, scannable product UI over landing-page theatrics inside the operator console.
5. Preserve auditability and policy clarity when improving speed or visual polish.

## Accessibility & Inclusion

The operator UI should support long monitoring sessions, fast scanning, keyboard-accessible workflows, clear focus states, and readable contrast for status-heavy screens.
