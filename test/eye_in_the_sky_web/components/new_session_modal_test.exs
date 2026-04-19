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
  # Filter logic (pure unit tests — no DB needed but ConnCase provides sandbox)
  # -------------------------------------------------------------------------

  describe "agent filtering logic" do
    test "empty query returns all agents" do
      assert filter_agents(@agents, "") == @agents
    end

    test "matches on slug substring" do
      result = filter_agents(@agents, "eits")
      slugs = Enum.map(result, &elem(&1, 0))
      assert slugs == ["eits-superpowers", "eits-workflow"]
    end

    test "matches on name substring case-insensitively" do
      result = filter_agents(@agents, "code")
      slugs = Enum.map(result, &elem(&1, 0))
      assert slugs == ["code-reviewer"]
    end

    test "returns empty list when nothing matches" do
      assert filter_agents(@agents, "zzznomatch") == []
    end

    test "case-insensitive slug match" do
      assert filter_agents(@agents, "EITS") |> length() == 2
    end

    test "case-insensitive name match" do
      result = filter_agents(@agents, "BUG")
      assert Enum.map(result, &elem(&1, 0)) == ["bugfix"]
    end
  end

  # -------------------------------------------------------------------------
  # Component rendering — verifies HTML structure and phx-change wiring
  # -------------------------------------------------------------------------

  describe "component rendering" do
    test "renders filter input with correct phx-change attribute when agents present" do
      html = render_component(NewSessionModal, base_assigns())

      assert html =~ ~s(phx-change="agent_search_changed")
      assert html =~ ~s(name="agent_search")
      assert html =~ "Filter agents..."
    end

    test "does not render filter input when no agents available" do
      html = render_component(NewSessionModal, base_assigns(%{available_agents: []}))

      refute html =~ ~s(name="agent_search")
      refute html =~ "Filter agents..."
    end

    test "renders all agents in select when agent_search is empty" do
      html = render_component(NewSessionModal, base_assigns(%{agent_search: ""}))

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

    test "renders empty-state message when no agents match the search" do
      html = render_component(NewSessionModal, base_assigns(%{agent_search: "zzznomatch"}))

      assert html =~ ~s(No agents match)
      assert html =~ "zzznomatch"
    end

    test "does not render empty-state message when agents match" do
      html = render_component(NewSessionModal, base_assigns(%{agent_search: "eits"}))

      refute html =~ "No agents match"
    end
  end

  # -------------------------------------------------------------------------
  # Mirrors the inline filtering in render/1 — stays in sync with the component
  # -------------------------------------------------------------------------

  defp filter_agents(agents, "") do
    agents
  end

  defp filter_agents(agents, query) do
    q = String.downcase(query)

    Enum.filter(agents, fn {slug, name, _scope} ->
      String.contains?(String.downcase(slug), q) or
        String.contains?(String.downcase(name), q)
    end)
  end
end
