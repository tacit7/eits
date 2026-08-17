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

  ## Payload shape for `tasks` topic

  - `{:tasks_changed, %{task_id: id, task: %Task{}}}` — specific task created/updated/deleted
  - `{:tasks_changed, %{}}` — generic task change (no entity info)
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

  @doc "Unsubscribe from real-time stream deltas for a session."
  def unsubscribe_dm_stream(session_id), do: unsub("dm:#{session_id}:stream")

  @doc "Subscribe to queued-prompt updates for a session."
  def subscribe_dm_queue(session_id), do: sub("dm:#{session_id}:queue")

  @doc "Subscribe to raw Codex JSONL stream lines for a session."
  def subscribe_codex_raw(session_id), do: sub("codex:#{session_id}:raw")

  @doc "Broadcast a raw Codex JSONL line for a session."
  def broadcast_codex_raw(session_id, line),
    do: broadcast("codex:#{session_id}:raw", {:codex_raw_line, line})

  @doc "Subscribe to new messages on a channel."
  def subscribe_channel_messages(channel_id), do: sub("channel:#{channel_id}:messages")

  @doc "Unsubscribe from new messages on a channel."
  def unsubscribe_channel_messages(channel_id), do: unsub("channel:#{channel_id}:messages")

  @doc "Subscribe to notification events."
  def subscribe_notifications, do: sub("notifications")

  @doc "Subscribe to team/member events."
  def subscribe_teams, do: sub("teams")

  @doc "Subscribe to project metadata changes (bookmark toggled, etc.)."
  def subscribe_projects, do: sub("projects")

  @doc "A project record was updated. Broadcasts to projects topic."
  def project_updated(project), do: broadcast("projects", {:project_updated, project})

  @doc "Subscribe to channel list changes (created, deleted/archived)."
  def subscribe_channels, do: sub("channels")

  @doc "A channel was created. Broadcasts to channels topic."
  def channel_created(channel), do: broadcast("channels", {:channel_created, channel})

  @doc "A channel was deleted/archived. Broadcasts to channels topic."
  def channel_deleted(channel), do: broadcast("channels", {:channel_deleted, channel})

  @doc "Subscribe to bookmark changes (created, deleted)."
  def subscribe_bookmarks, do: sub("bookmarks")

  @doc "A bookmark was created. Broadcasts to bookmarks topic."
  def bookmark_created(bookmark), do: broadcast("bookmarks", {:bookmark_created, bookmark})

  @doc "A bookmark was deleted. Broadcasts to bookmarks topic."
  def bookmark_deleted(bookmark), do: broadcast("bookmarks", {:bookmark_deleted, bookmark})

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
      broadcast("tasks:#{task.project_id}", {:task_updated, task})
    end
  end

  @doc "Tasks changed (no specific task). Global broadcast only."
  def tasks_changed, do: broadcast("tasks", :tasks_changed)

  # ---------------------------------------------------------------------------
  # Note events — topic: "note:<note_id>"
  # ---------------------------------------------------------------------------

  @doc "Subscribe to events for a specific note (e.g. editor sync updates)."
  def subscribe_note(note_id), do: sub(record_topic(:note, note_id))

  @doc "Unsubscribe from events for a specific note."
  def unsubscribe_note(note_id), do: unsub(record_topic(:note, note_id))

  @doc "Note content was updated (e.g. by the editor sync watcher)."
  def note_updated(note), do: broadcast(record_topic(:note, note.id), {:note_updated, note})

  # ---------------------------------------------------------------------------
  # Prompt events — topic: "prompt:<prompt_id>"
  # ---------------------------------------------------------------------------

  @doc "Subscribe to events for a specific prompt."
  def subscribe_prompt(prompt_id), do: sub(record_topic(:prompt, prompt_id))

  @doc "Unsubscribe from events for a specific prompt."
  def unsubscribe_prompt(prompt_id), do: unsub(record_topic(:prompt, prompt_id))

  @doc "Prompt content was updated (e.g. by the editor sync watcher)."
  def prompt_updated(prompt),
    do: broadcast(record_topic(:prompt, prompt.id), {:prompt_updated, prompt})

  # ---------------------------------------------------------------------------
  # Editor sync failure — record-specific topic
  # ---------------------------------------------------------------------------

  @doc """
  Subscribe to editor sync failure events for a record.

  Type is `:note`, `:prompt`, or `:task`.
  """
  def subscribe_editor_sync(type, record_id), do: sub(record_topic(type, record_id))

  @doc "Unsubscribe from editor sync failure events for a record."
  def unsubscribe_editor_sync(type, record_id), do: unsub(record_topic(type, record_id))

  @doc """
  An EditorSync watcher failed to write changes back to the DB.

  Broadcasts on the record-specific topic so the LiveView that owns the
  selection can show a flash message without subscribing to a global error bus.
  """
  def editor_sync_failed(type, record_id, reason) do
    broadcast(record_topic(type, record_id), {:editor_sync_failed, type, record_id, reason})
  end

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

  @doc "Subscribe to GitHub webhook delivery notifications."
  def subscribe_github_webhook, do: sub("github:webhook_received")

  @doc "Broadcast a delivery ID to wake the WebhookDispatcher."
  def github_webhook_received(delivery_id),
    do: broadcast("github:webhook_received", {:github_webhook_received, delivery_id})

  @doc "Broadcast a GitHub webhook rule fired event to a custom topic."
  def webhook_rule_fired(topic, message),
    do: broadcast(topic, {:webhook_rule_fired, message})

  @doc "Subscribe to pull request update events."
  def subscribe_pull_requests, do: sub("pull_requests:updated")

  @doc "Broadcast that a pull request record was updated."
  def pull_request_updated(pr),
    do: broadcast("pull_requests:updated", {:pull_request_updated, pr})

  @doc "Subscribe to Pi model discovery refresh events."
  def subscribe_pi_models, do: sub("pi:models")

  @doc "Broadcast a Pi model discovery refresh result."
  def pi_models_refreshed(result),
    do: broadcast("pi:models", {:pi_models_refreshed, result})

  # ---------------------------------------------------------------------------
  # Rail context — page LiveViews → RailLive
  # ---------------------------------------------------------------------------
  # These replace send_update(Rail, ...) calls which only work within the same
  # LiveView process. RailLive is now a standalone process; PubSub is the
  # correct cross-process channel.

  @doc """
  Build a browser-session-scoped topic for rail context updates.

  The rail is rendered as a sticky child LiveView while the page content is a
  separate LiveView process. A global rail context topic lets one window's page
  broadcasts overwrite another window's selected project, so routed views pass
  this scoped topic into the embedded rail.
  """
  def rail_context_topic(%{"_csrf_token" => token}) when is_binary(token) and token != "" do
    digest =
      :crypto.hash(:sha256, token)
      |> Base.url_encode64(padding: false)

    "rail:context:#{digest}"
  end

  def rail_context_topic(_session), do: "rail:context"

  @doc "Subscribe to rail context updates. Call from RailLive.mount/3 (connected? guard)."
  def subscribe_rail_context(topic \\ "rail:context"), do: sub(topic)

  @doc """
  Broadcast current rail context from a page LiveView.

  Call after sidebar assigns are set in mount/3 and handle_params/3.
  Reads sidebar_tab, sidebar_project, and active_channel_id from socket.assigns.
  """
  def broadcast_rail_context(socket) do
    topic = socket.assigns[:rail_context_topic] || "rail:context"

    broadcast(topic, {
      :rail_context,
      %{
        sidebar_tab: socket.assigns[:sidebar_tab] || :sessions,
        sidebar_project: socket.assigns[:sidebar_project],
        active_channel_id: socket.assigns[:active_channel_id]
      }
    })
  end

  @doc "Subscribe to rail unread count updates (call from RailLive)."
  def subscribe_rail_unread_counts, do: sub("rail:unread_counts")

  @doc "Broadcast unread channel counts from chat_live to RailLive."
  def broadcast_rail_unread_counts(counts),
    do: broadcast("rail:unread_counts", {:rail_unread_counts, counts})

  @doc "Subscribe to targeted session updates for the Rail flyout (call from RailLive)."
  def subscribe_rail_session_update, do: sub("rail:session_update")

  @doc "Broadcast a single session update to RailLive (replaces send_update session_updated:)."
  def broadcast_rail_session_updated(session),
    do: broadcast("rail:session_update", {:rail_session_updated, session})

  @doc "Subscribe to notification-count refresh signals for the Rail."
  def subscribe_rail_notifications_refresh, do: sub("rail:refresh:notifications")

  @doc "Signal RailLive to refresh its notification count."
  def broadcast_rail_refresh_notifications,
    do: broadcast("rail:refresh:notifications", :rail_refresh_notifications)

  @doc "Subscribe to project-list refresh signals for the Rail."
  def subscribe_rail_projects_refresh, do: sub("rail:refresh:projects")

  @doc "Signal RailLive to refresh its project list."
  def broadcast_rail_refresh_projects,
    do: broadcast("rail:refresh:projects", :rail_refresh_projects)

  @doc "Subscribe to channel-list refresh signals for the Rail."
  def subscribe_rail_channels_refresh, do: sub("rail:refresh:channels")

  @doc "Signal RailLive to refresh its flyout channel list."
  def broadcast_rail_refresh_channels,
    do: broadcast("rail:refresh:channels", :rail_refresh_channels)

  defp broadcast(topic, message), do: Phoenix.PubSub.broadcast(@pubsub, topic, message)
  defp sub(topic), do: Phoenix.PubSub.subscribe(@pubsub, topic)
  defp unsub(topic), do: Phoenix.PubSub.unsubscribe(@pubsub, topic)

  # Centralized topic construction for record-specific events.
  # Singular prefix ("note:", "prompt:", "task:") distinguishes from the
  # plural collection topics ("tasks:", "tasks:<project_id>").
  defp record_topic(type, id), do: "#{type}:#{id}"
end
