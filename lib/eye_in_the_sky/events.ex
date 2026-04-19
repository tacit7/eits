defmodule EyeInTheSky.Events do
  @moduledoc """
  Centralized PubSub interface for EyeInTheSky.

  All Phoenix.PubSub broadcast and subscribe calls go through this module.
  No other module should call Phoenix.PubSub directly.

  ## Topics

  | Topic                          | Subscribers                       |
  |--------------------------------|-----------------------------------|
  | `"agents"`                     | Sidebar, DMLive, session pages    |
  | `"agent:working"`              | ChatLive, DMLive                  |
  | `"session:<id>"`               | DMLive, FloatingChatLive          |
  | `"session:<id>:status"`        | DMLive                            |
  | `"dm:<id>:stream"`             | DMLive                            |
  | `"dm:<id>:queue"`              | DMLive                            |
  | `"channel:<id>:messages"`      | ChatLive                          |
  | `"tasks"`                      | Overview, DMLive                  |
  | `"tasks:<project_id>"`         | Kanban                            |
  | `"notifications"`              | FloatingChatLive                  |
  | `"teams"`                      | TeamLive                          |
  | `"settings"`                   | OverviewSettings                  |
  | `"scheduled_jobs"`             | JobsLive                          |
  | `"session_lifecycle"`          | Teams.Subscriber                  |
  | `"projects"`                   | Sidebar                           |
  | `"session:<id>:timer"`         | DMLive                            |
  | `"canvas:<id>"`                | CanvasLive                        |

  ## Payload shape for `agent:working`

  All callers use the single-struct form:
  - `{:agent_working, %Session{}}` — agent transitioned to working state
  - `{:agent_stopped, %Session{}}` — agent transitioned to idle/stopped state
  """

  @pubsub EyeInTheSky.PubSub

  # ---------------------------------------------------------------------------
  # Subscribe helpers
  # ---------------------------------------------------------------------------

  @doc "Subscribe to agent lifecycle events (created/updated/deleted)."
  def subscribe_agents, do: sub("agents")

  @doc "Subscribe to agent working/stopped status transitions."
  def subscribe_agent_working, do: sub("agent:working")

  @doc "Subscribe to task list changes."
  def subscribe_tasks, do: sub("tasks")

  @doc "Subscribe to project-scoped task changes."
  def subscribe_project_tasks(project_id), do: sub("tasks:#{project_id}")

  @doc "Subscribe to session-scoped events (messages, tool use, CLI output)."
  def subscribe_session(session_id), do: sub("session:#{session_id}")

  @doc "Subscribe to session status string changes."
  def subscribe_session_status(session_id), do: sub("session:#{session_id}:status")

  @doc "Subscribe to orchestrator timer events for a session."
  def subscribe_session_timer(session_id), do: sub("session:#{session_id}:timer")

  @doc "Subscribe to real-time stream deltas for a session."
  def subscribe_dm_stream(session_id), do: sub("dm:#{session_id}:stream")

  @doc "Subscribe to queued-prompt updates for a session."
  def subscribe_dm_queue(session_id), do: sub("dm:#{session_id}:queue")

  @doc "Subscribe to raw Codex JSONL stream lines for a session."
  def subscribe_codex_raw(session_id), do: sub("codex:#{session_id}:raw")

  @doc "Broadcast a raw Codex JSONL line for a session."
  def broadcast_codex_raw(session_id, line),
    do: broadcast("codex:#{session_id}:raw", {:codex_raw_line, line})

  @doc "Subscribe to new messages on a channel."
  def subscribe_channel_messages(channel_id), do: sub("channel:#{channel_id}:messages")

  @doc "Subscribe to notification events."
  def subscribe_notifications, do: sub("notifications")

  @doc "Subscribe to team/member events."
  def subscribe_teams, do: sub("teams")

  @doc "Subscribe to project metadata changes (bookmark toggled, etc.)."
  def subscribe_projects, do: sub("projects")

  @doc "A project record was updated. Broadcasts to projects topic."
  def project_updated(project), do: broadcast("projects", {:project_updated, project})

  @doc "Subscribe to settings changes."
  def subscribe_settings, do: sub("settings")

  @doc "Subscribe to scheduled job status updates."
  def subscribe_scheduled_jobs, do: sub("scheduled_jobs")

  @doc "Subscribe to session lifecycle transitions (idle, completed, etc.)."
  def subscribe_session_lifecycle, do: sub("session_lifecycle")

  # ---------------------------------------------------------------------------
  # Session events — required initial set
  # ---------------------------------------------------------------------------

  @doc "Session was created and started. Broadcasts to agents topic."
  def session_started(session), do: broadcast("agents", {:agent_updated, session})

  @doc "Session record was updated. Broadcasts to agents topic."
  def session_updated(session), do: broadcast("agents", {:agent_updated, session})

  @doc "Claude CLI output chunk received for a session."
  def session_output(session_id, session_ref, parsed) do
    broadcast("session:#{session_id}", {:claude_response, session_ref, parsed})
  end

  @doc "Session completed (CLI exited). Broadcasts stopped status."
  def session_completed(session), do: broadcast("agents", {:agent_stopped, session})

  @doc "Session failed. Broadcasts stopped status."
  def session_failed(session, _reason), do: broadcast("agents", {:agent_stopped, session})

  # ---------------------------------------------------------------------------
  # Tool approval events — required initial set (topic: TBD when implemented)
  # ---------------------------------------------------------------------------

  @doc "Tool approval requested."
  def tool_approval_requested(approval),
    do: broadcast("tool_approvals", {:approval_requested, approval})

  @doc "Tool approval decision recorded."
  def tool_approval_updated(approval),
    do: broadcast("tool_approvals", {:approval_updated, approval})

  @doc "Subscribe to tool approval events."
  def subscribe_tool_approvals, do: sub("tool_approvals")

  # ---------------------------------------------------------------------------
  # Task events — required initial set
  # ---------------------------------------------------------------------------

  @doc "Task was created, updated, or deleted. Broadcasts to both global and project-scoped topics."
  def task_updated(task) do
    broadcast("tasks", :tasks_changed)

    if task.project_id do
      broadcast("tasks:#{task.project_id}", :tasks_changed)
    end
  end

  @doc "Tasks changed (no specific task). Global broadcast only."
  def tasks_changed, do: broadcast("tasks", :tasks_changed)

  # ---------------------------------------------------------------------------
  # Agent identity events — topic: "agents"
  # ---------------------------------------------------------------------------

  @doc "Agent identity record created."
  def agent_created(agent), do: broadcast("agents", {:agent_created, agent})

  @doc "Agent identity record updated."
  def agent_updated(agent), do: broadcast("agents", {:agent_updated, agent})

  @doc "Agent identity record deleted."
  def agent_deleted(agent), do: broadcast("agents", {:agent_deleted, agent})

  # ---------------------------------------------------------------------------
  # Agent working status — topic: "agent:working"
  # ---------------------------------------------------------------------------

  @doc "Agent transitioned to working state. Broadcasts `{:agent_working, session}` on `agent:working`."
  def agent_working(session), do: broadcast("agent:working", {:agent_working, session})

  @doc "Agent transitioned to stopped/idle state. Broadcasts `{:agent_stopped, session}` on `agent:working`."
  def agent_stopped(session), do: broadcast("agent:working", {:agent_stopped, session})

  # ---------------------------------------------------------------------------
  # Session message events — topic: "session:<session_id>"
  # ---------------------------------------------------------------------------

  @doc "New message available for a session."
  def session_new_message(session_id, message) do
    broadcast("session:#{session_id}", {:new_message, message})
  end

  @doc "New DM received for a session."
  def session_new_dm(session_id, message) do
    broadcast("session:#{session_id}", {:new_dm, message})
  end

  @doc "Claude CLI process exited for a session."
  def session_cli_complete(session_id, session_ref, exit_code) do
    broadcast("session:#{session_id}", {:claude_complete, session_ref, exit_code})
  end

  @doc "Tool use event for a session."
  def session_tool_use(session_id, tool_name, tool_input) do
    broadcast("session:#{session_id}", {:tool_use, tool_name, tool_input})
  end

  @doc "Tool result event for a session."
  def session_tool_result(session_id, tool_name, error?) do
    broadcast("session:#{session_id}", {:tool_result, tool_name, error?})
  end

  # ---------------------------------------------------------------------------
  # Session status — topic: "session:<session_id>:status"
  # ---------------------------------------------------------------------------

  @doc "Session status string changed."
  def session_status(session_id, status) do
    broadcast("session:#{session_id}:status", {:session_status, session_id, status})
  end

  # ---------------------------------------------------------------------------
  # Stream events — topic: "dm:<session_id>:stream"
  # ---------------------------------------------------------------------------

  @doc "Broadcast a pre-formed stream event to a session's stream topic."
  def stream_event(session_id, event), do: broadcast("dm:#{session_id}:stream", event)

  @doc "Clear the stream display for a session."
  def stream_clear(session_id), do: broadcast("dm:#{session_id}:stream", :stream_clear)

  @doc "Agent error on the stream."
  def stream_error(session_id, provider_id, reason) do
    broadcast("dm:#{session_id}:stream", {:agent_error, provider_id, session_id, reason})
  end

  # ---------------------------------------------------------------------------
  # Queue events — topic: "dm:<session_id>:queue"
  # ---------------------------------------------------------------------------

  @doc "Queued prompt list changed for a session."
  def queue_updated(session_id, queue) do
    broadcast("dm:#{session_id}:queue", {:queue_updated, queue})
  end

  # ---------------------------------------------------------------------------
  # Channel events — topic: "channel:<channel_id>:messages"
  # ---------------------------------------------------------------------------

  @doc "New message on a channel."
  def channel_message(channel_id, message) do
    broadcast("channel:#{channel_id}:messages", {:new_message, message})
  end

  # ---------------------------------------------------------------------------
  # Notification events — topic: "notifications"
  # ---------------------------------------------------------------------------

  @doc "Broadcast a notification event tuple."
  def notification(event, payload \\ nil), do: broadcast("notifications", {event, payload})

  # ---------------------------------------------------------------------------
  # Team events — topic: "teams"
  # ---------------------------------------------------------------------------

  @doc "Broadcast a team or member event."
  def team_event(event, payload), do: broadcast("teams", {event, payload})

  # ---------------------------------------------------------------------------
  # Settings events — topic: "settings"
  # ---------------------------------------------------------------------------

  @doc "A setting value was changed or reset."
  def settings_changed(key, value) do
    broadcast("settings", {:settings_changed, key, value})
  end

  # ---------------------------------------------------------------------------
  # Scheduled job events — topic: "scheduled_jobs"
  # ---------------------------------------------------------------------------

  @doc "Scheduled job list updated."
  def jobs_updated, do: broadcast("scheduled_jobs", :jobs_updated)

  # ---------------------------------------------------------------------------
  # Session lifecycle events — topic: "session_lifecycle"
  # ---------------------------------------------------------------------------

  @doc "Session transitioned to idle (completed or errored). Used to decouple domain reactions."
  def session_idle(session_id), do: broadcast("session_lifecycle", {:session_idle, session_id})

  # ---------------------------------------------------------------------------
  # Private
  # ---------------------------------------------------------------------------

  @doc "Unsubscribe from session-scoped events."
  def unsubscribe_session(session_id), do: unsub("session:#{session_id}")

  @doc "Unsubscribe from session status events."
  def unsubscribe_session_status(session_id), do: unsub("session:#{session_id}:status")

  # ---------------------------------------------------------------------------
  # Canvas events — topic: "canvas:<canvas_id>"
  # ---------------------------------------------------------------------------

  @doc "Subscribe to canvas-scoped events (session added, etc.)."
  def subscribe_canvas(canvas_id), do: sub("canvas:#{canvas_id}")

  @doc "Unsubscribe from canvas-scoped events."
  def unsubscribe_canvas(canvas_id), do: unsub("canvas:#{canvas_id}")

  @doc "A session was added to a canvas."
  def canvas_session_added(canvas_id),
    do: broadcast("canvas:#{canvas_id}", {:canvas_session_added, %{canvas_id: canvas_id}})

  # ---------------------------------------------------------------------------
  # Orchestrator timer events — topic: "session:<session_id>:timer"
  # ---------------------------------------------------------------------------

  @doc "An orchestrator timer was scheduled (new or replacing an existing one)."
  def timer_scheduled(session_id, timer),
    do: broadcast("session:#{session_id}:timer", {:timer_scheduled, timer})

  @doc "An orchestrator timer was explicitly cancelled."
  def timer_cancelled(session_id),
    do: broadcast("session:#{session_id}:timer", :timer_cancelled)

  @doc "An orchestrator timer fired. Payload is the rescheduled timer map (repeating) or nil (one-shot)."
  def timer_fired(session_id, timer_or_nil),
    do: broadcast("session:#{session_id}:timer", {:timer_fired, timer_or_nil})

  # ---------------------------------------------------------------------------
  # Editor events — topic: "editor:<editor_id>"
  # editor_id is the file path; agents push operations keyed by the file they edited.
  # ---------------------------------------------------------------------------

  @doc "Subscribe to editor push events for a file path."
  def subscribe_editor(editor_id), do: sub("editor:#{editor_id}")

  @doc "Unsubscribe from editor push events."
  def unsubscribe_editor(editor_id), do: unsub("editor:#{editor_id}")

  @doc """
  Broadcast an editor operation to all LiveViews subscribed to this editor.

  op is one of: "set_content", "insert", "set_cursor", "highlight"
  payload is a plain map matching the JS handleEvent contract for that op.
  """
  def editor_push(editor_id, op, payload) do
    broadcast("editor:#{editor_id}", {:editor_push, op, payload})
  end

  defp broadcast(topic, message), do: Phoenix.PubSub.broadcast(@pubsub, topic, message)
  defp sub(topic), do: Phoenix.PubSub.subscribe(@pubsub, topic)
  defp unsub(topic), do: Phoenix.PubSub.unsubscribe(@pubsub, topic)
end
