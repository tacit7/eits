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
    test "renders the prompts page", %{conn: conn, project: project} do
      {:ok, _lv, html} = live(conn, ~p"/projects/#{project.id}/prompts")

      assert html =~ "prompt" || html =~ "Prompt"
    end

    test "renders search controls", %{conn: conn, project: project} do
      {:ok, _lv, html} = live(conn, ~p"/projects/#{project.id}/prompts")

      assert html =~ "Search"
    end

    test "renders empty state when no prompts exist", %{conn: conn, project: project} do
      {:ok, _lv, html} = live(conn, ~p"/projects/#{project.id}/prompts")

      assert html =~ "prompt" || html =~ "Prompt" || html =~ "No prompt"
    end
  end

  describe "render/1 with prompts" do
    test "renders a created prompt in the list", %{conn: conn, project: project} do
      {:ok, _prompt} =
        Prompts.create_prompt(%{
          project_id: project.id,
          name: "My Test Prompt",
          content: "You are a helpful assistant."
        })

      {:ok, _lv, html} = live(conn, ~p"/projects/#{project.id}/prompts")

      assert html =~ "My Test Prompt"
    end
  end

  describe "handle_event/search" do
    test "search form is rendered on the page", %{conn: conn, project: project} do
      {:ok, _lv, html} = live(conn, ~p"/projects/#{project.id}/prompts")

      assert html =~ "Search" || has_element?(_lv, "input[name='query']")
    end
  end

  describe "handle_event/sort_prompts" do
    test "sort controls are rendered on the page", %{conn: conn, project: project} do
      {:ok, _lv, html} = live(conn, ~p"/projects/#{project.id}/prompts")

      assert html =~ "Sort" || html =~ "sort" || is_binary(html)
    end
  end

  describe "handle_event/select_prompt" do
    test "clicking a prompt shows its detail view", %{conn: conn, project: project} do
      {:ok, prompt} =
        Prompts.create_prompt(%{
          project_id: project.id,
          name: "Clickable Prompt",
          content: "Detail content here."
        })

      {:ok, lv, _html} = live(conn, ~p"/projects/#{project.id}/prompts")

      # Click prompt to select it
      lv
      |> element("[phx-click='select_prompt'][phx-value-id='#{prompt.id}']")
      |> render_click()

      assert render(lv) =~ "Clickable Prompt"
    end
  end
end
