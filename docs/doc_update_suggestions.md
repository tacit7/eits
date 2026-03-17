# Documentation Update Suggestions

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
- Update MCP_TOOLS.md to reflect removed tools: i-nats-send, i-nats-listen, i-nats-send-remote, i-nats-listen-remote, i-spawn-claude
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
