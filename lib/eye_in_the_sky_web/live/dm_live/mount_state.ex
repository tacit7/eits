defmodule EyeInTheSkyWeb.DmLive.MountState do
  @moduledoc false

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [allow_upload: 3, connected?: 1]

  alias EyeInTheSky.{Tasks, Projects}
  alias EyeInTheSky.Claude.AgentWorker
  alias EyeInTheSkyWeb.Helpers.PubSubHelpers
  alias EyeInTheSkyWeb.Helpers.SlashItems

  @default_message_limit 20

  def maybe_subscribe(socket, session_id) do
    if connected?(socket), do: setup_subscriptions(session_id)
  end

  def setup_subscriptions(session_id) do
    PubSubHelpers.subscribe_session(session_id)
    PubSubHelpers.subscribe_agent_working()
    PubSubHelpers.subscribe_agents()
    PubSubHelpers.subscribe_dm_stream(session_id)
    PubSubHelpers.subscribe_dm_queue(session_id)
    PubSubHelpers.subscribe_tasks()
  end

  def assign_sidebar_context(socket, %{"from" => "project", "project_id" => project_id_str}) do
    case Integer.parse(project_id_str) do
      {pid, ""} ->
        socket
        |> assign(:sidebar_tab, :sessions)
        |> assign(:sidebar_project, Projects.get_project!(pid))

      _ ->
        socket
        |> assign(:sidebar_tab, :chat)
        |> assign(:sidebar_project, nil)
    end
  end

  def assign_sidebar_context(socket, _params) do
    socket
    |> assign(:sidebar_tab, :chat)
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

  def assign_defaults(socket, session) do
    socket
    |> assign(:active_tab, "messages")
    |> assign(:session_ref, nil)
    |> assign(:processing, initial_processing?(session))
    |> assign(:message_limit, @default_message_limit)
    |> assign(:has_more_messages, false)
    |> assign(:selected_model, session.model || "opus")
    |> assign(:selected_effort, "medium")
    |> assign(:active_overlay, nil)
    |> assign(:show_live_stream, true)
    |> assign(:stream_content, AgentWorker.get_stream_state(session.id))
    |> assign(:stream_tool, nil)
    |> assign(:stream_thinking, nil)
    |> assign(:slash_items, SlashItems.build())
    |> assign(:session_cli_opts, [])
    |> assign(:diff_cache, %{})
    |> assign(:selected_task, nil)
    |> assign(:task_notes, [])
    |> assign(:workflow_states, Tasks.list_workflow_states())
    |> assign(:current_task, Tasks.get_current_task_for_session(session.id))
    |> assign(:reload_timer, nil)
    |> assign(:total_tokens, 0)
    |> assign(:total_cost, 0.0)
    |> assign(:context_used, 0)
    |> assign(:context_window, 0)
    |> assign(:queued_prompts, AgentWorker.get_queue(session.id))
    |> assign(:thinking_enabled, false)
    |> assign(:max_budget_usd, nil)
    |> assign(:session_cli_opts, [])
    |> assign(:compacting, session.status == "compacting")
    |> assign(:message_search_query, "")
    |> assign(:session_context, nil)
    |> assign(:reloading, false)
    |> allow_upload(:files,
      accept: ~w(.jpg .jpeg .png .gif .pdf .txt .md .csv .json .xml .html),
      max_entries: 10,
      max_file_size: 50_000_000,
      auto_upload: true
    )
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
    AgentWorker.is_processing?(session_id)
  end
end
