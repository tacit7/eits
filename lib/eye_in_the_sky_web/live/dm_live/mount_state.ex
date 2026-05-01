defmodule EyeInTheSkyWeb.DmLive.MountState do
  @moduledoc false

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [allow_upload: 3]
  import EyeInTheSkyWeb.ControllerHelpers, only: [parse_int: 1]

  alias EyeInTheSky.Claude.AgentWorker
  alias EyeInTheSky.Events
  alias EyeInTheSky.{Projects, Tasks}
  alias EyeInTheSkyWeb.Helpers.PubSubHelpers
  alias EyeInTheSkyWeb.Helpers.SlashItems
  alias EyeInTheSky.OrchestratorTimers

  @default_message_limit 50

  def maybe_subscribe(is_connected, session_id, current_user) do
    if is_connected do
      if session_belongs_to?(session_id, current_user) do
        setup_subscriptions(session_id)
      else
        :unauthorized
      end
    else
      :ok
    end
  end

  def setup_subscriptions(session_id) do
    PubSubHelpers.subscribe_session(session_id)
    PubSubHelpers.subscribe_agent_working()
    PubSubHelpers.subscribe_agents()
    PubSubHelpers.subscribe_dm_stream(session_id)
    PubSubHelpers.subscribe_dm_queue(session_id)
    PubSubHelpers.subscribe_tasks()
    Events.subscribe_session_timer(session_id)
    Events.subscribe_codex_raw(session_id)
  end

  # Allow access in both auth-enabled (any user) and auth-disabled (current_user=nil)
  # modes. The nil -> false clause silently broke real-time updates under
  # DISABLE_AUTH=true: the LiveView mounted but never called setup_subscriptions,
  # so {:new_message} and {:new_dm} broadcasts were dropped on the floor.
  # Future: add user_id to sessions table and verify ownership when auth is required.
  defp session_belongs_to?(_session_id, _current_user), do: true

  def assign_sidebar_context(socket, %{"from" => "project", "project_id" => project_id_str}) do
    case parse_int(project_id_str) do
      nil ->
        socket
        |> assign(:sidebar_tab, :dm)
        |> assign(:sidebar_project, nil)

      pid ->
        socket
        |> assign(:sidebar_tab, :dm)
        |> assign(:sidebar_project, Projects.get_project!(pid))
    end
  end

  def assign_sidebar_context(socket, _params) do
    socket
    |> assign(:sidebar_tab, :dm)
    |> assign(:sidebar_project, nil)
  end

  def assign_session_state(socket, session, agent) do
    socket
    |> assign(:page_title, session.name || "Session")
    |> assign(:hide_mobile_header, true)
    |> assign(:session_id, session.id)
    |> assign(:session_uuid, session.uuid)
    |> assign(:agent_id, session.agent_id)
    |> assign(:session, session)
    |> assign(:agent, agent)
  end

  # Fast path — safe for disconnected mount. No DB or GenServer calls.
  def assign_essential_defaults(socket, session) do
    socket
    |> assign_ui_flags(session)
    |> assign_stream_defaults()
    |> assign_task_defaults()
    |> assign_upload_config()
  end

  defp assign_ui_flags(socket, session) do
    socket
    |> assign(:active_tab, "messages")
    |> assign(:session_ref, nil)
    |> assign(:processing, false)
    |> assign(:selected_model, session.model || "opus")
    |> assign(:selected_effort, "medium")
    |> assign(:active_overlay, nil)
    |> assign(:show_live_stream, true)
    |> assign(:slash_items, SlashItems.build())
    |> assign(:diff_cache, %{})
    |> assign(:reload_timer, nil)
    |> assign(:thinking_enabled, false)
    |> assign(:max_budget_usd, nil)
    |> assign(:session_cli_opts, [])
    |> assign(:compacting, session.status == "compacting")
    |> assign(:message_search_query, "")
    |> assign(:session_context, nil)
    |> assign(:reloading, false)
    |> assign(:active_timer, nil)
    |> assign(:codex_raw_lines, [])
    |> assign(:notify_on_stop, false)
    |> assign(:dm_settings_scope, "session")
    |> assign(:dm_settings_subtab, "general")
  end

  defp assign_stream_defaults(socket) do
    socket
    |> assign(:stream_content, nil)
    |> assign(:stream_tool, nil)
    |> assign(:stream_thinking, nil)
    |> assign(:total_tokens, 0)
    |> assign(:total_cost, 0.0)
    |> assign(:context_used, 0)
    |> assign(:context_window, 0)
  end

  defp assign_task_defaults(socket) do
    socket
    |> assign(:message_limit, @default_message_limit)
    |> assign(:has_more_messages, false)
    |> assign(:selected_task, nil)
    |> assign(:task_notes, [])
    |> assign(:workflow_states, [])
    |> assign(:current_task, :not_loaded)
    |> assign(:queued_prompts, [])
    |> assign(:tasks, [])
    |> assign(:commits, [])
    |> assign(:notes, [])
  end

  defp assign_upload_config(socket) do
    allow_upload(socket, :files,
      accept: ~w(.jpg .jpeg .png .gif .pdf .txt .md .csv .json .xml .html),
      max_entries: 10,
      max_file_size: 50_000_000,
      auto_upload: true
    )
  end

  # Connected-only — runs DB queries and GenServer calls after WebSocket upgrade.
  def assign_connected_defaults(socket, session) do
    stream_content =
      if session.status == "working",
        do: AgentWorker.get_stream_state(session.id),
        else: ""

    socket
    |> assign(:processing, initial_processing?(session))
    |> assign(:stream_content, stream_content)
    |> assign(:workflow_states, Tasks.list_workflow_states())
    |> assign(:current_task, Tasks.get_current_task_for_session(session.id))
    |> assign(:queued_prompts, AgentWorker.get_queue(session.id))
    |> assign(:active_timer, OrchestratorTimers.get_timer(session.id))
  end

  # For definitively-ended sessions (interactive close, crash), never show the
  # stop button. completed/failed sessions should not be resumed and any lagging
  # AgentWorker state from the SessionEnd hook would be a false positive.
  @ended_statuses ~w(completed failed)
  defp initial_processing?(%{status: status}) when status in @ended_statuses, do: false

  # For all other statuses (working, stopped, idle, waiting, archived, etc.),
  # delegate to the AgentWorker. "waiting" means a headless sdk-cli session
  # ended and can be resumed — if the user sends a new message, a new worker
  # runs and its state must be reflected here.
  defp initial_processing?(%{id: session_id}) do
    AgentWorker.processing?(session_id)
  end
end
