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

      assert html =~ "All"
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

    test "each scope filter value sets the correct data-label" do
      for {scope, label} <- [{"all", "All"}, {"global", "Global"}, {"project", "Project"}] do
        html = render_component(&Agents.toolbar/1, %{scope_filter: scope})

        assert html =~ ~s(data-label="#{label}"),
               "expected data-label=#{label} for scope=#{scope}"
      end
    end

    test "each sort order value sets the correct data-label" do
      for {sort, label} <- [
            {"name_asc", "Name A–Z"},
            {"name_desc", "Name Z–A"},
            {"recent", "Recent"},
            {"size_desc", "Largest"},
            {"size_asc", "Smallest"}
          ] do
        html = render_component(&Agents.toolbar/1, %{sort_by: sort})
        assert html =~ ~s(data-label="#{label}"), "expected data-label=#{label} for sort=#{sort}"
      end
    end

    test "renders dropdown detail elements" do
      html = render_component(&Agents.toolbar/1, %{})

      assert html =~ "dropdown"
    end

    test "renders with default scope and sort labels when no props passed" do
      html = render_component(&Agents.toolbar/1, %{})

      assert html =~ ~s(data-label="All")
      assert html =~ ~s(data-label="Name A–Z")
    end
  end
end
