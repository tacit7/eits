defmodule EyeInTheSkyWeb.Components.Rail.Flyout.AgentsSectionTest do
  use EyeInTheSkyWeb.ConnCase
  import Phoenix.LiveViewTest

  alias EyeInTheSkyWeb.Components.Rail.Flyout.AgentsSection

  describe "agents_filters/1" do
    test "renders search input" do
      html =
        render_component(
          &AgentsSection.agents_filters/1,
          agent_search: "",
          agent_scope: "all",
          myself: 1
        )

      assert html =~ "Search agents"
      assert html =~ "magnifying-glass"
    end

    test "renders search input with current value" do
      html =
        render_component(
          &AgentsSection.agents_filters/1,
          agent_search: "test-agent",
          agent_scope: "all",
          myself: 1
        )

      assert html =~ "value=\"test-agent\""
    end

    test "renders scope pills with all scope selected" do
      html =
        render_component(
          &AgentsSection.agents_filters/1,
          agent_search: "",
          agent_scope: "all",
          myself: 1
        )

      assert html =~ "All"
      assert html =~ "Global"
      assert html =~ "Project"
      assert html =~ "bg-primary/15"
    end

    test "renders correct scope pill as active" do
      html =
        render_component(
          &AgentsSection.agents_filters/1,
          agent_search: "",
          agent_scope: "global",
          myself: 1
        )

      assert html =~ "Global"
      assert html =~ "bg-primary/15"
    end

    test "renders search with debounce" do
      html =
        render_component(
          &AgentsSection.agents_filters/1,
          agent_search: "",
          agent_scope: "all",
          myself: 1
        )

      assert html =~ "phx-debounce"
      assert html =~ "200"
    end

    test "renders phx-keyup event for search" do
      html =
        render_component(
          &AgentsSection.agents_filters/1,
          agent_search: "",
          agent_scope: "all",
          myself: 1
        )

      assert html =~ "update_agent_search"
    end

    test "renders phx-target pointing to myself" do
      html =
        render_component(
          &AgentsSection.agents_filters/1,
          agent_search: "",
          agent_scope: "all",
          myself: 1
        )

      assert html =~ "phx-target"
    end
  end

  describe "agents_content/1" do
    test "renders empty message when no agents" do
      html =
        render_component(
          &AgentsSection.agents_content/1,
          agents: [],
          myself: 1
        )

      assert html =~ "No agents"
    end

    test "renders agent list" do
      agents = [
        %{id: 1, slug: "agent-1", name: "Code Reviewer"},
        %{id: 2, slug: "agent-2", name: "Test Writer"}
      ]

      html =
        render_component(
          &AgentsSection.agents_content/1,
          agents: agents,
          myself: 1
        )

      assert html =~ "Code Reviewer"
      assert html =~ "Test Writer"
    end

    test "renders agent row icon for each agent" do
      agents = [
        %{id: 1, slug: "agent-1", name: "Code Reviewer"},
        %{id: 2, slug: "agent-2", name: "Test Writer"}
      ]

      html =
        render_component(
          &AgentsSection.agents_content/1,
          agents: agents,
          myself: 1
        )

      # Robot icon renders as inline SVG; assert on a distinctive path segment
      assert html =~ "M12 8V4H8"
    end
  end

  describe "agent_row/1" do
    test "renders agent button with agent name" do
      agent = %{id: 1, slug: "reviewer", name: "Code Reviewer"}

      html =
        render_component(
          &AgentsSection.agent_row/1,
          agent: agent,
          myself: 1
        )

      assert html =~ "Code Reviewer"
    end

    test "renders agent slug as fallback when name is nil" do
      agent = %{id: 1, slug: "reviewer", name: nil}

      html =
        render_component(
          &AgentsSection.agent_row/1,
          agent: agent,
          myself: 1
        )

      assert html =~ "reviewer"
    end

    test "renders robot icon" do
      agent = %{id: 1, slug: "agent", name: "Test"}

      html =
        render_component(
          &AgentsSection.agent_row/1,
          agent: agent,
          myself: 1
        )

      # Robot icon renders as inline SVG; assert on a distinctive path segment
      assert html =~ "M12 8V4H8"
    end

    test "renders button with open_new_session_with_agent event" do
      agent = %{id: 1, slug: "reviewer", name: "Code Reviewer"}

      html =
        render_component(
          &AgentsSection.agent_row/1,
          agent: agent,
          myself: 1
        )

      assert html =~ "open_new_session_with_agent"
      assert html =~ "phx-value-slug=\"reviewer\""
      assert html =~ "phx-value-name=\"Code Reviewer\""
    end

    test "renders vim navigation attribute" do
      agent = %{id: 1, slug: "agent", name: "Test"}

      html =
        render_component(
          &AgentsSection.agent_row/1,
          agent: agent,
          myself: 1
        )

      assert html =~ "data-vim-flyout-item"
    end

    test "renders hover styles" do
      agent = %{id: 1, slug: "agent", name: "Test"}

      html =
        render_component(
          &AgentsSection.agent_row/1,
          agent: agent,
          myself: 1
        )

      assert html =~ "hover:bg-base-content/5"
    end

    test "renders truncate on long agent names" do
      agent = %{id: 1, slug: "agent", name: "Test"}

      html =
        render_component(
          &AgentsSection.agent_row/1,
          agent: agent,
          myself: 1
        )

      assert html =~ "truncate"
    end
  end
end
