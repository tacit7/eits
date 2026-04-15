# Documentation Update Suggestions

## 2026-04-14
**Commits reviewed**: cf8107bf..ca2f33b7

- **CODEX_SDK.md** — Document Codex SDK refactoring (commits 75850e7b, 9ddd866d, 1e460048): extract shared `run_codex_session/4` private helper from duplicated start/resume setup; consolidate CLI execution into single closure pattern; clarify `eits_session_id` (EITS session UUID) vs `thread_id` (Codex thread ID) naming; normalize error tuples to consistent `{:error, {type, reason}}` shape across provider handlers
- **REST_API.md** — Document POST `/tasks/:id/complete` endpoint (commit 1d754936): atomic transactional combine of annotate + state update to done; returns task JSON; `eits tasks complete <id>` CLI delegates to this endpoint; enables single-request task finalization in agents
- **CODE_GUIDELINES.md** — Document WorkflowState alias centralization (commit 91503780): extract state alias resolution (`in-review`, `todo`, `review` aliases) into dedicated WorkflowState module function; replaces inline matches in task_controller; enables consistent state-name mapping across API and CLI
- **DM_FEATURES.md** — Document Codex JSONL stream rendering (commit 442b6771): DM messages tab now surfaces raw Codex event stream in collapsible panel (last 100 lines); populated via `Events.broadcast_codex_raw` and `MessageHandler.forward_raw_lines` option; enables real-time debugging of Codex agent execution
- **PERFORMANCE.md** — Document hljs bundle size optimization (commit 1efe9252): switch from full highlight.js (1,014kB) to core-only build registering 6 languages (markdown, json, elixir, bash, yaml, ini/toml); shared `hljs_instance.js` prevents double-import from NotesTab + markdown.js; reduces syntax chunk to 78kB (93% reduction)
- **CODEX_SDK.md** — Document Codex.Models module (commit f2ff4520): new constant map with context_window and max_output_tokens specs per Codex model; enables context budgeting logic and output token prediction in agent handlers
- **CODE_GUIDELINES.md** — Document component extraction patterns (commits c5059ef4, 55bd1808, 8802072e, 273e8776, 8839dff1): extract shared ChatModal from favorite_fab and config_chat_guide; extract file_content_pane shared component; extract GiteaWebhookController with_verified_webhook helper; split advanced_cli_flags into sub-components; update Playwright selectors for dynamic ChatModal-generated IDs; apply pattern when component/helper used 2+ times
- **CODE_GUIDELINES.md** — Document explicit Repo.delete result handling (commit 5b24d576): pattern match on Repo.delete result instead of ignoring; handle both success and error cases explicitly; guard-based Port.close in CLI/port module (catch false clause)
- **CODE_GUIDELINES.md** — Document nil-guard refactoring (commit 1689e86e): replace `condition && nil` with explicit `if condition do nil else value end`; improves readability and prevents missing variable bindings in rescue clauses
- **CODE_GUIDELINES.md** — Document dead code removal (commits a020c835, 70bb7a6e): systematically grep for unused functions before removal; commits 822cf3b and 70bb7a6e removed 12+ unused functions (Accounts, Sessions, Notes, Channels contexts) and AgentPresenter module; validate removal via grep + test suite
- **CODE_GUIDELINES.md** — Document performance index additions (commit 26e93d80): add database indexes on frequently-filtered/joined columns (tasks.agent_id, tasks.archived); measure query impact via ExPlain before/after
- **CODE_GUIDELINES.md** — Document require Logger placement (commit 35692353): move `require Logger` to module scope (above defmodule) instead of inline; enables macro expansion at compile time; applied across chat_live, telemetry_dispatch, cron_parser
- **EITS_CLI.md** — Document worktree CLI commands (commit 22fc1381): new `eits worktree create <name>` and `eits worktree remove` commands; creates isolated git worktree with dynamic deps symlink (../../../) for multi-branch development; documented in CLAUDE.md worktree section
- **CODE_GUIDELINES.md** — Document anti-pattern fixes for Elixir (commits 3d5052af, d621b874, 01436e22): dead module removal (unused .ex files); nested case consolidation (combine cascading case/case into single pattern match); redundant with clause removal (unused :ok clause in with expressions)

## 2026-04-12
**Commits reviewed**: ca015ef..cf8107bf

- **DM_FEATURES.md** — Document async session file sync on DmLive mount (commit 622f567f): defers expensive DB/file operations to connected phase to prevent DB connection timeouts during mount; applies :mounted callback guard pattern documented in elm-like LiveView patterns; prevents "connection timeout" errors on slow systems
- **DM_FEATURES.md** — Document message cache bypass on forced reload (commits 58ca02fb–42607612): message_cache now bypassed when `force_reload_messages` flag set (search clear, manual reload); includes regression test coverage for cache skip paths; explains when cache is safe vs. must be bypassed
- **MOBILE.md** — Document modal bottom-sheet styling pattern (commits fdb7305a–5fe1c364): new_session_modal + agent_list modals now use CSS-driven bottom-sheet layout on mobile; prevents iOS keyboard overlap; coordinates with dm_page responsive height adjustments
- **CODE_GUIDELINES.md** — Document component extraction refactoring (commits 122c0538–09644874): split 340L agent_schedule_form into sub-components; extracted usage_table as generic reusable component (replaced 5 duplicates); extracted sidebar all_projects_section; shows pattern for identifying extraction candidates (>150L template, repeated pattern, mixed concerns)
- **CODE_GUIDELINES.md** — Document MobileNav route mapping (commit 557a0f34): /dm/* routes now map to :sessions controller internally; explains route alias pattern for mobile nav documentation and test alignment
- **PERFORMANCE.md (new file)** — Document lazy-loading strategy (commits f93cc940–57b975c1): sortablejs and marked imports now lazy-loaded via dynamic import; 73% main bundle reduction achieved; explains when to apply lazy-load pattern and event-driven import triggers
- **CODE_GUIDELINES.md** — Document WebSocket origin check pattern (commit 7c6eda4a): allow eits.dev origin via check_origin/1 callback; explain handling of non-same-site WebSocket requests
- **CODE_GUIDELINES.md** — Document Vite module deduplication gotcha (commit 38e75331): Vite __vite_preload deduplicates live_socket.js module between assets and body, causing double init; prevent via explicit script scoping or dynamic import ordering
- **REST_API.md** — Document /api/browser/sessions endpoint (update from 2026-04-02): clarify browser-auth (session cookie) vs. Bearer token usage; when to use /api/browser/sessions for frontend fetch vs. /api/v1/sessions for API clients
- **CODE_GUIDELINES.md** — Document query preload helper pattern (extends 2026-04-10 entry): systematize module-level constants like SESSION_DETAIL_PRELOADS across contexts for DRY preload lists; reference ApiPresenter for consistent applied-everywhere pattern
- **DM_FEATURES.md** — Document full-text search on message bodies (commits 5f14bbb6–973cf0ae): session search now includes message content via FTS; explain search_messages query pattern and sender_role filtering (assistant, user, agent roles supported in FTS scope)

## 2026-04-10
**Commits reviewed**: ca015ef..4cf15dc

- **REST_API.md** — Document GET /sessions/:uuid endpoint (commits 5c9493b, 33b4756): new endpoint returns session detail with recent tasks, notes, commits (limit 5 each), and is_spawned boolean flag; response includes agent_uuid and preloaded related resources; supports both integer ID and UUID resolution
- **CODE_GUIDELINES.md** — Document query preload extraction pattern (commit 4cf15dc): extract repeated preload lists to module constants/helpers (e.g., SESSION_DETAIL_PRELOADS, SESSION_LIST_PRELOADS); improves readability and maintainability; reference ApiPresenter.present_session_detail/2 for example
- **MOBILE.md** — Document 44px touch target standards (commits 2a9b73e, 0e33a0e, 8db8967, 54e3c3b): all mobile touch targets now meet 44x44px minimum via btn-sm/min-h-[44px]/min-w-[44px] Tailwind classes; covers notes actions, dialog close buttons, kanban toolbar actions, input elements text-base sizing to prevent iOS zoom

## 2026-04-07
**Commits reviewed**: ca015ef..f786c5d

- **CODE_GUIDELINES.md** — Document tagged tuple pattern for context functions (commits 625655a, 96ce027, 2827d63, 0949e18, ee3e586, et al): systematic refactoring of Accounts.get_user/1, Projects.get_project/1, Tasks.get_task/1, Notes.get_note/1, Teams.get_team/*, Prompts.get_prompt/1, ChecklistItems functions to return `{:ok, value} | {:error, :not_found}` instead of nil; show pattern with before/after examples; explain caller changes (nil checks → pattern matching); benefits for explicit error handling and call-site clarity
- **NEW: docs/ORCHESTRATOR_TIMERS.md** — Document OrchestratorTimers feature (commits 2193b4c–8a3f530): GenServer with token-correlated session timers, PubSub event broadcast on timer start/cancel, DmLive integration with hamburger menu + schedule modal UI, subscribe/broadcast helpers in Events module, timer event handlers (timer_started, timer_cancelled), timer badge on DM page, database persistence of active_timer, support for resumable sessions
- **CODE_GUIDELINES.md** — Document scheduler context refactoring (commit 9a0bc21): move direct Repo/schema queries out of scheduler modules into dedicated context functions (Agents.list_agents_pending_status_check/0, Agents.archive_agent/2, Sessions.list_idle_sessions_older_than/1, Tasks.active_task_count_for_session/1); remove deprecated Agents.update_agent_status/2 no-op; scheduler now delegates exclusively through contexts
- **CODE_GUIDELINES.md** — Document Projects.get_project_with_agents!/1 helper (commit 0949e18): new context function prevents Repo.preload leakage from web layer into LiveViews; replaces direct preload calls in config.ex, files.ex, notes.ex; centralizes eager-load query logic
- **CODE_GUIDELINES.md** — Document boolean simplification pattern (commit dfc4e8e): remove redundant `== true` boolean comparisons and excessive boolean-tracking assignments; simplify to direct pattern matching and direct boolean fields; applied across LiveView event handlers and helper modules
- **KANBAN.md** — Document sidebar and kanban task improvements (commits a5824f3–eb95482): sidebar task links to kanban with filtered view, kanban toolbar with list view link, deduplicated task_id assigns, KanbanCard helper extraction (resolve_dm_session), consolidated handle_info for agent_working/agent_stopped events, task_detail_drawer and new_agent_drawer integration
- **CODE_GUIDELINES.md or MOBILE.md** — Document mobile layout fixes (commits ab17275–a21fdd0): sticky header offset fixes for mobile nav, min-h-[44px] touch target sizing on sidebar nav/drawers/notifications, consistent viewport alignment with 320px min width, mobile-safe overflow handling in task lists

## 2026-04-03
**Commits reviewed**: 42ae046..7c77b83

- **CODE_GUIDELINES.md** — Document GenServer error handling pattern (commit 5da2e85): explicit try/catch after task/timeout binding prevents variable scope issues in catch clauses; function-level catch creates implicit try that makes inner bindings inaccessible; show example with ShellCommandWorker
- **CODE_GUIDELINES.md** — Document catch :exit pattern for GenServer exits (commit 97c201c): replace `rescue e ->` with `catch :exit, reason` for non-error exceptions in GenServer callbacks; `rescue` in GenServer only catches Exception types, not exit/throw signals
- **CODE_GUIDELINES.md** — Document repository preload extraction (commit 97c201c): move `Repo.preload` calls from web layer LiveViews into context modules (Projects.get_project_with_agents!/1); removes Repo alias from web layer and centralizes query logic
- **CODE_GUIDELINES.md** — Document CLI refactoring: CLI.Port module extraction (commit e9ba9f0): new CLI.Port.cancel_port/2 consolidates SIGTERM/SIGKILL logic (process group + direct PID); both Claude.CLI and Codex.CLI delegate to it, eliminating duplicate kill implementations
- **CODE_GUIDELINES.md** — Document jobs_helpers with_scoped_job/4 pattern (commit e9ba9f0): extract repeated parse_job_id + get_job + scoping_check sequence into private helper; show usage in handle_edit_job, handle_toggle_job, handle_delete_job callbacks
- **CODE_GUIDELINES.md** — Document chat_live channel loading refactoring (commit e9ba9f0): split setup_channel/2 into load_channels/1 (list fetch) + load_channel_data/4 (single channel detail) + setup_channel/2 (socket assign); isolates DB queries from UI state, improves testability
- **NEW: docs/PROJECT_BOOKMARKS.md** — Document project bookmarks feature (commits 46afbb6): schema design (bookmarks table, name/description/url/icon fields), UI component for bookmark management in project config, bulk operations (import/export), and integration with project overview. Reference implementation plans at `.claude/plans/2026-04-03-project-bookmarks.md`
- **CODE_GUIDELINES.md or SETTINGS.md** — Document Autumn DaisyUI theme addition (commit 16ef7d2): new theme option in settings theme selector alongside existing themes; note DaisyUI theme plugin loading in Vite config

## 2026-04-02
**Commits reviewed**: 624313367941bf1280bd1f090c450e2b3d67594a..42ae046

- **CLAUDE.md** — Update API key blocking behavior (commit c3a47c8): ANTHROPIC_API_KEY now blocked in build_env for spawned Claude processes to prevent credit-balance-too-low errors when shell env contains a key with insufficient credits; spawned processes fall through to Max plan OAuth via macOS keychain
- **WORKERS.md or SESSION_MANAGER.md** — Document orphaned Claude process cleanup (commits 29f9684, 5846ebf, 6bf2b26, 428b0c8): AgentWorker now retries failed session starts with `--resume` when "Session ID already in use" error is received; first retry pkill's orphaned processes, second retry fails if orphan kill didn't help (:kill_retry flag prevents infinite retries); covers crash-and-restart scenarios
- **CODE_GUIDELINES.md** — Document chat upload helpers extraction (commit f155e80): ChatLive.UploadHelpers module extracted with functions for file cleanup, accept/reject processing, and attachment presigning; enables test coverage and reuse across upload flows
- **REST_API.md** — Document `/api/browser/sessions` endpoint (commit 76ab752): new browser-authenticated endpoint (session cookie instead of Bearer token) for command palette session list fetches; standard /api/v1/sessions requires Bearer auth which browser fetch cannot provide
- **SETUP.md or PRODUCTION.md** — Document static asset restoration (commits b194105, f25d0de, f7704bd): mockups.html, manifest.json, and sw.js files restored to `.gitignore` after fix; service worker and mockup assets no longer excluded from production builds
- **CODE_GUIDELINES.md** — Document kanban accessibility fix (commit 9738b41): select-all checkbox column now uses data-column-index instead of data-column-handle to prevent drag-handle binding on checkbox element; fixes sorting activation when selecting multiple kanban tasks
- **SETUP.md** — Document Oban Pruner/Stager/Lifeline plugins (commit 804fb9e): Oban config in dev now includes Pruner (clean completed jobs), Stager (enqueue scheduled jobs), and Lifeline (recover crashed job processes) plugins; moved from inline testing mode to normal job processing
- **CODE_GUIDELINES.md** — Document datetime helpers consolidation (commit fa85633): format_relative_time/1 helper now handles both DateTime and NaiveDateTime types via pattern matching; enables consistent relative time rendering across context that returns mixed datetime types
- **CODE_GUIDELINES.md** — Document agent task status fix (commit 523b025): Task.Status enum no longer includes invalid `:error` status; corrected to `:failed` in AgentWorkerEvents; fixes agent status lifecycle tracking
- **CODE_GUIDELINES.md** — Document task timestamp injection (commits d2e90bf, a631a29): create_task and update_task directives now inject timestamps (inserted_at, updated_at) and task UUID directly from EITS-CMD (no DB query); enables proper task lifecycle tracking in agents without waiting for session sync
- **EITS_CLI.md or CODE_GUIDELINES.md** — Document EITS-CMD feedback protocol (commit 73f64bd): all directives now return [EITS-CMD ok] or [EITS-CMD error] messages back to originating session; task_begin returns task_id, team_add returns member_id, spawn returns agent_id; agents must wait for feedback before follow-up commands
- **CODE_GUIDELINES.md** — Document UploadHelpers and message validation (commits 85a4a7f, 5c47d80): palette commands (Create Note, Create Agent, Create Chat) now use LiveView socket instead of HTTP fetch; adds input validation for chat UUID and agent instructions before creation
- **DM_FEATURES.md** — Document message queue bug fixes (commits 1a09115, 91e8d312, 9e8d312): three queue bugs fixed: orphaned file cleanup on message rejection, message reload after rejection, and deterministic deduplication; includes regression tests for message admission flow
- **CODE_GUIDELINES.md** — Document color system unification (commits 233f620-f1f6c0a): all hardcoded oklch/hsl colors replaced with semantic Tailwind classes (text-primary, bg-surface, etc.) and @catppuccin/daisyui theme plugin; enables dark mode and theme switching across auth, chat, date picker, and prompt pages
- **SETUP.md** — Document Vite dev server port configuration (commit 2907189, 8686abb): VITE_PORT env var now configurable (default 5173); when running multiple worktrees, use different ports (e.g., VITE_PORT=5174 PORT=5002) to avoid asset conflicts; documented worktree workflow in CLAUDE.md
- **CODE_GUIDELINES.md** — Document markdown syntax highlighting fix (commit 426cd7c): CodeMirror 6 markdown editor now includes defaultHighlightStyle fallback for proper syntax highlighting; prevents syntax loss in note editors across all CM hooks
- **CODE_GUIDELINES.md** — Document vim keybindings and CM settings (commits 56d604c, 783bd91, 228f0f2, 52c5fde, a02b82f, dd01560): CodeMirror now supports user-configurable tab size, font size, and vim mode toggles via Settings; persisted in localStorage via CM user settings section
- **REST_API.md** — Document numeric session ID resolution (commit ee6cacc): dm --to now accepts both UUID and integer session ID; enables agents to use simpler EITS_SESSION_ID env var instead of full UUID for DM targeting
- **CODE_GUIDELINES.md or DM_FEATURES.md** — Document command palette improvements (commits 672f73e, d4c298a, 80f294d): command palette now includes comprehensive agent management, server-side session flags (from CLI flags), and deduplicated SQL fragments for task title queries
- **DM_FEATURES.md** — Document multimodal content blocks (commits baa1bf9, 9391dd8, b90e4c4, 85edb0e, 214e6c0): new ContentBlock foundation with provider-aware pipeline; content_blocks JSON piped to Claude CLI stdin; handles image preprocessing (resize, compress, EXIF normalization) with model capability enforcement

## 2026-04-01
**Commits reviewed**: ca015ef..d70a166

- **CODE_GUIDELINES.md** — Document context function pattern for SQL queries: Messages.list_inbound_dms/2 and Teams.list_broadcast_targets/1 extract inline Ecto.Query from CmdDispatcher; explain when to move query logic to context modules (reusability, testability, separation of concerns); note secondary sort stability in list_inbound_dms (desc: m.id) for deterministic ordering
- **CODE_GUIDELINES.md** — Document ViewHelpers.parse_budget/1 as canonical budget parsing implementation; previously duplicated in ChatLive and AgentLive.Index; explain import pattern to avoid code duplication across LiveView modules
- **SETUP.md** — Document Oban configuration change: removed inline testing mode from dev.exs; scheduled jobs now run normally in development (cron plugin enabled); previously disabled with `testing: :inline` flag

## 2026-03-29 (Updated)
**Commits reviewed**: f233620..c4c2112

- No new feature suggestions. Recent commits are documentation-only:
  - c4c2112: Added DEBUG_VITE_LIVEVIEW.md with diagnostic steps for "Cannot bind multiple views" prod build errors
  - dce9e53: Updated PRODUCTION.md with SECRET_KEY_BASE persistence notes

## 2026-03-29
**Commits reviewed**: 624313367941bf1280bd1f090c450e2b3d67594a..87ae294

- **DM_FEATURES.md or CODE_GUIDELINES.md** — Document CmdDispatcher error surfacing: notify_error/3 now creates persistent notifications (toast UI, sidebar badge) and DMs errors back to originating agent session instead of bare logging; applies to dm, task create/begin, and spawn directives; enables agents to react to dispatch failures in real-time

## 2026-03-28
**Commits reviewed**: 624313367941bf1280bd1f090c450e2b3d67594a..f967b6d

- **CODE_GUIDELINES.md** — Document CodeMirror 6 integration on project config and files pages: replace Highlight syntax highlighting with CodeMirror editor (ProjectLive.Files, ProjectLive.Config); Cmd+S save handler with path traversal guard; cm_language/1 helper for language detection; editor remount keyed on file path hash
- **SECURITY.md or CODE_GUIDELINES.md** — Document path traversal hardening: FileHelpers.safe_realpath/1 resolves symlinks via system realpath; FileHelpers.path_within?/2 replaces all starts_with? guards across files.ex/config.ex/overview config.ex; trailing "/" appended to root before comparison; symlink escape prevention via realpath resolution before path check
- **WORKERS.md or SESSION_MANAGER.md** — Document SDK process cleanup: do_handle_sdk_error now calls strategy.cancel(sdk_ref) before clearing the ref to kill orphaned Claude CLI processes on handler crash; prevents indefinite background process accumulation
- **CODE_GUIDELINES.md** — Document sidebar UI improvements: docked project panel expanded on folder click; redundant project name header removed from docked panel; persistent section state across navigation (SidebarState JS hook)

## 2026-03-26
**Commits reviewed**: 624313367941bf1280bd1f090c450e2b3d67594a..9a92b45

- **NEW: docs/CANVAS_OVERLAY.md** — Document floating session windows feature: Canvas/CanvasSession schemas (`lib/eye_in_the_sky_web/canvases.ex`), CanvasOverlayComponent with drag/resize/z-index handling, ChatWindowComponent, WebSocket state sync via agent_updated/session_updated PubSub events, chat_window_hook.js for client-side state management, position/size persistence in CanvasSession records. Include UI pattern for floating windows and z-index stacking.
- **CLAUDE.md or ARCHITECTURE.md** — Document OTP app rename: `eye_in_the_sky_web` → `eye_in_the_sky` (commit 554da58). Update import statements and supervision tree references if documented separately.
- **SETUP.md** — Update default port documentation: application now defaults to port 5001 (was 5000); document PORT env var override (5001-5020 range) and MCP server endpoint moved to `http://localhost:5001/mcp` (Anubis server).
- **CLAUDE.md** — Document timestamp field migration: all tables now use `:utc_datetime_usec` type (migrations 20260321080000-080200). Previously mixed datetime/timestamp types; clarify that queries should use `DateTime.utc_now()` and comparisons with ISO8601 strings via `DateTime.from_iso8601/1`.
- **CLAUDE.md or ARCHITECTURE.md** — Document UUID column migration: varchar UUID columns converted to native Postgres `uuid` type (migration 20260322011755). Include source_uuid field addition and impact on Ecto.UUID codec usage; update example queries.
- **NEW: docs/AGENT_DEFINITIONS.md** — Document agent definition tracking system: AgentDefinitions context for scanning `.claude/agents/` files, AgentDefinition schema (project_id, scope, filepath, frontmatter parsing), auto-sync on agent spawn when slug not found in DB, YAML list parser for agent lists, scope/project_id constraints, and advisory locks for sync race conditions.
- **CODE_GUIDELINES.md** — Document UI component improvements: session_card component refactoring with action dropdown menu (replace icon buttons), click propagation guards on edit forms (stop rename form clicks from triggering row navigation), stream_insert re-render behavior in session lists.
- **SETUP.md** — Document VAPID_PRIVATE_KEY requirement for web push; note migration of key from config/config.exs to runtime.exs environment variables.
- **EVENTS.md** — Add documentation for canvas-related PubSub events: agent_updated/session_updated broadcasts that sync floating window state across clients.

## 2026-03-20
**Commits reviewed**: cdb8acd..6243133

- **CODE_GUIDELINES.md**: Document new module extractions from recent refactoring: ProviderStrategy (`lib/eye_in_the_sky_web/claude/provider_strategy.ex`) with provider implementations (Claude, Codex); ChatPresenter (`lib/eye_in_the_sky_web_web/live/chat_presenter.ex`) for extracted chat logic; WorkflowStates, TaskTags, ChecklistItems contexts extracted from Tasks (`lib/eye_in_the_sky_web/workflow_states.ex`, `lib/eye_in_the_sky_web/task_tags.ex`, `lib/eye_in_the_sky_web/checklist_items.ex`)
- **CODE_GUIDELINES.md** or **WORKERS.md**: Document JobsHelpers module consolidation: `lib/eye_in_the_sky_web_web/live/shared/jobs_helpers.ex` now contains unified `create_with_claude/2` and `save_job/2` logic (replaces duplicate implementations in OverviewLive.Jobs and ProjectLive.Jobs); explain when to use JobsHelpers vs direct context calls
- **KANBAN.md** or **CODE_GUIDELINES.md**: Document Trello-style kanban card dropdown menu for task actions (replace task copy/delete buttons with "..." menu); include UI pattern for mobile/desktop action menus
- No breaking API changes in these commits; refactoring is internal module organization only

## 2026-03-18
**Commits reviewed**: 435f772..cdb8acd

- **CODE_GUIDELINES.md**: Update module location references: AgentManager moved from `lib/eye_in_the_sky_web/claude/agent_manager.ex` to `lib/eye_in_the_sky_web/agents/agent_manager.ex`; document new modules InstructionBuilder, RuntimeContext, and Git.Worktrees with their responsibilities
- **WORKERS.md** or **SESSION_MANAGER.md**: Document agent state lifecycle transitions: `:pending` (on :queued/:retry_queued admission) → `:running` (on SDK :started event) → `:failed` (on dispatch error); explain promote_agent_if_pending synchronous execution requirement for test sandbox safety
- **WORKERS.md** or **SESSION_MANAGER.md**: Document worktree handling improvements: worktree reuse on repeated prepare calls, untracked file filtering in dirty check (git status --porcelain with ?? filter), and Git.Worktrees module structure
- **REST_API.md**: Update DM endpoint docs: POST /api/v1/dm now accepts from_session_id/to_session_id (int FK) instead of sender_id/target_session_id; legacy params still supported for backward compatibility
- **EITS_HOOKS.md** or **CHAT.md**: Document eits-dm skill for agents: teaches DM parsing of "DM from:<name> (session:<uuid>) <body>" format and reply flow via eits dm CLI; update eits CLI docs to show --from defaults to $EITS_SESSION_UUID
- **CHAT.md**: Update typing indicator docs; clarify that ambient messages no longer trigger agent responses (only @direct and @all do); document per-channel sequential message numbering with backfill migration
- **REST_API.md**: Add GET /api/v1/channels/:channel_id/messages endpoint documentation with pagination and CLI support via eits cli
- **SESSION_MANAGER.md**: Document "stopped" session status (set by Stop hook, displays yellow left bar); clarify that "completed" status is now set explicitly via i-end-session skill (not auto-set on CLI exit)
- **CODE_GUIDELINES.md** or **DM_FEATURES.md**: Document Quick Note modal and New Note CodeMirror editor: title/body textarea in modal, inline CodeMirror editor with Cmd+S save handler, parent_type resolution (system vs project), and InlineNoteCreatorHook JS integration
- **CODE_GUIDELINES.md**: Document new Opus 4.6 1M model and Sonnet 4.5 1M addition to claude_models(), model_display_name helpers, and max effort option availability across all forms (DM page, agent drawer, session modal, jobs)
- **CODEX_SDK.md**: Document restored Codex streaming pipeline: CodexStreamAssembler module for provider-polymorphic stream dispatch; provider-aware avatar/label in DM UI; stream_thinking assign for UI display
- **SECURITY.md**: Document API key rotation system: api_keys table (key_hash, label, valid_until), HMAC-SHA256 hashing in hash_token/1, RequireAuth plug validation via valid_db_token?/1, eits.gen.api_key mix task integration, and backward compatibility with EITS_API_KEY env var
- **SECURITY.md**: Document server-side session expiry: user_sessions table (uuid pk, session_token unique, expires_at), ValidateSession plug in :browser pipeline, 7-day TTL, and session token cookie handling
- **UI_IMPROVEMENTS.md**: Document DM page textarea scroll fix for max-height input fields; kanban card accessibility fix (exclude interactive elements from SortableJS drag)

## 2026-03-17
**Commits reviewed**: 569410e..435f772

- **REST_API.md**: Remove deleted endpoints `/dev/test-login` and `/api/v1/editor/open` from endpoint listings; update webhook handler docs for new Gitea signature format handling (both 'sha256=<hex>' and raw hex headers)
- **SECURITY.md**: Document SessionAuth plug (session-cookie based auth for /oban and /dev/dashboard instead of RequireAuth); add API key validation behavior change in RequireAuth (rejects all traffic in prod if EITS_API_KEY unset, allows passthrough in dev); document webhook signature verification now rejects unsigned requests by default (configurable via allow_unsigned_webhooks flag in dev)
- **SETUP.md**: Add VAPID_PRIVATE_KEY to required environment variables section (moved from config/config.exs to runtime.exs); document allow_unsigned_webhooks dev config flag for webhook testing; add RemoteIp proxy configuration for Tailscale CGNAT range (100.64.0.0/10) and X-Forwarded-For rewriting
- **REST_API.md**: Document POST /api/v1/dm rate-limiting: 30 requests/min per sender_id via Hammer; add error response code (429 Too Many Requests) for rate-limit violations
- **CLAUDE.md**: Update module name references: PgSearch (formerly FTS5 in search/), AgentWorkerEvents (formerly WorkerEvents in claude/); both updated in existing commit
- **DM_FEATURES.md**: Document DmLive mount structure refactoring: single with chain (previously 3-level delegation); document active_overlay atom-based state management replacing 5 boolean assigns (effort_menu, model_menu, task_drawer, task_detail, checkpoint); note overlay state controls 5 drawer/menu components
- **REST_API.md**: Document webhook controller improvements: repository.full_name validation returns 400 if missing (no 'claude/eits-web' fallback); project_path validation returns 500 if not configured (no File.cwd!() fallback); signature comparison handles both new and legacy header formats
- **CODE_GUIDELINES.md**: Document agent context typespecs additions to Agents, Sessions, Messages contexts (public function @spec annotations); note Keyword.filter pattern usage in optional parameter handling (build_instructions/1, start_claude_sdk/2)

## 2026-03-16
**Commits reviewed**: 0fae369..6b55196

- Document MCP server removal: all MCP tools (`spawn_agent`, `send_message`, `todo`, `team_*`, etc.) must now use REST API endpoints (`POST /agents`, `POST /messages`, `/tasks`, `/teams`)
- Update REST_API.md: add POST `/agents` spawn validation pipeline, structured error response codes, status endpoint `/agents/:id/status`
- Add AgentWorker queue management docs: max queue depth (5), retry logic (exponential backoff 1s-30s), max retries (5), queue overflow handling
- Document DM endpoint audit: validation improvements, error handling, status code standardization (201 Created, 400 Bad Request, 404 Not Found, 409 Conflict)
- Document agent worker refactors: ETS registry (replace Agent-based), `current_job` struct, stream buffer management, queue persistence patterns
- Add CodeMirror 6 LiveView hook documentation: language detection, Cmd+S save handler, syntax highlighting integration for inline note editor
- Document inline note editor component: CodeMirror wrapper, save/cancel handlers, parent_type validation, edit mode state management
- Add settings page redesign docs: tabbed layout (settings, config guide), CodeMirror editor preference, EITS_WORKFLOW toggle for hook disable, preferred_editor persistence
- Document auth refactoring: browser auth vs API auth separation, new auth tables (User, Passkey, RegistrationToken), DISABLE_AUTH env var for dev
- Add swipe actions documentation: mobile session list right-swipe for archive/rename, SwipeRow JS hook, editing_session_id state tracking
- Document teams mobile template: responsive grid layout, progress tracking, task links, archived toggle, mobile_view state tracking
- Add config guide chat handler docs: FabHook integration, ConfigChatGuide JS hook, chat button behavior, messaging flow to DM page
- Document spawn endpoint improvements: validation helpers, structured error codes, rollback behavior on failure, name field validation
- Add session list improvements: session name/description as independent fields, atomic task-session linking, session intent field (text type)
- Document Codex tool changes: deprecated tools removed (spawn_agent, etc.), REST API migration complete

## 2026-03-12
**Commits reviewed**: b02aafb..1b8fce0

- Document Gitea webhook handler for PR review automation: HMAC auth setup (GITEA_WEBHOOK_SECRET env var), webhook event types, PR diff generation flow, and failing closed in production
- Add PWA and Web Push support documentation: manifest.json, service worker configuration (sw.js), push subscription API endpoints, browser permissions, and client setup in push_notifications.js
- Update EITS hook scripts documentation: eits-session-end.sh new lifecycle hook, expanded eits-session-startup.sh capabilities, and todo checking logic in check-active-todo.sh
- Document DM page overhaul features: usage dashboard, agent queue management, new_agent_drawer/new_task_drawer improvements, and agent state lifecycle display
- Update architecture docs on context safety: atom conversion safeguards in parser.ex, Tasks context refactoring (safe attribute updates), and kanban LiveView state boundary improvements
- Add REST_API.md sections: push subscription endpoints (POST/GET /api/v1/push/subscriptions), gitea webhook endpoint, and notification trigger payloads
- Document workable task worker improvements: GenServer crash handling for invalid task_ids, safe project lookup patterns, and worker state management

## 2026-03-11
**Commits reviewed**: e7f897e..b02aafb

- Document WebAuthn/passkey authentication (new Accounts context: User, Passkey, RegistrationToken schemas; auth controller, auth LiveView, require_auth plug, passkey_auth.js hook)
- Add passkey setup/registration flow docs and wax_ dependency reference in ARCHITECTURE.md
- Document port configuration change: HTTPS on 5001, HTTP on 5000
- Update MCP_TOOLS.md with new agent control tools: i-agent-cancel (terminate), i-agent-send (send messages), i-agent-status (check state)
- Document enhanced i-spawn-agent tool: new provider, project_id, worktree, effort_level parameters; now returns agent_id + session_id
- Add parent_agent_id and parent_session_id fields to Agents and Sessions schema docs; explain cascading relationships
- Document session status broadcasts via PubSub topic `session:<id>:status` (emitted on start/idle/terminate/queue_full events)
- Document "Create with Claude" feature on project jobs page (model + effort_level selection, spawns agent to DM view)
- Add git post-commit hook integration docs: eits-post-commit.sh POSTs commit hash+message to `/api/v1/commits`, symlinked to .git/hooks/post-commit
- Document LocalTime LiveView hook for client-side timezone rendering; remove hardcoded locale from datetime formatters (use system locale)
- Document task UUID vs integer ID lookup behavior; explain get_task_by_uuid_or_id! fallback in Tasks context
- Update REST_API.md: document POST `/api/v1/notifications` endpoint (NotificationController)
- Document total_tokens_for_session field on messages; wire into DM page token count display
- Document auto-scroll hook and eits.register mix task

## 2026-03-10
**Commits reviewed**: a2efe06..86af5ba

- Add notifications system documentation: new Notifications context (notify, mark_read, mark_all_read, purge_old) and `/api/v1/notifications` endpoints in REST_API.md
- Document i-notify MCP tool (categories: agent/job/system, resource linking, PubSub broadcasting) in MCP_TOOLS.md
- Update MCP_TOOLS.md to reflect removed tools: i-nats-send, i-nats-listen, i-nats-send-remote, i-nats-listen-remote, i-nats-spawn-claude
- Document MCP.Tools.Helpers module for shared session ID resolution across MCP tools
- Add SessionStore 24h TTL cleanup implementation to ARCHITECTURE.md or MCP_TOOLS.md
- Document i-todo fixes: project_id auto-resolution, tag linking via task_tags join table, remove-session and add-session-to-tasks commands
- Document Agents context PubSub broadcasting to "agents" topic for real-time updates in agent listings
- Add JobHelper and WorkableTaskWorker to WORKERS.md (auto-job processing for workable tasks)
- Update /notifications LiveView features (category filters, mark read inline, resource links, unread count badge)

## 2026-03-09
**Commits reviewed**: a2efe06..da77068

- Add API documentation for new `/api/v1/jobs/*` endpoints (GET jobs, POST/DELETE job assignments) in REST_API.md
- Document scheduled jobs system architecture (ScheduledJob schema, job_dispatcher_worker, daily_digest_worker) in new docs/SCHEDULED_JOBS.md
- Update REST_API.md with JobController endpoints for job listing, assignment, and metrics retrieval
- Document DM file upload feature (drag-and-drop, attachment handling) in docs/DM_FEATURES.md
- Add worker process documentation for JobDispatcherWorker and DailyDigestWorker in docs/WORKERS.md
- Update CLAUDE.md with details on PostgreSQL shell scripts location (priv/scripts/sql/postgresql/) and migration from SQLite
- Document new LiveViews (overview/jobs, project/jobs) endpoints and capabilities
- Add PostgreSQL-specific notes to CLI scripts documentation (i-project, i-prompt)

## 2026-03-15
**Commits reviewed**: 1b8fce0..0fae369

- Add FTS5.fts_name_description_match/1 helper documentation: explains tsvector query extraction pattern, usage across sessions/tasks/notes search, and performance implications
- Update QueryBuilder docs: field name validation in maybe_where/3 to prevent SQL injection, validation strategy, and allowed field patterns
- Expand CommandPalette documentation: new CommandRegistry with command definitions, stack-based navigation for submenus, fuzzy matching algorithm, breadcrumb UX, and command organization patterns
- Document Command Palette features: Go to Session submenu (async fetch), project-scoped filtering, quick-create commands (new-agent, new-chat, create-note, create-task), and search threshold behavior
- Update Session docs: last_activity_at ordering and filtering behavior, ISO8601 string standardization in Agents context, session sorting by created and last message capabilities
- Add Agent last_activity_at migration notes: schema change from datetime to ISO8601 text format (migration 20260309000001), update scheduling logic in agent_status.ex, and query patterns for datetime comparisons
- Document DM page improvements: mobile-optimized top bar (Claude-style minimal design), tab navigation in mobile overflow menu, removal of token counter and thinking toggle, periodic_sync loop lifecycle management
- Update Session card component documentation: shared session_card component usage across different pages (agent_live/index, project sessions), status indicator styling (colored left border accent), and mobile responsiveness fixes
- Document Kanban search improvements: lowered threshold to 2 characters, search hint text, and removal of WIP limit display
- Add mobile UI improvements documentation: FAB (floating action button) navigation to DM page, dark mode code block rendering fixes, and string timestamp handling in session filters


## 2026-04-11
**Commits reviewed**: 4cf15dc..ef512001

- **EITS_CLI.md** — Already updated (commit ef512001): session search, list filters, sessions tasks/notes, notes search, commits --session, and sessions show rich response now documented with examples
- **MOBILE.md** — Document session action menu UX pattern change (commits 14d199c, 73df7b61): replaced mobile swipe panel with persistent dropdown menu for session actions (archive, rename, delete); dropdown hidden on mobile for space efficiency; pattern applicable to other mobile action menus
- **CODE_GUIDELINES.md** — Document Elixir idiom improvements (commits c7091a8, ebc9751d, 4215866c, 5a5117f0, c332ca9, 41adbeb, 3e84d2b, d7876e3f, 9b8f442a, 2dab6e95, 78340e23, ec5ad9da, f0af2836, dc0beccc, 274ac700): systematic refactoring across 37+ commits includes (r37 through r23):
  - Replace `!is_nil()` with `not is_nil()` (Elixir standard negation operator)
  - Replace `== nil`/`!= nil` with `is_nil()/not is_nil()` for clarity
  - Replace `length(list) > 0` with `list != []` (O(1) vs O(n) performance, idiomatic check)
  - Replace inline SVGs with `<.icon>` Heroicons component (consolidates icon library)
  - Replace boolean nil-guards (`&&`) with explicit `not is_nil()` or `if` expressions in LiveView handlers/components
  - Fix bare `_ -> catch-alls` in `with/else` clauses to `{:error, _}` for explicit error handling
  - Simplify `{:ok, x}` pattern matches with direct value assignment when error path irrelevant
- **WORKERS.md or SESSION_MANAGER.md** — Document AgentWorker idle timeout (commit d74450ce): new IdleTimer module tracks worker idleness, auto-terminates stale workers after timeout to prevent max_children exhaustion under load; includes error recovery integration

## 2026-04-13
**Commits reviewed**: cf8107bf..472a2dff

- **DM_FEATURES.md** — Document DM timer countdown UI enhancements: timer display in DM schedule modal, countdown timer component (timer_countdown.js hook), pre-fill feature for schedule editing, and new timer settings in general tab
- **COMMAND_PALETTE.md** — Document command palette improvements: shortcut modifier key configuration (Settings > General), keyboard navigation optimizations (arrow-key optimizations), c-k reassignment from tasks to palette
- **SECURITY.md or AUTH.md** — Document auth_controller hardening against 4 security bugs: decode_b64url crash protection, challenge reuse validation, sign_count validation, and session matching error handling; include test patterns from auth_controller_test.exs
- **REFACTORING_PATTERNS.md or COMPONENT_ARCHITECTURE.md** — Document FileBrowserHelpers helper extraction pattern: consolidate duplicate file-browser logic from 3 LiveViews (overview/config, project/config, project/files) into shared module; include test patterns for helper-extracted modules
- **CODE_PATTERNS.md** — Document form component refactoring pattern from advanced_cli_flags: replace multi-attribute prop drilling (13+ attrs) with config map, reduces component complexity and improves maintainability
- **WORKERS.md** — Update worker error handling documentation: atomic job claiming patterns, type validation for args (MixTaskWorker, SpawnAgentWorker), strict float parsing, endpoint URL validation in SpawnAgentWorker
- **REST_API.md** — Update push subscription API documentation: authentication requirement (JSON 401 on unauthenticated requests), routes in browser-session pipeline, broadcast patterns for push_subscriptions
- **API_LIMITS.md or DM_FEATURES.md** — Document DM message limit increase: raised from default to 50 messages per fetch, includes id tiebreaker sort for pagination stability
- **WEBHOOK_HANDLING.md** — Document Gitea webhook controller support for pull_request synchronize action (in addition to opened action)
- **PATH_VALIDATION.md** — Document path_within? security improvements: safe_realpath usage, trailing-slash guard, sibling-prefix validation, and test coverage patterns
