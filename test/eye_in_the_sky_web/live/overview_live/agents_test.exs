defmodule EyeInTheSkyWeb.OverviewLive.AgentsTest do
  use ExUnit.Case, async: true

  alias EyeInTheSkyWeb.OverviewLive.Agents, as: AgentsLive

  defp socket_with(assigns) do
    base = %{
      agents: [],
      filtered_agents: [],
      selected_agent: nil,
      search_query: "",
      sort_by: "name_asc",
      scope_filter: "all",
      detail_tab: :preview,
      page_title: "Agents",
      sidebar_tab: :agents,
      sidebar_project: nil,
      __changed__: %{}
    }

    %Phoenix.LiveView.Socket{assigns: Map.merge(base, assigns)}
  end

  describe "mount/3" do
    test "initializes socket with correct assigns" do
      socket = %Phoenix.LiveView.Socket{assigns: %{}}
      {:ok, result} = AgentsLive.mount(%{}, %{}, socket)

      assert result.assigns.page_title == "Agents"
      assert result.assigns.search_query == ""
      assert result.assigns.sort_by == "name_asc"
      assert result.assigns.scope_filter == "all"
      assert result.assigns.selected_agent == nil
      assert result.assigns.detail_tab == :preview
    end
  end

  describe "handle_params/3" do
    test "selects agent by id from params" do
      agent = %{id: "test-agent-1", name: "Test Agent"}
      socket = socket_with(%{agents: [agent]})

      {:noreply, result} = AgentsLive.handle_params(%{"id" => "test-agent-1"}, "", socket)

      assert result.assigns.selected_agent == agent
    end

    test "sets selected_agent to nil when id not found" do
      agent = %{id: "test-agent-1", name: "Test Agent"}
      socket = socket_with(%{agents: [agent]})

      {:noreply, result} = AgentsLive.handle_params(%{"id" => "nonexistent"}, "", socket)

      assert is_nil(result.assigns.selected_agent)
    end

    test "handles empty params without crashing" do
      socket = socket_with(%{agents: []})

      {:noreply, result} = AgentsLive.handle_params(%{}, "", socket)

      assert is_nil(result.assigns.selected_agent)
    end
  end

  describe "handle_event/3 - search" do
    test "updates search_query and reloads agents" do
      socket = socket_with(%{search_query: ""})

      {:noreply, result} = AgentsLive.handle_event("search", %{"query" => "test"}, socket)

      assert result.assigns.search_query == "test"
    end

    test "handles empty search query" do
      socket = socket_with(%{search_query: "prev"})

      {:noreply, result} = AgentsLive.handle_event("search", %{"query" => ""}, socket)

      assert result.assigns.search_query == ""
    end
  end

  describe "handle_event/3 - sort_agents" do
    test "updates sort_by to name_desc" do
      socket = socket_with(%{sort_by: "name_asc"})

      {:noreply, result} = AgentsLive.handle_event("sort_agents", %{"by" => "name_desc"}, socket)

      assert result.assigns.sort_by == "name_desc"
    end

    test "updates sort_by to recent" do
      socket = socket_with(%{sort_by: "name_asc"})

      {:noreply, result} = AgentsLive.handle_event("sort_agents", %{"by" => "recent"}, socket)

      assert result.assigns.sort_by == "recent"
    end

    test "handles size_desc sort" do
      socket = socket_with(%{sort_by: "name_asc"})

      {:noreply, result} = AgentsLive.handle_event("sort_agents", %{"by" => "size_desc"}, socket)

      assert result.assigns.sort_by == "size_desc"
    end

    test "handles size_asc sort" do
      socket = socket_with(%{sort_by: "name_asc"})

      {:noreply, result} = AgentsLive.handle_event("sort_agents", %{"by" => "size_asc"}, socket)

      assert result.assigns.sort_by == "size_asc"
    end
  end

  describe "handle_event/3 - filter_scope" do
    test "updates scope_filter to global" do
      socket = socket_with(%{scope_filter: "all"})

      {:noreply, result} = AgentsLive.handle_event("filter_scope", %{"scope" => "global"}, socket)

      assert result.assigns.scope_filter == "global"
    end

    test "updates scope_filter to project" do
      socket = socket_with(%{scope_filter: "all"})

      {:noreply, result} = AgentsLive.handle_event("filter_scope", %{"scope" => "project"}, socket)

      assert result.assigns.scope_filter == "project"
    end

    test "updates scope_filter to all" do
      socket = socket_with(%{scope_filter: "global"})

      {:noreply, result} = AgentsLive.handle_event("filter_scope", %{"scope" => "all"}, socket)

      assert result.assigns.scope_filter == "all"
    end
  end

  describe "handle_event/3 - select_agent" do
    test "selects an agent" do
      agent = %{id: "agent-1", name: "Agent 1"}
      socket = socket_with(%{agents: [agent], selected_agent: nil})

      {:noreply, result} =
        AgentsLive.handle_event("select_agent", %{"id" => "agent-1"}, socket)

      assert result.assigns.selected_agent == agent
    end

    test "deselects agent when clicking the same id again" do
      agent = %{id: "agent-1", name: "Agent 1"}
      socket = socket_with(%{agents: [agent], selected_agent: agent})

      {:noreply, result} =
        AgentsLive.handle_event("select_agent", %{"id" => "agent-1"}, socket)

      assert is_nil(result.assigns.selected_agent)
    end

    test "switches selected_agent to a different agent" do
      agent1 = %{id: "agent-1", name: "Agent 1"}
      agent2 = %{id: "agent-2", name: "Agent 2"}
      socket = socket_with(%{agents: [agent1, agent2], selected_agent: agent1})

      {:noreply, result} =
        AgentsLive.handle_event("select_agent", %{"id" => "agent-2"}, socket)

      assert result.assigns.selected_agent == agent2
    end

    test "resets detail_tab to preview when selecting a new agent" do
      agent = %{id: "agent-1", name: "Agent 1"}
      socket = socket_with(%{agents: [agent], selected_agent: nil, detail_tab: :raw})

      {:noreply, result} =
        AgentsLive.handle_event("select_agent", %{"id" => "agent-1"}, socket)

      assert result.assigns.detail_tab == :preview
    end
  end

  describe "handle_event/3 - close_viewer" do
    test "clears selected_agent" do
      agent = %{id: "agent-1", name: "Agent 1"}
      socket = socket_with(%{agents: [agent], selected_agent: agent})

      {:noreply, result} = AgentsLive.handle_event("close_viewer", %{}, socket)

      assert is_nil(result.assigns.selected_agent)
    end
  end

  describe "handle_event/3 - set_detail_tab" do
    test "accepts 'preview' and sets :preview" do
      socket = socket_with(%{detail_tab: :raw})

      {:noreply, result} =
        AgentsLive.handle_event("set_detail_tab", %{"tab" => "preview"}, socket)

      assert result.assigns.detail_tab == :preview
    end

    test "accepts 'raw' and sets :raw" do
      socket = socket_with(%{detail_tab: :preview})

      {:noreply, result} = AgentsLive.handle_event("set_detail_tab", %{"tab" => "raw"}, socket)

      assert result.assigns.detail_tab == :raw
    end

    test "ignores unknown tab values without crashing" do
      socket = socket_with(%{detail_tab: :preview})

      {:noreply, result} =
        AgentsLive.handle_event("set_detail_tab", %{"tab" => "evil_tab"}, socket)

      assert result.assigns.detail_tab == :preview
    end

    test "ignores missing tab key" do
      socket = socket_with(%{detail_tab: :preview})

      {:noreply, result} = AgentsLive.handle_event("set_detail_tab", %{}, socket)

      assert result.assigns.detail_tab == :preview
    end
  end

  describe "handle_event/3 - set_notify_on_stop" do
    test "forwards to NotificationHelpers.set_notify_on_stop" do
      socket = socket_with(%{})

      # This event is delegated to NotificationHelpers which requires proper socket setup.
      # Just verify it doesn't crash.
      result = AgentsLive.handle_event("set_notify_on_stop", %{}, socket)

      assert is_tuple(result)
      assert elem(result, 0) == :noreply
    end
  end
end
