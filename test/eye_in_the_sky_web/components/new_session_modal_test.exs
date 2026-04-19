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

  describe "datalist agent field" do
    test "renders datalist with all agents when agents present" do
      html = render_component(NewSessionModal, base_assigns())

      assert html =~ ~s(<datalist id="agent-options">)
      assert html =~ ~s(value="eits-superpowers")
      assert html =~ "EITS Superpowers"
      assert html =~ ~s(value="bugfix")
      assert html =~ "Bug Fixer"
    end

    test "renders input linked to datalist" do
      html = render_component(NewSessionModal, base_assigns())

      assert html =~ ~s(list="agent-options")
      assert html =~ ~s(name="agent")
      assert html =~ "Search agents..."
    end

    test "does not render agent field when no agents available" do
      html = render_component(NewSessionModal, base_assigns(%{available_agents: []}))

      refute html =~ ~s(list="agent-options")
      refute html =~ ~s(<datalist)
    end

    test "marks project-scoped agents with (project) suffix" do
      html = render_component(NewSessionModal, base_assigns())

      assert html =~ "Code Reviewer (project)"
    end

    test "global agents have no scope suffix" do
      html = render_component(NewSessionModal, base_assigns())

      assert html =~ ">EITS Superpowers<"
      refute html =~ "EITS Superpowers (global)"
    end
  end

  describe "module exports" do
    test "NewSessionModal is compiled and exports render/1" do
      assert Code.ensure_loaded?(NewSessionModal)
      assert function_exported?(NewSessionModal, :render, 1)
    end
  end
end
