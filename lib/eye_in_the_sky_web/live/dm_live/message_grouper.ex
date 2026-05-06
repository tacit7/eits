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

  The ids deliberately differ from the component-internal ids used inside
  message_item ("dm-message-<id>") and tool_cluster ("cluster-<id>") to avoid
  duplicate HTML id attributes on the page.
  """

  @tail_window 10
  @tool_types ~w(tool_use tool_result bash output)

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

  @doc "Convenience: group_events then map to stream rows."
  def grouped_rows(messages) do
    messages |> group_events() |> Enum.map(&to_stream_row/1)
  end

  @doc """
  Returns only the stream rows that changed after appending a new message.

  Re-runs group_events on the last #{@tail_window} messages from both old and
  new lists, then returns rows that are new or have changed content. The common
  case (standalone assistant message) produces exactly one new row. A tool event
  appended to an existing cluster produces one updated cluster row (same id →
  morphdom patches in place, no delete+reinsert).
  """
  def diff_tail(existing_messages, new_messages) do
    tail_old =
      existing_messages
      |> Enum.take(-@tail_window)
      |> group_events()
      |> Enum.map(&to_stream_row/1)

    tail_new =
      new_messages
      |> Enum.take(-@tail_window)
      |> group_events()
      |> Enum.map(&to_stream_row/1)

    old_by_id = Map.new(tail_old, &{&1.id, &1})

    Enum.filter(tail_new, fn row -> Map.get(old_by_id, row.id) != row end)
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
        is_tool = stream_type in @tool_types

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

  defp flush_cluster({:cluster, events}) do
    events = Enum.reverse(events)
    first = List.first(events)
    last = List.last(events)

    duration_ms =
      if first != last do
        DateTime.diff(last.inserted_at, first.inserted_at, :millisecond)
      end

    type_counts =
      Enum.frequencies_by(events, fn msg ->
        get_in(msg.metadata || %{}, ["stream_type"]) || "event"
      end)

    {:cluster, events,
     %{
       count: length(events),
       type_counts: type_counts,
       first_at: first.inserted_at,
       duration_ms: if(duration_ms && duration_ms > 1000, do: duration_ms)
     }}
  end
end
