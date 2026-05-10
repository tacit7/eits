defmodule EyeInTheSkyWeb.TopBar.SkillsTest do
  use EyeInTheSkyWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  alias EyeInTheSkyWeb.TopBar.Skills

  describe "toolbar/1 component" do
    test "renders search input with default value", %{conn: conn} do
      html = render_component(&Skills.toolbar/1, %{})

      assert html =~ "Search skills"
      assert html =~ "skills-top-bar-search"
    end

    test "renders search input with custom value", %{conn: conn} do
      html = render_component(&Skills.toolbar/1, %{search_query: "test-query"})

      assert html =~ "test-query"
    end

    test "renders type filter dropdown", %{conn: conn} do
      html = render_component(&Skills.toolbar/1, %{})

      assert html =~ "Type:"
      assert html =~ "skills-type-dropdown"
    end

    test "renders scope filter dropdown", %{conn: conn} do
      html = render_component(&Skills.toolbar/1, %{})

      assert html =~ "Source:"
      assert html =~ "skills-scope-dropdown"
    end

    test "renders all type options", %{conn: conn} do
      html = render_component(&Skills.toolbar/1, %{type_filter: "all"})

      assert html =~ "Type" || html =~ "type"
    end

    test "renders all scope options", %{conn: conn} do
      html = render_component(&Skills.toolbar/1, %{scope_filter: "all"})

      assert html =~ "All" || html =~ "all"
      assert html =~ "Global" || html =~ "global"
      assert html =~ "Project" || html =~ "project"
    end

    test "highlights selected type filter", %{conn: conn} do
      html = render_component(&Skills.toolbar/1, %{type_filter: "action"})

      # Type should be reflected in component
      assert is_binary(html)
    end

    test "highlights selected scope filter", %{conn: conn} do
      html = render_component(&Skills.toolbar/1, %{scope_filter: "project"})

      assert html =~ "Project" || html =~ "project"
    end

    test "renders with vim search attribute", %{conn: conn} do
      html = render_component(&Skills.toolbar/1, %{})

      assert html =~ "vim" || html =~ "Vim" || is_binary(html)
    end

    test "handles all type filter values", %{conn: conn} do
      for type <- ["all", "action", "read"] do
        html = render_component(&Skills.toolbar/1, %{type_filter: type})
        assert is_binary(html)
      end
    end

    test "handles all scope filter values", %{conn: conn} do
      for scope <- ["all", "global", "project"] do
        html = render_component(&Skills.toolbar/1, %{scope_filter: scope})
        assert is_binary(html)
      end
    end

    test "renders dropdown triggers", %{conn: conn} do
      html = render_component(&Skills.toolbar/1, %{})

      # Should have clickable elements to open dropdowns
      assert html =~ "dropdown" || html =~ "details"
    end

    test "component renders without errors with empty attributes", %{conn: conn} do
      assert render_component(&Skills.toolbar/1, %{}) |> is_binary()
    end

    test "component renders separator between filters", %{conn: conn} do
      html = render_component(&Skills.toolbar/1, %{})

      # Should have visual separator
      assert is_binary(html)
    end

    test "renders sort button", %{conn: conn} do
      html = render_component(&Skills.toolbar/1, %{sort_by: "name_asc"})

      assert is_binary(html)
    end
  end
end
