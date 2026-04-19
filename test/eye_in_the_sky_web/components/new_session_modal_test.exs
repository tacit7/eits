defmodule EyeInTheSkyWeb.Components.NewSessionModalTest do
  use EyeInTheSkyWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  alias EyeInTheSkyWeb.Components.NewSessionModal

  @agents [
    {"eits-superpowers", "EITS Superpowers", :global},
    {"eits-workflow", "EITS Workflow", :global},
    {"bugfix", "Bug Fixer", :global},
    {"code-reviewer", "Code Reviewer", :project}
  ]

  defp base_assigns(overrides \\ %{}) do
    Map.merge(
      %{
        id: "test-modal",
        show: true,
        toggle_event: "toggle_new_session",
        submit_event: "create_session",
        prompts: [],
        projects: [],
        current_project: nil,
        available_agents: @agents,
        agent_search: "",
        file_uploads: nil
      },
      overrides
    )
  end

  # -------------------------------------------------------------------------
  # Component rendering — verifies HTML structure and phx-change wiring
  # -------------------------------------------------------------------------

  describe "agent filter input" do
    test "renders filter input with phx-change when agents present" do
      html = render_component(NewSessionModal, base_assigns())

      assert html =~ ~s(phx-change="agent_search_changed")
      assert html =~ ~s(name="agent_search")
      assert html =~ "Filter agents..."
    end

    test "does not render agent field when no agents available" do
      html = render_component(NewSessionModal, base_assigns(%{available_agents: []}))

      refute html =~ ~s(name="agent_search")
      refute html =~ "Filter agents..."
    end
  end

  describe "agent select" do
    test "renders all agents in select when agent_search is empty" do
      html = render_component(NewSessionModal, base_assigns(%{agent_search: ""}))

      assert html =~ ~s(name="agent")
      assert html =~ "EITS Superpowers"
      assert html =~ "EITS Workflow"
      assert html =~ "Bug Fixer"
      assert html =~ "Code Reviewer"
    end

    test "renders only matching agents when agent_search filters by slug" do
      html = render_component(NewSessionModal, base_assigns(%{agent_search: "eits"}))

      assert html =~ "EITS Superpowers"
      assert html =~ "EITS Workflow"
      refute html =~ "Bug Fixer"
      refute html =~ "Code Reviewer"
    end

    test "marks project-scoped agents with (project) suffix" do
      html = render_component(NewSessionModal, base_assigns(%{agent_search: ""}))

      assert html =~ "Code Reviewer (project)"
    end

    test "global agents have no scope suffix" do
      html = render_component(NewSessionModal, base_assigns(%{agent_search: ""}))

      assert html =~ "EITS Superpowers"
      refute html =~ "EITS Superpowers (global)"
    end

    test "renders empty-state message when no agents match the search" do
      html = render_component(NewSessionModal, base_assigns(%{agent_search: "zzznomatch"}))

      assert html =~ "No agents match"
      assert html =~ "zzznomatch"
    end

    test "does not render empty-state or select when agents match" do
      html = render_component(NewSessionModal, base_assigns(%{agent_search: "eits"}))

      refute html =~ "No agents match"
      assert html =~ ~s(name="agent")
    end
  end

  describe "overflow indicator" do
    test "shows overflow hint when more than 10 agents match" do
      many_agents =
        for i <- 1..12, do: {"agent-#{i}", "Agent #{i}", :global}

      html = render_component(NewSessionModal, base_assigns(%{available_agents: many_agents, agent_search: ""}))

      assert html =~ "more — type to narrow"
      assert html =~ "hero-ellipsis-horizontal"
    end

    test "does not show overflow hint when 10 or fewer agents match" do
      ten_agents =
        for i <- 1..10, do: {"agent-#{i}", "Agent #{i}", :global}

      html = render_component(NewSessionModal, base_assigns(%{available_agents: ten_agents, agent_search: ""}))

      refute html =~ "more — type to narrow"
    end

    test "overflow count reflects filtered results, not total agents" do
      many_agents =
        for i <- 1..12, do: {"eits-agent-#{i}", "EITS Agent #{i}", :global}

      # All 12 match "eits", so overflow = 2
      html = render_component(NewSessionModal, base_assigns(%{available_agents: many_agents, agent_search: "eits"}))

      assert html =~ "2 more — type to narrow"
    end
  end

  describe "module exports" do
    test "NewSessionModal is compiled and exports render/1" do
      assert Code.ensure_loaded?(NewSessionModal)
      assert function_exported?(NewSessionModal, :render, 1)
    end
  end
end
