defmodule EyeInTheSkyWeb.TopBar.SkillsTest do
  use EyeInTheSkyWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  alias EyeInTheSkyWeb.TopBar.Skills

  describe "toolbar/1 component" do
    test "renders search input" do
      html = render_component(&Skills.toolbar/1, %{})

      assert html =~ "Search skills"
      assert html =~ "skills-top-bar-search"
    end

    test "renders search input with custom value" do
      html = render_component(&Skills.toolbar/1, %{search_query: "test-query"})

      assert html =~ "test-query"
    end

    test "renders type filter dropdown" do
      html = render_component(&Skills.toolbar/1, %{})

      assert html =~ "Type:"
      assert html =~ "skills-type-dropdown"
    end

    test "renders scope filter dropdown" do
      html = render_component(&Skills.toolbar/1, %{})

      assert html =~ "Source:"
      assert html =~ "skills-scope-dropdown"
    end

    test "renders sort dropdown" do
      html = render_component(&Skills.toolbar/1, %{})

      assert html =~ "Sort:"
      assert html =~ "skills-sort-dropdown"
    end

    test "renders all type options" do
      html = render_component(&Skills.toolbar/1, %{type_filter: "all"})

      assert html =~ "All"
      assert html =~ "Skills"
      assert html =~ "Commands"
    end

    test "renders all scope options" do
      html = render_component(&Skills.toolbar/1, %{scope_filter: "all"})

      assert html =~ "All"
      assert html =~ "Global"
      assert html =~ "Project"
    end

    test "renders sort options" do
      html = render_component(&Skills.toolbar/1, %{sort_by: "name_asc"})

      assert html =~ "Name A"
      assert html =~ "Recent"
    end

    test "selected type filter value is reflected" do
      html = render_component(&Skills.toolbar/1, %{type_filter: "skills"})

      assert html =~ "Skills"
    end

    test "selected scope filter is reflected" do
      html = render_component(&Skills.toolbar/1, %{scope_filter: "project"})

      assert html =~ "Project"
    end

    test "handles all type filter values without error" do
      for type <- ["all", "skills", "commands"] do
        assert render_component(&Skills.toolbar/1, %{type_filter: type}) |> is_binary()
      end
    end

    test "handles all scope filter values without error" do
      for scope <- ["all", "global", "project"] do
        assert render_component(&Skills.toolbar/1, %{scope_filter: scope}) |> is_binary()
      end
    end

    test "handles all sort order values without error" do
      for sort <- ["name_asc", "name_desc", "recent", "size_desc", "size_asc"] do
        assert render_component(&Skills.toolbar/1, %{sort_by: sort}) |> is_binary()
      end
    end

    test "renders dropdown elements" do
      html = render_component(&Skills.toolbar/1, %{})

      assert html =~ "dropdown"
    end

    test "renders with defaults when no props passed" do
      assert render_component(&Skills.toolbar/1, %{}) |> is_binary()
    end
  end
end
