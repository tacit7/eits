# Documentation Update Suggestions

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
