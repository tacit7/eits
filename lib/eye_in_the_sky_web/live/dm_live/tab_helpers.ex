defmodule EyeInTheSkyWeb.DmLive.TabHelpers do
  @moduledoc false

  import Phoenix.Component, only: [assign: 3]

  alias EyeInTheSky.{Commits, Messages, Notes, Repo, Tasks}

  require Logger

  @default_message_limit 20

  def load_tab_data(socket, tab, session_id) do
    Logger.info("Loading DM tab data tab=#{tab} session_id=#{session_id}")
    {messages, has_more} = load_message_data(socket, tab, session_id)

    {total_tokens, total_cost} =
      maybe_load_value(
        tab,
        "messages",
        {socket.assigns[:total_tokens], socket.assigns[:total_cost]},
        fn -> read_session_usage_stats(socket, session_id) end
      )

    current_task =
      maybe_load_value(tab, ["messages", "tasks"], socket.assigns[:current_task], fn ->
        Tasks.get_current_task_for_session(session_id)
      end)

    {context_used, context_window} =
      maybe_load_value(
        tab,
        "messages",
        {socket.assigns[:context_used], socket.assigns[:context_window]},
        fn -> extract_context_window(messages) end
      )

    socket
    |> assign(:messages, messages)
    |> assign(:has_more_messages, has_more)
    |> assign(:total_tokens, total_tokens)
    |> assign(:total_cost, total_cost)
    |> assign(:context_used, context_used || 0)
    |> assign(:context_window, context_window || 0)
    |> assign(:current_task, current_task)
    |> assign(
      :tasks,
      maybe_load_tab_data(tab, "tasks", socket.assigns[:tasks], fn ->
        Tasks.list_tasks_for_session(session_id)
      end)
    )
    |> assign(
      :commits,
      maybe_load_tab_data(tab, "commits", socket.assigns[:commits], fn ->
        Commits.list_commits_for_session(session_id)
      end)
    )
    |> assign(
      :notes,
      maybe_load_tab_data(tab, "notes", socket.assigns[:notes], fn ->
        Notes.list_notes_for_session(session_id)
      end)
    )
  end

  def reload_tasks(socket) do
    assign(socket, :tasks, Tasks.list_tasks_for_session(socket.assigns.session_id))
  end

  defp load_message_data(socket, "messages", session_id) do
    query = socket.assigns[:message_search_query] || ""

    if query != "" do
      messages =
        Messages.search_messages_for_session(session_id, query)
        |> Repo.preload(:attachments)

      Logger.info(
        "Searched #{length(messages)} messages for session=#{session_id} query=#{inspect(query)}"
      )

      {messages, false}
    else
      limit = socket.assigns[:message_limit] || @default_message_limit

      fetched_messages =
        Messages.list_recent_messages(session_id, limit + 1)
        |> Repo.preload(:attachments)

      Logger.info("Loaded #{length(fetched_messages)} messages for session=#{session_id}")

      if length(fetched_messages) > limit do
        {Enum.drop(fetched_messages, 1), true}
      else
        {fetched_messages, false}
      end
    end
  end

  defp load_message_data(socket, _tab, _session_id) do
    {socket.assigns[:messages] || [], socket.assigns[:has_more_messages] || false}
  end

  defp maybe_load_tab_data(active_tab, target_tab, existing_data, loader) do
    if active_tab == target_tab do
      loader.()
    else
      existing_data || []
    end
  end

  defp maybe_load_value(active_tab, target_tabs, existing_value, loader) do
    targets = List.wrap(target_tabs)

    if active_tab in targets do
      loader.()
    else
      existing_value
    end
  end

  defp extract_context_window(messages) do
    messages
    |> Enum.reverse()
    |> Enum.find_value(fn msg ->
      case msg.metadata do
        %{"model_usage" => model_usage} when is_map(model_usage) and map_size(model_usage) > 0 ->
          model_usage
          |> Map.values()
          |> Enum.find_value(fn entry when is_map(entry) ->
            input = entry["inputTokens"] || 0
            cache_read = entry["cacheReadInputTokens"] || 0
            cache_creation = entry["cacheCreationInputTokens"] || 0
            ctx_window = entry["contextWindow"] || 200_000
            used = input + cache_read + cache_creation

            if used > 0, do: {used, ctx_window}
          end)

        %{"usage" => %{"input_tokens" => _} = usage} ->
          input = usage["input_tokens"] || 0
          cache_read = usage["cache_read_input_tokens"] || 0
          cache_creation = usage["cache_creation_input_tokens"] || 0
          used = input + cache_read + cache_creation

          if used > 0, do: {used, 200_000}

        _ ->
          nil
      end
    end) || {0, 0}
  end

  defp read_session_usage_stats(socket, session_id) do
    alias EyeInTheSky.Claude.SessionReader
    alias EyeInTheSkyWeb.Live.Shared.SessionHelpers

    case SessionHelpers.resolve_project_path(socket.assigns.session, socket.assigns.agent) do
      {:ok, project_path} ->
        case SessionReader.read_usage(socket.assigns.session_uuid, project_path) do
          {:ok, tokens, cost} ->
            {tokens, cost}

          _ ->
            {Messages.total_tokens_for_session(session_id),
             Messages.total_cost_for_session(session_id)}
        end

      _ ->
        {Messages.total_tokens_for_session(session_id),
         Messages.total_cost_for_session(session_id)}
    end
  end
end
