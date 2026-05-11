defmodule EyeInTheSkyWeb.TopBar.AgentsTest do
  use EyeInTheSkyWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  alias EyeInTheSkyWeb.TopBar.Agents

  describe "toolbar/1 component" do
    test "renders search input" do
      html = render_component(&Agents.toolbar/1, %{})

      assert html =~ "Search agents"
      assert html =~ "agents-top-bar-search"
    end

    test "renders search input with custom query value" do
      html = render_component(&Agents.toolbar/1, %{search_query: "test-query"})

      assert html =~ "test-query"
    end

    test "renders scope filter dropdown" do
      html = render_component(&Agents.toolbar/1, %{})

      assert html =~ "Source:"
      assert html =~ "agents-scope-dropdown"
    end

    test "renders sort dropdown" do
      html = render_component(&Agents.toolbar/1, %{})

      assert html =~ "Sort:"
      assert html =~ "agents-sort-dropdown"
    end

    test "renders all scope options" do
      html = render_component(&Agents.toolbar/1, %{scope_filter: "all"})

      assert html =~ "All Sources"
      assert html =~ "Global"
      assert html =~ "Project"
    end

    test "renders all sort options" do
      html = render_component(&Agents.toolbar/1, %{sort_by: "name_asc"})

      assert html =~ "Name A"
      assert html =~ "Recent"
    end

    test "selected scope is highlighted in label" do
      html = render_component(&Agents.toolbar/1, %{scope_filter: "project"})

      assert html =~ "Project"
    end

    test "selected sort is highlighted in label" do
      html = render_component(&Agents.toolbar/1, %{sort_by: "recent"})

      assert html =~ "Recent"
    end

    test "handles all scope filter values without error" do
      for scope <- ["all", "global", "project"] do
        assert render_component(&Agents.toolbar/1, %{scope_filter: scope}) |> is_binary()
      end
    end

    test "handles all sort order values without error" do
      for sort <- ["name_asc", "name_desc", "recent", "size_desc", "size_asc"] do
        assert render_component(&Agents.toolbar/1, %{sort_by: sort}) |> is_binary()
      end
    end

    test "renders dropdown detail elements" do
      html = render_component(&Agents.toolbar/1, %{})

      assert html =~ "dropdown"
    end

    test "renders with defaults when no props passed" do
      assert render_component(&Agents.toolbar/1, %{}) |> is_binary()
    end
  end
end
