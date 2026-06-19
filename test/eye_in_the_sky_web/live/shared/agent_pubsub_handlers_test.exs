defmodule EyeInTheSkyWeb.Live.Shared.AgentPubSubHandlersTest do
  use EyeInTheSky.DataCase, async: true

  alias EyeInTheSkyWeb.Live.Shared.AgentPubSubHandlers

  # Builds a minimal Phoenix.LiveView.Socket with the given assigns.
  defp build_socket(assigns) do
    base = %{__changed__: %{}, flash: %{}}
    %Phoenix.LiveView.Socket{assigns: Map.merge(base, assigns)}
  end

  # Returns a simple agent-like map comparable to what LiveViews hold in lists.
  defp agent_map(id, status \\ "working") do
    %{
      id: id,
      status: status,
      name: "agent-#{id}",
      last_activity_at: DateTime.utc_now()
    }
  end

  # ──────────────────────────────────────────────────────────────
  # extract_stopped_status/1
  # ──────────────────────────────────────────────────────────────
  describe "extract_stopped_status/1" do
    test "returns status string when present and non-empty" do
      assert AgentPubSubHandlers.extract_stopped_status(%{status: "waiting"}) == "waiting"
      assert AgentPubSubHandlers.extract_stopped_status(%{status: "idle"}) == "idle"
    end

    test "returns 'idle' when status is an empty string" do
      assert AgentPubSubHandlers.extract_stopped_status(%{status: ""}) == "idle"
    end

    test "returns 'idle' when status is nil" do
      assert AgentPubSubHandlers.extract_stopped_status(%{status: nil}) == "idle"
    end

    test "returns 'idle' when message has no status key" do
      assert AgentPubSubHandlers.extract_stopped_status(%{id: 1}) == "idle"
    end
  end

  # ──────────────────────────────────────────────────────────────
  # update_agent_list/5
  # ──────────────────────────────────────────────────────────────
  describe "update_agent_list/5" do
    test "updates status of the matching agent and leaves others unchanged" do
      agents = [agent_map(1, "working"), agent_map(2, "working"), agent_map(3, "idle")]
      socket = build_socket(%{agents: agents})

      result_socket = AgentPubSubHandlers.update_agent_list(socket, :agents, 2, "idle", nil)

      updated = result_socket.assigns.agents
      assert Enum.find(updated, &(&1.id == 1)).status == "working"
      assert Enum.find(updated, &(&1.id == 2)).status == "idle"
      assert Enum.find(updated, &(&1.id == 3)).status == "idle"
    end

    test "does nothing when session_id does not match any agent" do
      agents = [agent_map(1, "working")]
      socket = build_socket(%{agents: agents})

      result_socket = AgentPubSubHandlers.update_agent_list(socket, :agents, 99, "idle", nil)

      assert result_socket.assigns.agents == result_socket.assigns.agents
      assert Enum.find(result_socket.assigns.agents, &(&1.id == 1)).status == "working"
    end

    test "uses a custom assign_key" do
      agents = [agent_map(5, "working")]
      socket = build_socket(%{my_sessions: agents})

      result_socket =
        AgentPubSubHandlers.update_agent_list(socket, :my_sessions, 5, "idle", nil)

      assert Enum.find(result_socket.assigns.my_sessions, &(&1.id == 5)).status == "idle"
    end

    test "applies sort_by 'name' after status update" do
      agents = [agent_map(3, "working"), agent_map(1, "working"), agent_map(2, "working")]

      for a <- agents do
        a = Map.put(a, :last_message_at, nil)
        _ = a
      end

      socket = build_socket(%{agents: agents})
      result = AgentPubSubHandlers.update_agent_list(socket, :agents, 2, "idle", "name")
      names = Enum.map(result.assigns.agents, & &1.name)
      assert names == Enum.sort(names)
    end
  end

  # ──────────────────────────────────────────────────────────────
  # handle_agent_working_in_list/4
  # ──────────────────────────────────────────────────────────────
  describe "handle_agent_working_in_list/4" do
    test "marks the matching agent as working" do
      agents = [agent_map(10, "idle"), agent_map(11, "idle")]
      socket = build_socket(%{agents: agents, sort_by: nil})

      msg = %{id: 10}
      {:noreply, result} = AgentPubSubHandlers.handle_agent_working_in_list(socket, msg)

      assert Enum.find(result.assigns.agents, &(&1.id == 10)).status == "working"
      assert Enum.find(result.assigns.agents, &(&1.id == 11)).status == "idle"
    end

    test "no-ops when message id is nil" do
      agents = [agent_map(1, "idle")]
      socket = build_socket(%{agents: agents, sort_by: nil})

      {:noreply, result} = AgentPubSubHandlers.handle_agent_working_in_list(socket, %{id: nil})

      assert result.assigns.agents == agents
    end

    test "uses sort_by from assigns when not provided explicitly" do
      agents = [agent_map(2, "idle"), agent_map(1, "idle")]
      socket = build_socket(%{agents: agents, sort_by: "name"})

      msg = %{id: 1}
      {:noreply, result} = AgentPubSubHandlers.handle_agent_working_in_list(socket, msg)

      names = Enum.map(result.assigns.agents, & &1.name)
      assert names == Enum.sort(names)
    end
  end

  # ──────────────────────────────────────────────────────────────
  # handle_agent_stopped_in_list/4
  # ──────────────────────────────────────────────────────────────
  describe "handle_agent_stopped_in_list/4" do
    test "applies the message status to the matching agent" do
      agents = [agent_map(20, "working")]
      socket = build_socket(%{agents: agents, sort_by: nil})

      msg = %{id: 20, status: "completed"}
      {:noreply, result} = AgentPubSubHandlers.handle_agent_stopped_in_list(socket, msg)

      assert Enum.find(result.assigns.agents, &(&1.id == 20)).status == "completed"
    end

    test "defaults to 'idle' when status is missing" do
      agents = [agent_map(21, "working")]
      socket = build_socket(%{agents: agents, sort_by: nil})

      msg = %{id: 21}
      {:noreply, result} = AgentPubSubHandlers.handle_agent_stopped_in_list(socket, msg)

      assert Enum.find(result.assigns.agents, &(&1.id == 21)).status == "idle"
    end

    test "no-ops when message id is nil" do
      agents = [agent_map(1, "working")]
      socket = build_socket(%{agents: agents, sort_by: nil})

      {:noreply, result} =
        AgentPubSubHandlers.handle_agent_stopped_in_list(socket, %{id: nil, status: "idle"})

      assert Enum.find(result.assigns.agents, &(&1.id == 1)).status == "working"
    end
  end

  # ──────────────────────────────────────────────────────────────
  # handle_agent_working_mapsets/2
  # ──────────────────────────────────────────────────────────────
  describe "handle_agent_working_mapsets/2" do
    test "moves session from waiting to working" do
      socket =
        build_socket(%{
          working_session_ids: MapSet.new([]),
          waiting_session_ids: MapSet.new([5])
        })

      {:noreply, result} =
        AgentPubSubHandlers.handle_agent_working_mapsets(socket, %{id: 5})

      assert MapSet.member?(result.assigns.working_session_ids, 5)
      refute MapSet.member?(result.assigns.waiting_session_ids, 5)
    end

    test "adds session to working even when not in waiting" do
      socket =
        build_socket(%{
          working_session_ids: MapSet.new([]),
          waiting_session_ids: MapSet.new([])
        })

      {:noreply, result} =
        AgentPubSubHandlers.handle_agent_working_mapsets(socket, %{id: 7})

      assert MapSet.member?(result.assigns.working_session_ids, 7)
    end

    test "no-ops when id is nil" do
      socket =
        build_socket(%{
          working_session_ids: MapSet.new([1]),
          waiting_session_ids: MapSet.new([2])
        })

      {:noreply, result} =
        AgentPubSubHandlers.handle_agent_working_mapsets(socket, %{id: nil})

      assert result.assigns.working_session_ids == MapSet.new([1])
      assert result.assigns.waiting_session_ids == MapSet.new([2])
    end
  end

  # ──────────────────────────────────────────────────────────────
  # handle_agent_stopped_mapsets/2
  # ──────────────────────────────────────────────────────────────
  describe "handle_agent_stopped_mapsets/2" do
    test "removes session from both working and waiting sets" do
      socket =
        build_socket(%{
          working_session_ids: MapSet.new([3, 4]),
          waiting_session_ids: MapSet.new([3])
        })

      {:noreply, result} =
        AgentPubSubHandlers.handle_agent_stopped_mapsets(socket, %{id: 3, status: "idle"})

      refute MapSet.member?(result.assigns.working_session_ids, 3)
      refute MapSet.member?(result.assigns.waiting_session_ids, 3)
      assert MapSet.member?(result.assigns.working_session_ids, 4)
    end

    test "no-ops when id is nil" do
      socket =
        build_socket(%{
          working_session_ids: MapSet.new([9]),
          waiting_session_ids: MapSet.new([])
        })

      {:noreply, result} =
        AgentPubSubHandlers.handle_agent_stopped_mapsets(socket, %{id: nil, status: "idle"})

      assert MapSet.member?(result.assigns.working_session_ids, 9)
    end
  end

  # ──────────────────────────────────────────────────────────────
  # handle_agent_stopped_waiting_mapsets/2
  # ──────────────────────────────────────────────────────────────
  describe "handle_agent_stopped_waiting_mapsets/2" do
    test "moves session from working to waiting on 'waiting' status" do
      socket =
        build_socket(%{
          working_session_ids: MapSet.new([6]),
          waiting_session_ids: MapSet.new([])
        })

      {:noreply, result} =
        AgentPubSubHandlers.handle_agent_stopped_waiting_mapsets(socket, %{
          id: 6,
          status: "waiting"
        })

      refute MapSet.member?(result.assigns.working_session_ids, 6)
      assert MapSet.member?(result.assigns.waiting_session_ids, 6)
    end

    test "no-ops when status is not 'waiting'" do
      socket =
        build_socket(%{
          working_session_ids: MapSet.new([8]),
          waiting_session_ids: MapSet.new([])
        })

      {:noreply, result} =
        AgentPubSubHandlers.handle_agent_stopped_waiting_mapsets(socket, %{
          id: 8,
          status: "idle"
        })

      # socket unchanged — passed through the catch-all clause
      assert result.assigns.working_session_ids == MapSet.new([8])
      assert result.assigns.waiting_session_ids == MapSet.new([])
    end

    test "no-ops when message does not match waiting pattern" do
      socket =
        build_socket(%{
          working_session_ids: MapSet.new([]),
          waiting_session_ids: MapSet.new([])
        })

      {:noreply, result} =
        AgentPubSubHandlers.handle_agent_stopped_waiting_mapsets(socket, %{id: 99})

      assert result.assigns.working_session_ids == MapSet.new([])
    end
  end
end
