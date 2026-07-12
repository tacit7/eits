defmodule EyeInTheSkyWeb.DmLive.MessageGrouperRegressionTest do
  @moduledoc """
  Regression tests for MessageGrouper covering five contract requirements:

  1. >10 consecutive tool events must not shift cluster identity or produce
     duplicate/stale cluster rows during incremental diff_from_cached_tail calls.
  2. Cluster meta.count must reflect tool *calls* (tool_use + tool_result = 1),
     and multiple calls in a single message body must each be counted. Result-only
     runs must not report "0 tool calls".
  3. User and system messages whose body starts with "Tool:" or "> `Name`" must
     remain normal :message rows, not be clustered.

  These tests are intentionally written against the *required* behavior. On the
  baseline branch (pre-fix) they are expected to fail. Once the streaming-fixer
  integration branch is merged, all assertions here must pass.
  """

  use ExUnit.Case, async: true

  alias EyeInTheSkyWeb.DmLive.MessageGrouper

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp msg(id, opts \\ []) do
    %{
      id: id,
      sender_role: Keyword.get(opts, :sender_role, "assistant"),
      body: Keyword.get(opts, :body, nil),
      metadata: Keyword.get(opts, :metadata, nil),
      inserted_at: DateTime.add(~U[2026-01-01 00:00:00Z], id, :second)
    }
  end

  defp tool_msg(id, opts \\ []) do
    stream_type = Keyword.get(opts, :stream_type, "tool_use")
    tool_name = Keyword.get(opts, :tool_name, "Bash")

    metadata = %{
      "stream_type" => stream_type,
      "tool_name" => tool_name
    }

    msg(id, Keyword.merge(opts, metadata: metadata))
  end

  defp cluster_row_id_of(rows) do
    case Enum.find(rows, &(&1.type == :cluster)) do
      nil -> nil
      row -> row.id
    end
  end

  # ---------------------------------------------------------------------------
  # Contract 1: >10 consecutive tool events — cluster identity stability
  # ---------------------------------------------------------------------------

  describe "cluster identity with >10 consecutive tool events" do
    test "grouped_rows for 15 tool events produces exactly 2 rows (cluster + summary)" do
      events = Enum.map(1..15, &tool_msg/1)
      rows = MessageGrouper.grouped_rows(events)

      assert length(rows) == 2
      assert Enum.any?(rows, &(&1.type == :cluster))
      assert Enum.any?(rows, &(&1.type == :cluster_summary))
    end

    test "cluster row id is anchored to the first event, not first in tail window" do
      # 15 tool events: the tail window is 10, so take(-10) gives events 6..15.
      # The cluster id must reference event 1 (the true first), not event 6.
      events = Enum.map(1..15, &tool_msg/1)
      rows = MessageGrouper.grouped_rows(events)

      cluster = Enum.find(rows, &(&1.type == :cluster))
      first_event = List.first(events)

      # Expected: "cluster-row-1" — fails on baseline which computes id from tail[0]
      assert cluster.id == "cluster-row-#{first_event.id}",
             "cluster id #{inspect(cluster.id)} should be cluster-row-#{first_event.id}"
    end

    test "diff_from_cached_tail does not shift cluster id when a 16th event arrives" do
      # Simulate the incremental path: 15 events cached, then event 16 arrives.
      events_15 = Enum.map(1..15, &tool_msg/1)

      # Compute what the socket would have stored as last_stream_tail after 15 events.
      {_changed_15, cached_tail_15} = MessageGrouper.diff_from_cached_tail([], events_15)

      # Record the cluster id that was emitted after 15 events.
      old_cluster_id = cluster_row_id_of(cached_tail_15)

      # Now a 16th event arrives.
      events_16 = events_15 ++ [tool_msg(16)]
      {changed_16, _new_tail_16} = MessageGrouper.diff_from_cached_tail(cached_tail_15, events_16)

      new_cluster_ids = Enum.map(changed_16, & &1.id) |> Enum.filter(&String.starts_with?(&1, "cluster-row-"))

      # The only changed cluster row id must be the same stable id (no shift).
      # Baseline will emit a NEW cluster-row-7 while cluster-row-6 becomes stale.
      for new_id <- new_cluster_ids do
        assert new_id == old_cluster_id,
               "cluster id shifted from #{old_cluster_id} to #{new_id}; stale row leaked"
      end
    end

    test "diff_from_cached_tail emits at most 2 changed rows (cluster + summary) for one new tool event" do
      events_11 = Enum.map(1..11, &tool_msg/1)
      {_changed_11, cached_tail_11} = MessageGrouper.diff_from_cached_tail([], events_11)

      events_12 = events_11 ++ [tool_msg(12)]
      {changed_12, _new_tail_12} = MessageGrouper.diff_from_cached_tail(cached_tail_11, events_12)

      # Adding one more tool event to an existing cluster must update at most 2 rows
      # (the cluster row and its summary). Producing 4 rows means stale rows leaked.
      assert length(changed_12) <= 2,
             "expected ≤2 changed rows, got #{length(changed_12)}: #{inspect(Enum.map(changed_12, & &1.id))}"
    end

    test "no shifted cluster row id leaks after tail-window boundary" do
      events_14 = Enum.map(1..14, &tool_msg/1)
      {_c14, cached_14} = MessageGrouper.diff_from_cached_tail([], events_14)

      old_cluster_id = cluster_row_id_of(cached_14)

      events_15 = events_14 ++ [tool_msg(15)]
      {changed_15, _new_15} = MessageGrouper.diff_from_cached_tail(cached_14, events_15)

      changed_cluster_ids =
        changed_15
        |> Enum.map(& &1.id)
        |> Enum.filter(&String.starts_with?(&1, "cluster-row-"))

      for id <- changed_cluster_ids do
        assert id == old_cluster_id,
               "cluster id shifted from #{old_cluster_id} to #{id}; stale row leaked"
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Contract 2: Cluster summary accuracy
  # ---------------------------------------------------------------------------

  describe "tool call count accuracy" do
    test "1 tool_use + 1 matching tool_result counts as 1 call in meta.count" do
      events = [
        tool_msg(1, stream_type: "tool_use", tool_name: "Bash"),
        tool_msg(2, stream_type: "tool_result", tool_name: "Bash")
      ]

      rows = MessageGrouper.grouped_rows(events)
      cluster = Enum.find(rows, &(&1.type == :cluster))

      # Contract: a call-pair is one call.
      # Baseline: meta.count == 2 (every event counted separately). EXPECTED FAIL.
      assert cluster.meta.count == 1,
             "1 tool_use + 1 tool_result should be 1 call, got #{cluster.meta.count}"
    end

    test "3 tool_use + 3 tool_result pairs count as 3 calls" do
      events =
        Enum.flat_map(1..3, fn i ->
          [
            tool_msg(i * 2 - 1, stream_type: "tool_use", tool_name: "Bash"),
            tool_msg(i * 2, stream_type: "tool_result", tool_name: "Bash")
          ]
        end)

      rows = MessageGrouper.grouped_rows(events)
      cluster = Enum.find(rows, &(&1.type == :cluster))

      # Baseline: count == 6. EXPECTED FAIL.
      assert cluster.meta.count == 3,
             "3 tool_use+result pairs should be 3 calls, got #{cluster.meta.count}"
    end

    test "single message body with 2 tool calls is counted as 2 calls" do
      # A single assistant message encoding two tool calls in its body.
      body = "> `Bash` {\"command\":\"echo hello\"}\n\n> `Read` {\"file_path\":\"/tmp/a\"}"

      events = [
        msg(1,
          sender_role: "assistant",
          body: body,
          metadata: nil
        )
      ]

      rows = MessageGrouper.grouped_rows(events)
      cluster = Enum.find(rows, &(&1.type == :cluster))

      # Contract: each parsed tool call segment counts separately.
      # Baseline: count == 1 (one event, one body). EXPECTED FAIL.
      assert cluster.meta.count == 2,
             "body encoding 2 tool calls should count as 2, got #{cluster.meta.count}"
    end

    test "result-only cluster does not report 0 tool calls in meta" do
      # Legacy result-only stream: only tool_result events, no tool_use.
      events = Enum.map(1..3, &tool_msg(&1, stream_type: "tool_result"))

      rows = MessageGrouper.grouped_rows(events)
      cluster = Enum.find(rows, &(&1.type == :cluster))

      # The display label must not say "0 tool calls". meta.count must be > 0.
      # Any positive number is truthful; the label in the component can say "results".
      refute cluster.meta.count == 0,
             "result-only cluster must have count > 0, not #{cluster.meta.count}"
    end
  end

  # ---------------------------------------------------------------------------
  # Contract 3: Sender-role false positives
  # ---------------------------------------------------------------------------

  describe "user and system prose with tool-like body prefixes" do
    test "user message starting with '> `Name`' is a normal :message row, not clustered" do
      messages = [
        msg(1, sender_role: "user", body: "> `Bash` echo hello")
      ]

      rows = MessageGrouper.grouped_rows(messages)
      assert length(rows) == 1

      # Baseline: body_is_tool_message? fires regardless of role → :cluster. EXPECTED FAIL.
      assert hd(rows).type == :message,
             "user message with tool-like body should be :message, got :cluster"
    end

    test "system message starting with 'Tool:' is a normal :message row, not clustered" do
      messages = [
        msg(1, sender_role: "system", body: "Tool: SomeThing\n{}")
      ]

      rows = MessageGrouper.grouped_rows(messages)
      assert length(rows) == 1

      # Baseline: body_is_tool_message? fires regardless of role → :cluster. EXPECTED FAIL.
      assert hd(rows).type == :message,
             "system message with 'Tool:' body should be :message, got :cluster"
    end

    test "user message starting with '> `Name`' is not merged into adjacent tool cluster" do
      # A user message appearing after real tool events must NOT extend the cluster.
      messages = [
        tool_msg(1, stream_type: "tool_use"),
        msg(2, sender_role: "user", body: "> `Bash` echo inserted by user")
      ]

      rows = MessageGrouper.grouped_rows(messages)
      cluster = Enum.find(rows, &(&1.type == :cluster))
      user_row = Enum.find(rows, &(&1.type == :message))

      # The user message must not be absorbed into the tool cluster.
      # Baseline: both events end up in one cluster. EXPECTED FAIL.
      assert user_row != nil,
             "user message must remain a :message row; cluster absorbed it"

      assert cluster != nil && length(cluster.data) == 1,
             "tool cluster must contain only the tool_use event, not the user message"
    end

    test "assistant message starting with '> `Name`' IS clustered (imported format)" do
      # Assistant messages with tool-like bodies should still cluster.
      messages = [
        msg(1, sender_role: "assistant", body: "> `Bash` {\"command\":\"echo hello\"}")
      ]

      rows = MessageGrouper.grouped_rows(messages)
      # This must remain a cluster (the fix must not over-correct).
      assert Enum.any?(rows, &(&1.type == :cluster)),
             "assistant message with tool body should still be clustered"
    end

    test "system prose starting with '> `Name`' is not merged with prior tool cluster" do
      messages = [
        tool_msg(1, stream_type: "tool_result"),
        msg(2, sender_role: "system", body: "> `Note` this is a system annotation")
      ]

      rows = MessageGrouper.grouped_rows(messages)

      # System message must be a separate :message row.
      # Baseline: the system message body triggers body_is_tool_message? → merged. EXPECTED FAIL.
      assert Enum.any?(rows, &(&1.type == :message)),
             "system message must not be absorbed into the preceding tool cluster"
    end
  end
end
