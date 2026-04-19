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
        file_uploads: nil
      },
      overrides
    )
  end

  # -------------------------------------------------------------------------
  # Datalist rendering — verifies HTML structure
  # -------------------------------------------------------------------------

  describe "agent datalist input" do
    test "renders search input with list attribute when agents present" do
      html = render_component(NewSessionModal, base_assigns())

      assert html =~ ~s(name="agent")
      assert html =~ ~s(list="agent-options")
      assert html =~ "Search agents..."
    end

    test "does not render agent field when no agents available" do
      html = render_component(NewSessionModal, base_assigns(%{available_agents: []}))

      refute html =~ ~s(list="agent-options")
      refute html =~ "Search agents..."
    end

    test "renders datalist with all agent slugs as options" do
      html = render_component(NewSessionModal, base_assigns())

      assert html =~ ~s(value="eits-superpowers")
      assert html =~ ~s(value="eits-workflow")
      assert html =~ ~s(value="bugfix")
      assert html =~ ~s(value="code-reviewer")
    end

    test "all agents are included regardless of count" do
      many_agents = for i <- 1..15, do: {"agent-#{i}", "Agent #{i}", :global}

      html = render_component(NewSessionModal, base_assigns(%{available_agents: many_agents}))

      for i <- 1..15 do
        assert html =~ ~s(value="agent-#{i}")
      end
    end

    test "no overflow indicator or empty-state rendered" do
      many_agents = for i <- 1..15, do: {"agent-#{i}", "Agent #{i}", :global}
      html = render_component(NewSessionModal, base_assigns(%{available_agents: many_agents}))

      refute html =~ "more — type to narrow"
      refute html =~ "No agents match"
    end
  end

  describe "module exports" do
    test "NewSessionModal is compiled and exports render/1" do
      assert Code.ensure_loaded?(NewSessionModal)
      assert function_exported?(NewSessionModal, :render, 1)
    end
  end
end
