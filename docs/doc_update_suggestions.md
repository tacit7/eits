# Documentation Update Suggestions

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
