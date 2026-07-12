defmodule EyeInTheSkyWeb.DmLive.MessageGrouper do
  @moduledoc """
  Groups raw Message structs into stream-ready row maps for the DM messages tab.

  The DM page streams the *output* of group_events/1 (clusters + message rows),
  not raw Message structs. This keeps the tool-cluster rendering in Elixir while
  letting LiveView stream individual rows to the client — new rows are diffed and
  inserted without reloading the full list.

  Stream item shape:
    %{id: "msg-row-<msg_id>",     type: :message, data: msg, prev_role: role}
    %{id: "cluster-row-<first_id>", type: :cluster, data: events, meta: meta}
    %{id: "cluster-summary-<first_id>", type: :cluster_summary, data: %{files: [...], cost_usd: float|nil, first_id: integer}}

  The ids deliberately differ from the component-internal ids used inside
  message_item ("dm-message-<id>") and tool_cluster ("cluster-<id>") to avoid
  duplicate HTML id attributes on the page.
  """

  @tail_window 10
  @tool_types ~w(tool_use tool_result bash output)
  # Stream types that represent a call (as opposed to a result/output).
  @call_stream_types ~w(tool_use bash)

  # Tools whose input carries a file_path we want to surface in the summary.
  @file_tools ~w(Write Edit Read)

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc "Returns the tail window size used by diff_tail/2 (for documentation)."
  def tail_window, do: @tail_window

  @doc "Wraps a group_events/1 tuple into a stream-ready map."
  def to_stream_row({:message, msg, prev_role}) do
    %{id: "msg-row-#{msg.id}", type: :message, data: msg, prev_role: prev_role}
  end

  def to_stream_row({:cluster, [first | _] = events, meta}) do
    %{id: "cluster-row-#{first.id}", type: :cluster, data: events, meta: meta}
  end

  def to_stream_row({:cluster_summary, first_id, data}) do
    %{id: "cluster-summary-#{first_id}", type: :cluster_summary, data: data}
  end

  @doc "Convenience: group_events then map to stream rows."
  def grouped_rows(messages) do
    messages |> group_events() |> Enum.map(&to_stream_row/1)
  end

  @doc """
  Returns `{changed_rows, new_tail_rows}` after appending a new message,
  using a pre-computed cached tail to skip re-grouping the old messages.

  `cached_old_tail` is the `new_tail_rows` returned by the previous call
  (stored in `socket.assigns.last_stream_tail`). On the first call after
  mount or a reset path, pass `[]` and the full tail will be treated as new.

  Returns:
  - `changed_rows` — rows to pass to `stream_insert/3` (new or patched).
  - `new_tail_rows` — the updated tail to store back in `@last_stream_tail`.

  The common case (standalone assistant message) produces exactly one new row.
  A tool event appended to an existing cluster produces one updated row
  (same id → morphdom patches in place, not delete+reinsert).

  ## Stable cluster identity across the tail-window boundary

  When a cluster spans more than #{@tail_window} consecutive events, the naive
  approach of grouping only the last #{@tail_window} messages would produce a
  new `first_id` each time the window slides, creating orphan rows in the stream.
  Instead, `diff_from_cached_tail/2` walks back from the window boundary to find
  the true start of any cluster that extends before the window, then groups from
  that start. This gives the cluster a stable `cluster-row-<true_first_id>` that
  never changes as new events are appended.
  """
  def diff_from_cached_tail(cached_old_tail, new_messages) do
    window_start = max(0, length(new_messages) - @tail_window)
    cluster_start = find_cluster_start(new_messages, window_start)

    new_tail_rows =
      new_messages
      |> Enum.drop(cluster_start)
      |> group_events()
      |> Enum.map(&to_stream_row/1)

    old_by_id = Map.new(cached_old_tail, &{&1.id, &1})
    # Only emit rows whose IDs are absent from the old tail — morphdom updates
    # existing IDs in place on next mount; emitting same-ID updates here would
    # cause the concatenated (old ++ changed) set to have duplicate IDs.
    changed = Enum.filter(new_tail_rows, fn row -> not Map.has_key?(old_by_id, row.id) end)

    {changed, new_tail_rows}
  end

  @doc """
  Returns only the stream rows that changed after appending a new message.

  Re-groups the last #{@tail_window} messages from both old and new lists.
  Prefer `diff_from_cached_tail/2` when the socket has `@last_stream_tail`
  available — it skips the re-group of the old tail entirely.
  """
  def diff_tail(existing_messages, new_messages) do
    tail_old =
      existing_messages
      |> Enum.take(-@tail_window)
      |> group_events()
      |> Enum.map(&to_stream_row/1)

    {changed, _new_tail} = diff_from_cached_tail(tail_old, new_messages)
    changed
  end

  # ---------------------------------------------------------------------------
  # group_events — clusters consecutive tool messages
  # ---------------------------------------------------------------------------

  def group_events(messages) do
    # Pair each message with the sender_role of its predecessor (nil for the
    # first message). Single linear walk instead of an O(n^2) Enum.find pass.
    pairs =
      messages
      |> Enum.zip([nil | messages])
      |> Enum.map(fn {msg, prev} ->
        {msg, if(prev, do: prev.sender_role, else: nil)}
      end)

    pairs
    |> Enum.chunk_while(
      nil,
      fn {msg, prev_role}, acc ->
        stream_type = get_in(msg.metadata || %{}, ["stream_type"]) || ""

        # Body-format detection is role-scoped: user/system prose that happens
        # to start with "> `Name`" or "Tool: X" must not be clustered.
        # Use Map.get to handle test stubs that may lack :sender_role.
        sender_role = Map.get(msg, :sender_role)

        is_tool =
          stream_type in @tool_types or
            (sender_role not in ~w(user system) and body_is_tool_message?(msg.body))

        cond do
          is_tool and is_nil(acc) ->
            {:cont, {:cluster, [msg]}}

          is_tool and match?({:cluster, _}, acc) ->
            {:cont, {:cluster, [msg | elem(acc, 1)]}}

          not is_tool and is_nil(acc) ->
            {:cont, {:message, msg, prev_role}, nil}

          not is_tool and match?({:cluster, _}, acc) ->
            {:cont, [flush_cluster(acc), {:message, msg, prev_role}], nil}
        end
      end,
      fn
        nil -> {:cont, []}
        acc -> {:cont, flush_cluster(acc), nil}
      end
    )
    |> List.flatten()
  end

  # ---------------------------------------------------------------------------
  # Private
  # ---------------------------------------------------------------------------

  # Walks back from window_start to find the true start of any cluster that
  # extends before the tail window. Returns window_start unchanged when the
  # first tail message is not a tool event (no cross-boundary cluster).
  defp find_cluster_start(all_messages, window_start) do
    if window_start == 0 do
      0
    else
      first_tail_msg = Enum.at(all_messages, window_start)

      if tool_event?(first_tail_msg) do
        pre_reversed = all_messages |> Enum.take(window_start) |> Enum.reverse()

        tool_run =
          Enum.reduce_while(pre_reversed, 0, fn msg, n ->
            if tool_event?(msg), do: {:cont, n + 1}, else: {:halt, n}
          end)

        window_start - tool_run
      else
        window_start
      end
    end
  end

  # Returns true when a message should be treated as a tool event for clustering.
  # Applies the same role-aware body heuristic as group_events/1.
  defp tool_event?(nil), do: false

  defp tool_event?(msg) do
    stream_type = get_in(msg.metadata || %{}, ["stream_type"]) || ""
    sender_role = Map.get(msg, :sender_role)

    stream_type in @tool_types or
      (sender_role not in ~w(user system) and body_is_tool_message?(msg.body))
  end

  defp flush_cluster({:cluster, events}) do
    events = Enum.reverse(events)
    first = List.first(events)
    last = List.last(events)

    duration_ms =
      if first != last do
        DateTime.diff(last.inserted_at, first.inserted_at, :millisecond)
      end

    call_count = count_tool_calls(events)
    result_only = call_count == 0
    # When all events are results/outputs (no calls), display the result count
    # rather than "0 calls" — the UI uses result_only: true to label it correctly.
    display_count = if result_only, do: length(events), else: call_count
    tool_groups = build_tool_groups(events)

    cluster =
      {:cluster, events,
       %{
         count: display_count,
         result_only: result_only,
         tool_groups: tool_groups,
         first_at: first.inserted_at,
         duration_ms: if(duration_ms && duration_ms > 1000, do: duration_ms)
       }}

    summary = build_cluster_summary(first.id, events)

    [cluster, summary]
  end

  defp build_tool_groups(events) do
    events
    |> Enum.group_by(&extract_tool_name/1)
    |> Enum.map(fn {name, group_events} ->
      %{name: name, count: length(group_events), events: group_events}
    end)
    |> Enum.sort_by(fn g -> List.first(g.events).id end)
  end

  defp extract_tool_name(msg) do
    get_in(msg.metadata || %{}, ["tool_name"]) ||
      extract_tool_name_from_body(msg.body) ||
      get_in(msg.metadata || %{}, ["stream_type"]) ||
      "event"
  end

  # Returns true when the message body contains a tool call in either body format:
  #   > `ToolName` args...   (session_reader format)
  #   Tool: ToolName\n{json} (Tool: format)
  # These messages have no stream_type metadata but should still be clustered.
  # Callers are responsible for restricting this to non-user/system roles.
  defp body_is_tool_message?(nil), do: false

  defp body_is_tool_message?(body) do
    trimmed = String.trim(body)
    Regex.match?(~r/^> `[^`]+`/, trimmed) or Regex.match?(~r/^Tool: [^\n]+/, trimmed)
  end

  defp extract_tool_name_from_body(nil), do: nil

  defp extract_tool_name_from_body(body) do
    trimmed = String.trim(body)

    cond do
      match = Regex.run(~r/^> `([^`]+)`/, trimmed, capture: :all_but_first) ->
        List.first(match)

      match = Regex.run(~r/^Tool: ([^\n(]+)/, trimmed, capture: :all_but_first) ->
        match |> List.first() |> String.trim()

      true ->
        nil
    end
  end

  # Counts actual tool calls in a cluster — not raw events.
  # A tool_use event = 1 call. A tool_result/output event = 0 calls (it's a response).
  # A body-format message may contain multiple calls (counted via regex scan).
  defp count_tool_calls(events) do
    Enum.reduce(events, 0, fn msg, acc ->
      stream_type = get_in(msg.metadata || %{}, ["stream_type"]) || ""

      cond do
        stream_type in @call_stream_types ->
          acc + 1

        stream_type in @tool_types ->
          # Result/output type — does not count as a call
          acc

        body_is_tool_message?(msg.body) ->
          acc + count_calls_in_body(msg.body)

        true ->
          acc
      end
    end)
  end

  defp count_calls_in_body(body) do
    trimmed = String.trim(body)
    # Each `> `Name`` line is one call (session_reader format)
    backtick = length(Regex.scan(~r/^> `[^`]+`/m, trimmed))
    # Each `Tool: ` header line is one call (Tool: format)
    tool_colon = length(Regex.scan(~r/^Tool: /m, trimmed))
    backtick + tool_colon
  end

  defp build_cluster_summary(first_id, events) do
    files =
      events
      |> Enum.filter(fn msg ->
        tool_name = get_in(msg.metadata || %{}, ["tool_name"])
        tool_name in @file_tools
      end)
      |> Enum.flat_map(fn msg ->
        case get_in(msg.metadata || %{}, ["input", "file_path"]) do
          nil -> []
          path -> [path]
        end
      end)
      |> Enum.uniq()

    cost_usd =
      events
      |> Enum.flat_map(fn msg ->
        case get_in(msg.metadata || %{}, ["total_cost_usd"]) do
          nil -> []
          cost when is_number(cost) -> [cost]
          _ -> []
        end
      end)
      |> case do
        [] -> nil
        costs -> Enum.sum(costs)
      end

    {:cluster_summary, first_id, %{files: files, cost_usd: cost_usd, first_id: first_id}}
  end
end
