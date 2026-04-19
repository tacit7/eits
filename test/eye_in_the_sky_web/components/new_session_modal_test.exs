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
  # JS combobox rendering — verifies HTML structure and data-agents encoding
  # -------------------------------------------------------------------------

  describe "agent combobox" do
    test "renders hook element with data-agents JSON when agents present" do
      html = render_component(NewSessionModal, base_assigns())

      assert html =~ ~s(phx-hook="AgentCombobox")
      assert html =~ ~s(data-agents=)
      assert html =~ "Search agents..."
    end

    test "does not render agent field when no agents available" do
      html = render_component(NewSessionModal, base_assigns(%{available_agents: []}))

      refute html =~ ~s(phx-hook="AgentCombobox")
      refute html =~ "Search agents..."
    end

    test "data-agents JSON contains all agent slugs" do
      html = render_component(NewSessionModal, base_assigns())

      assert html =~ "eits-superpowers"
      assert html =~ "eits-workflow"
      assert html =~ "bugfix"
      assert html =~ "code-reviewer"
    end

    test "data-agents JSON contains agent names" do
      html = render_component(NewSessionModal, base_assigns())

      assert html =~ "EITS Superpowers"
      assert html =~ "EITS Workflow"
      assert html =~ "Bug Fixer"
      assert html =~ "Code Reviewer"
    end

    test "data-agents JSON contains scope strings" do
      html = render_component(NewSessionModal, base_assigns())

      assert html =~ "global"
      assert html =~ "project"
    end

    test "all agents are encoded regardless of count" do
      many_agents = for i <- 1..15, do: {"agent-#{i}", "Agent #{i}", :global}

      html = render_component(NewSessionModal, base_assigns(%{available_agents: many_agents}))

      for i <- 1..15 do
        assert html =~ "agent-#{i}"
      end
    end

    test "renders hidden input and visible search input" do
      html = render_component(NewSessionModal, base_assigns())

      assert html =~ ~s(data-combobox-value)
      assert html =~ ~s(data-combobox-input)
      assert html =~ ~s(data-combobox-list)
    end

    test "no datalist element rendered" do
      html = render_component(NewSessionModal, base_assigns())

      refute html =~ "<datalist"
      refute html =~ "list=\"agent-options\""
    end
  end

  describe "module exports" do
    test "NewSessionModal is compiled and exports render/1" do
      assert Code.ensure_loaded?(NewSessionModal)
      assert function_exported?(NewSessionModal, :render, 1)
    end
  end
end
