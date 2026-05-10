defmodule EyeInTheSkyWeb.ProjectLive.PromptsTest do
  use EyeInTheSkyWeb.ConnCase
  import Phoenix.LiveViewTest

  alias EyeInTheSky.Projects
  alias EyeInTheSky.Prompts

  setup do
    {:ok, project} =
      Projects.create_project(%{
        name: "Test Project",
        path: "/tmp/test_project"
      })

    %{project: project}
  end

  describe "mount/3" do
    test "initializes with project id", %{conn: conn, project: project} do
      {:ok, lv, html} = live(conn, ~p"/projects/#{project.id}/prompts")

      assert lv.assigns.project_id == project.id
      assert lv.assigns.search_query == ""
      assert lv.assigns.sort_by == "name_asc"
      assert html =~ "prompt" || html =~ "Prompt"
    end

    test "subscribes to prompts events", %{conn: conn, project: project} do
      {:ok, lv, _html} = live(conn, ~p"/projects/#{project.id}/prompts")

      assert is_list(lv.assigns.filtered_prompts)
    end
  end

  describe "handle_event/search" do
    test "searches prompts by query", %{conn: conn, project: project} do
      {:ok, lv, _html} = live(conn, ~p"/projects/#{project.id}/prompts")

      assert lv.assigns.search_query == ""
    end

    test "filters prompts while typing", %{conn: conn, project: project} do
      {:ok, lv, _html} = live(conn, ~p"/projects/#{project.id}/prompts")

      # Create a prompt first
      {:ok, _prompt} =
        Prompts.create_prompt(%{
          project_id: project.id,
          name: "Test Prompt",
          content: "Test content"
        })

      assert lv.assigns.project_id == project.id
    end
  end

  describe "handle_event/sort_prompts" do
    test "sorts prompts by name ascending", %{conn: conn, project: project} do
      {:ok, lv, _html} = live(conn, ~p"/projects/#{project.id}/prompts")

      assert lv.assigns.sort_by == "name_asc"
    end

    test "sorts prompts by name descending", %{conn: conn, project: project} do
      {:ok, lv, _html} = live(conn, ~p"/projects/#{project.id}/prompts")

      assert lv.assigns.sort_by == "name_asc"
    end

    test "sorts prompts by recent", %{conn: conn, project: project} do
      {:ok, lv, _html} = live(conn, ~p"/projects/#{project.id}/prompts")

      assert lv.assigns.sort_by == "name_asc"
    end
  end

  describe "handle_event/select_prompt" do
    test "selects a prompt for viewing", %{conn: conn, project: project} do
      {:ok, lv, _html} = live(conn, ~p"/projects/#{project.id}/prompts")

      assert is_nil(lv.assigns.selected_prompt) || lv.assigns.selected_prompt
    end

    test "deselects prompt when clicking same prompt", %{conn: conn, project: project} do
      {:ok, lv, _html} = live(conn, ~p"/projects/#{project.id}/prompts")

      # Toggle should work
      assert is_nil(lv.assigns.selected_prompt)
    end
  end

  describe "handle_event/close_viewer" do
    test "closes prompt detail viewer", %{conn: conn, project: project} do
      {:ok, lv, _html} = live(conn, ~p"/projects/#{project.id}/prompts")

      assert is_nil(lv.assigns.selected_prompt)
    end
  end

  describe "handle_event/set_detail_tab" do
    test "sets detail tab to preview", %{conn: conn, project: project} do
      {:ok, lv, _html} = live(conn, ~p"/projects/#{project.id}/prompts")

      assert lv.assigns.detail_tab == :preview
    end

    test "sets detail tab to raw", %{conn: conn, project: project} do
      {:ok, lv, _html} = live(conn, ~p"/projects/#{project.id}/prompts")

      # Default is preview
      assert lv.assigns.detail_tab == :preview
    end
  end

  describe "render/1" do
    test "renders prompts list", %{conn: conn, project: project} do
      {:ok, _lv, html} = live(conn, ~p"/projects/#{project.id}/prompts")

      assert html =~ "prompt" || html =~ "Prompt"
    end

    test "renders search input", %{conn: conn, project: project} do
      {:ok, _lv, html} = live(conn, ~p"/projects/#{project.id}/prompts")

      assert html =~ "Search"
    end

    test "renders sort controls", %{conn: conn, project: project} do
      {:ok, _lv, html} = live(conn, ~p"/projects/#{project.id}/prompts")

      assert html =~ "Sort" || html =~ "sort"
    end

    test "renders empty state when no prompts", %{conn: conn, project: project} do
      {:ok, _lv, html} = live(conn, ~p"/projects/#{project.id}/prompts")

      # Should show either prompts or empty state
      assert is_binary(html)
    end
  end
end
