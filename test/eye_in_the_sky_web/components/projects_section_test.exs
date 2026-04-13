defmodule EyeInTheSkyWeb.Components.ProjectsSectionTest do
  use EyeInTheSkyWeb.ConnCase
  import Phoenix.LiveViewTest
  import Phoenix.Component

  alias EyeInTheSky.Projects
  alias EyeInTheSkyWeb.Components.Sidebar.ProjectsSection

  defp build_project(name \\ nil) do
    name = name || "proj-#{System.unique_integer([:positive])}"
    {:ok, project} =
      Projects.create_project(%{name: name, path: "/tmp/#{name}", slug: name})
    project
  end

  defp render_section(assigns) do
    defaults = %{
      projects: [],
      sidebar_project: nil,
      sidebar_tab: :sessions,
      collapsed: false,
      expanded_projects: true,
      new_project_path: nil,
      renaming_project_id: nil,
      rename_value: "",
      myself: %Phoenix.LiveComponent.CID{cid: 1}
    }

    merged = Map.merge(defaults, assigns)
    render_component(&ProjectsSection.projects_section/1, merged)
  end

  describe "flat list with no project selected" do
    test "renders project rows as links" do
      p1 = build_project("alpha")
      p2 = build_project("beta")

      html = render_section(%{projects: [p1, p2]})

      assert html =~ "alpha"
      assert html =~ "beta"
      assert html =~ ~r/href="\/projects\/#{p1.id}"/
      assert html =~ ~r/href="\/projects\/#{p2.id}"/
    end

    test "does not render any docked panel when sidebar_project is nil" do
      p = build_project()
      html = render_section(%{projects: [p], sidebar_project: nil})

      refute html =~ "project-panel"
      refute html =~ "Overview"
    end

    test "project rows do not have selected class when nothing is selected" do
      p = build_project()
      html = render_section(%{projects: [p], sidebar_project: nil})

      refute html =~ "bg-primary/15"
      refute html =~ "font-semibold"
    end
  end

  describe "selected project with docked panel" do
    test "selected row has stronger visual treatment" do
      p = build_project("discourse")
      html = render_section(%{projects: [p], sidebar_project: p})

      assert html =~ "bg-primary/15"
      assert html =~ "font-semibold"
    end

    test "docked panel renders beneath selected project" do
      p = build_project("discourse")
      html = render_section(%{projects: [p], sidebar_project: p})

      assert html =~ "border-t-2"
      assert html =~ "border-primary"
    end

    test "panel header shows project name without icon or label prefix" do
      p = build_project("discourse")
      html = render_section(%{projects: [p], sidebar_project: p})

      assert html =~ "discourse"
      # Name appears in panel header — no "Project" label before it
      refute html =~ ">Project<"
    end

    test "panel contains 8 separate nav items" do
      p = build_project()
      html = render_section(%{projects: [p], sidebar_project: p})

      assert html =~ "Overview"
      assert html =~ "Sessions"
      assert html =~ "Tasks"
      assert html =~ "Prompts"
      assert html =~ "Notes"
      assert html =~ "Files"
      assert html =~ "Agents"
      assert html =~ "Jobs"
    end

    test "panel items link to correct project routes" do
      p = build_project()
      html = render_section(%{projects: [p], sidebar_project: p})

      assert html =~ ~r/href="\/projects\/#{p.id}"/
      assert html =~ ~r/href="\/projects\/#{p.id}\/sessions"/
      assert html =~ ~r/href="\/projects\/#{p.id}\/tasks"/
      assert html =~ ~r/href="\/projects\/#{p.id}\/prompts"/
      assert html =~ ~r/href="\/projects\/#{p.id}\/notes"/
      assert html =~ ~r/href="\/projects\/#{p.id}\/files"/
      assert html =~ ~r/href="\/projects\/#{p.id}\/agents"/
      assert html =~ ~r/href="\/projects\/#{p.id}\/jobs"/
    end

    test "Overview is active when sidebar_tab is :overview" do
      p = build_project()
      html = render_section(%{projects: [p], sidebar_project: p, sidebar_tab: :overview})

      # active class on Overview item
      assert html =~ ~r/border-primary font-medium[^>]*>.*Overview/s
    end

    test "Sessions panel item is active when sidebar_tab is :sessions" do
      p = build_project()
      html = render_section(%{projects: [p], sidebar_project: p, sidebar_tab: :sessions})

      assert html =~ ~r/border-primary font-medium[^>]*>.*Sessions/s
    end

    test "no panel renders for non-selected projects" do
      selected = build_project("selected")
      other = build_project("other")
      html = render_section(%{projects: [selected, other], sidebar_project: selected})

      # Only one panel header with the selected project name
      assert [_] = Regex.scan(~r/text-\[11px\] font-medium text-primary/, html)
    end
  end

  describe "collapsed sidebar" do
    test "does not render docked panel when collapsed" do
      p = build_project()
      html = render_section(%{projects: [p], sidebar_project: p, collapsed: true})

      refute html =~ "Overview"
      refute html =~ "border-t-2"
    end
  end

  describe "bookmark button" do
    test "bookmark button is present in hover actions for each project" do
      p = build_project()
      html = render_section(%{projects: [p]})

      assert html =~ "set_bookmark"
    end

    test "outline bookmark icon when project is not bookmarked" do
      p = build_project()
      html = render_section(%{projects: [p]})

      assert html =~ "hero-bookmark "
      refute html =~ "hero-bookmark-solid"
    end

    test "solid bookmark icon when project is bookmarked" do
      p = build_project()
      {:ok, p} = Projects.update_project(p, %{bookmarked: true})
      html = render_section(%{projects: [p]})

      assert html =~ "hero-bookmark-solid"
    end

    test "phx-disable-with present on bookmark button" do
      p = build_project()
      html = render_section(%{projects: [p]})

      assert html =~ "phx-disable-with"
    end
  end
end
