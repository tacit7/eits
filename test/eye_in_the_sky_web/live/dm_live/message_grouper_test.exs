defmodule EyeInTheSkyWeb.DmLive.MessageGrouperTest do
  use ExUnit.Case, async: true

  alias EyeInTheSkyWeb.DmLive.MessageGrouper

  # ---------------------------------------------------------------------------
  # Test helpers
  # ---------------------------------------------------------------------------

  defp msg(id, opts \\ []) do
    role = Keyword.get(opts, :role, "agent")
    stream_type = Keyword.get(opts, :stream_type, nil)
    body = Keyword.get(opts, :body, nil)

    metadata =
      case stream_type do
        nil -> %{}
        t -> %{"stream_type" => t}
      end

    %{
      id: id,
      sender_role: role,
      metadata: metadata,
      body: body,
      inserted_at: ~U[2024-01-01 00:00:00Z]
    }
  end

  defp tool_msg(id, stream_type \\ "tool_use") do
    msg(id, role: "agent", stream_type: stream_type)
  end

  defp result_msg(id) do
    msg(id, role: "agent", stream_type: "tool_result")
  end

  defp user_msg(id, body \\ nil) do
    msg(id, role: "user", body: body)
  end

  defp body_call_msg(id, body) do
    msg(id, role: "agent", body: body)
  end

  # ---------------------------------------------------------------------------
  # Defect 1: stable cluster identity across the tail-window boundary
  # ---------------------------------------------------------------------------

  describe "diff_from_cached_tail/2 — stable cluster identity" do
    test "12 consecutive tool events: new_tail cluster ID stays cluster-row-1 as window slides" do
      # Build a run of 12 consecutive tool events (exceeds @tail_window = 10).
      messages = Enum.map(1..12, &tool_msg/1)

      # Simulate what happens after the first 10 messages are loaded:
      # last_stream_tail is set to the rows from grouped_rows([msg1..msg10]).
      initial_tail = messages |> Enum.take(10) |> MessageGrouper.grouped_rows()

      # Message 11 arrives.
      {_changed11, tail11} =
        MessageGrouper.diff_from_cached_tail(initial_tail, Enum.take(messages, 11))

      # Message 12 arrives.
      {_changed12, tail12} = MessageGrouper.diff_from_cached_tail(tail11, messages)

      # The new_tail cluster ID must be cluster-row-1 throughout.
      cluster_in_tail11 = Enum.find(tail11, &(&1.type == :cluster))
      cluster_in_tail12 = Enum.find(tail12, &(&1.type == :cluster))
      assert cluster_in_tail11.id == "cluster-row-1"
      assert cluster_in_tail12.id == "cluster-row-1"
    end

    test "no orphan summary row when cluster spans window boundary" do
      messages = Enum.map(1..12, &tool_msg/1)
      initial_tail = messages |> Enum.take(10) |> MessageGrouper.grouped_rows()

      {changed, new_tail} = MessageGrouper.diff_from_cached_tail(initial_tail, messages)

      # The summary in the new tail must use the stable cluster anchor.
      summary_in_tail = Enum.find(new_tail, &(&1.type == :cluster_summary))
      assert summary_in_tail.id == "cluster-summary-1"

      # No orphan summaries with a wrong (shifted) ID should appear in changed.
      orphan_summaries =
        Enum.filter(changed, fn row ->
          row.type == :cluster_summary and row.id != "cluster-summary-1"
        end)

      assert orphan_summaries == []
    end

    test "new_tail cluster includes ALL events, not just window slice" do
      messages = Enum.map(1..11, &tool_msg/1)
      initial_tail = messages |> Enum.take(10) |> MessageGrouper.grouped_rows()

      {_changed, new_tail} = MessageGrouper.diff_from_cached_tail(initial_tail, messages)

      cluster_row = Enum.find(new_tail, &(&1.type == :cluster))
      event_ids = Enum.map(cluster_row.data, & &1.id)
      # new_tail cluster must hold all 11 events, not just the window slice.
      assert event_ids == Enum.to_list(1..11)
    end

    test "non-tool message after a long cluster does not extend the cluster" do
      tool_msgs = Enum.map(1..10, &tool_msg/1)
      user = user_msg(11)
      messages = tool_msgs ++ [user]

      {changed, new_tail} = MessageGrouper.diff_from_cached_tail([], messages)

      row_types = Enum.map(new_tail, & &1.type)
      assert :cluster in row_types
      assert :message in row_types

      # User message should be a standalone row, not part of the cluster.
      user_row = Enum.find(changed, &(&1.type == :message))
      refute is_nil(user_row)
      assert user_row.data.id == 11
    end

    test "two separate clusters in the window are both represented correctly" do
      # cluster A (msgs 1-3), user (4), cluster B (msgs 5-7)
      messages = [
        tool_msg(1),
        tool_msg(2),
        tool_msg(3),
        user_msg(4),
        tool_msg(5),
        tool_msg(6),
        tool_msg(7)
      ]

      {changed, _tail} = MessageGrouper.diff_from_cached_tail([], messages)

      cluster_ids = changed |> Enum.filter(&(&1.type == :cluster)) |> Enum.map(& &1.id)
      assert "cluster-row-1" in cluster_ids
      assert "cluster-row-5" in cluster_ids
    end
  end

  # ---------------------------------------------------------------------------
  # Defect 2: correct call count (tool_use + tool_result = 1 call)
  # ---------------------------------------------------------------------------

  describe "cluster meta :count — actual calls, not raw events" do
    test "one tool_use + one tool_result counts as 1 call" do
      messages = [tool_msg(1, "tool_use"), result_msg(2)]
      rows = MessageGrouper.grouped_rows(messages)

      cluster = Enum.find(rows, &(&1.type == :cluster))
      assert cluster.meta.count == 1
    end

    test "two tool_use events count as 2 calls" do
      messages = [tool_msg(1, "tool_use"), tool_msg(2, "tool_use")]
      rows = MessageGrouper.grouped_rows(messages)

      cluster = Enum.find(rows, &(&1.type == :cluster))
      assert cluster.meta.count == 2
    end

    test "result-only cluster has result_only: true and count > 0 (event count, not call count)" do
      messages = [result_msg(1), result_msg(2)]
      rows = MessageGrouper.grouped_rows(messages)

      cluster = Enum.find(rows, &(&1.type == :cluster))
      assert cluster.meta.result_only == true
      # count reflects the number of result events (not 0) so the UI can display "2 results"
      assert cluster.meta.count == 2
    end

    test "non-result-only cluster has result_only: false" do
      messages = [tool_msg(1, "tool_use"), result_msg(2)]
      rows = MessageGrouper.grouped_rows(messages)

      cluster = Enum.find(rows, &(&1.type == :cluster))
      assert cluster.meta.result_only == false
    end

    test "body-format message with two calls counts as 2" do
      body = "> `Write` path/to/a.txt\n\n> `Edit` path/to/b.txt"
      messages = [body_call_msg(1, body)]
      rows = MessageGrouper.grouped_rows(messages)

      cluster = Enum.find(rows, &(&1.type == :cluster))
      assert cluster.meta.count == 2
    end

    test "body-format message with single Tool: header counts as 1" do
      body = "Tool: Bash\n{\"command\": \"ls\"}"
      messages = [body_call_msg(1, body)]
      rows = MessageGrouper.grouped_rows(messages)

      cluster = Enum.find(rows, &(&1.type == :cluster))
      assert cluster.meta.count == 1
    end

    test "mixed cluster: one tool_use + two body calls = 3" do
      body = "> `Write` a.txt\n\n> `Read` b.txt"
      messages = [tool_msg(1, "tool_use"), body_call_msg(2, body)]
      rows = MessageGrouper.grouped_rows(messages)

      cluster = Enum.find(rows, &(&1.type == :cluster))
      assert cluster.meta.count == 3
    end
  end

  # ---------------------------------------------------------------------------
  # Defect 3: body-format detection is role-aware
  # ---------------------------------------------------------------------------

  describe "group_events/1 — role-aware body detection" do
    test "user message starting with '> `Name`' is NOT clustered" do
      messages = [user_msg(1, "> `SomeTool` arg")]
      rows = MessageGrouper.grouped_rows(messages)

      assert length(rows) == 1
      assert List.first(rows).type == :message
    end

    test "user message starting with 'Tool: ' is NOT clustered" do
      messages = [user_msg(1, "Tool: please run this for me")]
      rows = MessageGrouper.grouped_rows(messages)

      assert length(rows) == 1
      assert List.first(rows).type == :message
    end

    test "system message starting with '> `Name`' is NOT clustered" do
      messages = [msg(1, role: "system", body: "> `ToolName` arg")]
      rows = MessageGrouper.grouped_rows(messages)

      assert length(rows) == 1
      assert List.first(rows).type == :message
    end

    test "agent message starting with '> `Name`' IS clustered" do
      messages = [body_call_msg(1, "> `Write` /tmp/file.txt\ncontents")]
      rows = MessageGrouper.grouped_rows(messages)

      assert length(rows) == 2
      assert Enum.any?(rows, &(&1.type == :cluster))
    end

    test "agent message starting with 'Tool: ' IS clustered" do
      messages = [body_call_msg(1, "Tool: Bash\n{\"command\": \"pwd\"}")]
      rows = MessageGrouper.grouped_rows(messages)

      assert length(rows) == 2
      assert Enum.any?(rows, &(&1.type == :cluster))
    end

    test "user message adjacent to tool events stays separate" do
      messages = [
        tool_msg(1, "tool_use"),
        user_msg(2, "> `FakeToolCall` arg"),
        tool_msg(3, "tool_use")
      ]

      rows = MessageGrouper.grouped_rows(messages)

      # Should be: cluster(1), message(2), cluster(3)
      types = rows |> Enum.reject(&(&1.type == :cluster_summary)) |> Enum.map(& &1.type)
      assert types == [:cluster, :message, :cluster]
    end
  end

  # ---------------------------------------------------------------------------
  # Regression: basic grouping still works after changes
  # ---------------------------------------------------------------------------

  describe "group_events/1 — basic grouping" do
    test "standalone user message becomes a message row" do
      rows = MessageGrouper.grouped_rows([user_msg(1, "hello")])
      assert [%{type: :message}] = rows
    end

    test "single tool_use event becomes a cluster + summary" do
      rows = MessageGrouper.grouped_rows([tool_msg(1)])
      types = Enum.map(rows, & &1.type)
      assert :cluster in types
      assert :cluster_summary in types
    end

    test "mixed sequence groups correctly" do
      messages = [
        user_msg(1, "hi"),
        tool_msg(2, "tool_use"),
        result_msg(3),
        user_msg(4, "done")
      ]

      rows = MessageGrouper.grouped_rows(messages)
      types = rows |> Enum.reject(&(&1.type == :cluster_summary)) |> Enum.map(& &1.type)
      assert types == [:message, :cluster, :message]
    end
  end
end
