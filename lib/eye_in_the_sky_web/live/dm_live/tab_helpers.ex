defmodule EyeInTheSkyWeb.DmLive.TabHelpers do
  @moduledoc false

  import Phoenix.Component, only: [assign: 3]

  alias EyeInTheSky.{Commits, Contexts, Messages, Notes, Tasks}
  alias EyeInTheSkyWeb.Live.Shared.SessionHelpers

  require Logger

  @default_context_window 200_000
  @default_message_limit 20

  def load_tab_data(socket, tab, session_id) do
    Logger.info("Loading DM tab data tab=#{tab} session_id=#{session_id}")
    {messages, has_more} = load_message_data(socket, tab, session_id)

    # Sentinel {0, 0.0} means "not yet loaded". A session with genuinely zero
    # usage also returns {0, 0.0}, which will correctly cache and skip re-reads.
    {total_tokens, total_cost} =
      maybe_load_once(
        tab,
        "messages",
        {socket.assigns[:total_tokens], socket.assigns[:total_cost]},
        {0, 0.0},
        fn -> read_session_usage_stats(socket, session_id) end
      )

    current_task =
      maybe_load_once(
        tab,
        ["messages", "tasks"],
        socket.assigns[:current_task],
        nil,
        fn -> Tasks.get_current_task_for_session(session_id) end
      )

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
        |> enrich_commit_messages(socket)
      end)
    )
    |> assign(
      :notes,
      maybe_load_tab_data(tab, "notes", socket.assigns[:notes], fn ->
        Notes.list_notes_for_session(session_id)
      end)
    )
    |> assign(
      :session_context,
      maybe_load_tab_data(tab, "context", socket.assigns[:session_context], fn ->
        case Contexts.get_session_context(session_id) do
          {:ok, ctx} -> ctx
          {:error, :not_found} -> nil
        end
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

      Logger.info(
        "Searched #{length(messages)} messages for session=#{session_id} query=#{inspect(query)}"
      )

      {messages, false}
    else
      # Messages are kept live via PubSub handle_info — skip the DB round-trip
      # when switching back to the messages tab if they're already loaded.
      existing = socket.assigns[:messages]

      if existing != nil do
        {existing, socket.assigns[:has_more_messages] || false}
      else
        limit = socket.assigns[:message_limit] || @default_message_limit

        fetched_messages =
          Messages.list_recent_messages(session_id, limit + 1)

        Logger.info("Loaded #{length(fetched_messages)} messages for session=#{session_id}")

        if length(fetched_messages) > limit do
          {Enum.drop(fetched_messages, 1), true}
        else
          {fetched_messages, false}
        end
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

  # Like maybe_load_value but skips the loader if the value is already loaded
  # (i.e. not equal to the empty sentinel). Avoids redundant DB/IO on tab switch.
  defp maybe_load_once(active_tab, target_tabs, existing_value, empty_sentinel, loader) do
    targets = List.wrap(target_tabs)

    if active_tab in targets and existing_value == empty_sentinel do
      loader.()
    else
      existing_value
    end
  end

  defp extract_context_window(messages) do
    messages
    |> Enum.reverse()
    |> Enum.find_value(&extract_context_from_metadata/1)
    |> Kernel.||({0, 0})
  end

  defp extract_context_from_metadata(msg) do
    case msg.metadata do
      %{"model_usage" => model_usage} when is_map(model_usage) and map_size(model_usage) > 0 ->
        extract_from_model_usage(model_usage)

      %{"usage" => %{"input_tokens" => _} = usage} ->
        extract_from_usage(usage)

      _ ->
        nil
    end
  end

  defp extract_from_model_usage(model_usage) do
    model_usage
    |> Map.values()
    |> Enum.find_value(fn entry when is_map(entry) ->
      input = entry["inputTokens"] || 0
      cache_read = entry["cacheReadInputTokens"] || 0
      cache_creation = entry["cacheCreationInputTokens"] || 0
      ctx_window = entry["contextWindow"] || @default_context_window
      used = input + cache_read + cache_creation

      if used > ctx_window do
        Logger.warning(
          "[ctx_overflow] model_usage: used=#{used} window=#{ctx_window} " <>
            "input=#{input} cache_read=#{cache_read} cache_creation=#{cache_creation}"
        )
      end

      if used > 0, do: {used, ctx_window}
    end)
  end

  defp extract_from_usage(usage) do
    input = usage["input_tokens"] || 0
    cache_read = usage["cache_read_input_tokens"] || 0
    cache_creation = usage["cache_creation_input_tokens"] || 0
    used = input + cache_read + cache_creation

    if used > @default_context_window do
      Logger.warning(
        "[ctx_overflow] usage: used=#{used} window=#{@default_context_window} " <>
          "input=#{input} cache_read=#{cache_read} cache_creation=#{cache_creation}"
      )
    end

    if used > 0, do: {used, @default_context_window}
  end

  # Enriches commits that have no stored message by fetching subjects from git.
  # Uses a single `git log --no-walk` call for all missing hashes at once.
  # Returns commits unchanged if project path can't be resolved.
  defp enrich_commit_messages(commits, socket) do
    missing = Enum.filter(commits, &is_nil(&1.commit_message))

    if missing == [] do
      commits
    else
      case SessionHelpers.resolve_project_path(socket.assigns.session, socket.assigns.agent) do
        {:ok, project_path} ->
          hashes = Enum.map(missing, & &1.commit_hash)

          messages =
            case System.cmd(
                   "git",
                   ["-C", project_path, "log", "--no-walk", "--format=%H\t%s"] ++ hashes,
                   stderr_to_stdout: false
                 ) do
              {output, 0} ->
                output
                |> String.split("\n", trim: true)
                |> Map.new(fn line ->
                  [hash | rest] = String.split(line, "\t", parts: 2)
                  {String.trim(hash), Enum.join(rest, "\t")}
                end)

              _ ->
                %{}
            end

          Enum.map(commits, fn commit ->
            if is_nil(commit.commit_message) do
              %{commit | commit_message: Map.get(messages, commit.commit_hash)}
            else
              commit
            end
          end)

        _ ->
          commits
      end
    end
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
