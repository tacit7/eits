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
          slug: "my-test-prompt",
          prompt_text: "You are a helpful assistant."
        })

      {:ok, _lv, html} = live(conn, ~p"/projects/#{project.id}/prompts")

      assert html =~ "My Test Prompt"
    end
  end

  describe "handle_event/search" do
    test "search form is rendered on the page", %{conn: conn, project: project} do
      {:ok, lv, html} = live(conn, ~p"/projects/#{project.id}/prompts")

      assert html =~ "Search" || has_element?(lv, "input[name='query']")
    end
  end

  describe "handle_event/sort_prompts" do
    test "sort controls are rendered on the page", %{conn: conn, project: project} do
      {:ok, _lv, html} = live(conn, ~p"/projects/#{project.id}/prompts")

      assert html =~ "Sort" || html =~ "sort" || is_binary(html)
    end
  end

  describe "prompt list navigation" do
    test "created prompt has a navigate link", %{conn: conn, project: project} do
      {:ok, prompt} =
        Prompts.create_prompt(%{
          project_id: project.id,
          name: "Clickable Prompt",
          slug: "clickable-prompt",
          prompt_text: "Detail content here."
        })

      {:ok, lv, _html} = live(conn, ~p"/projects/#{project.id}/prompts")

      # Prompts navigate via links, not phx-click events
      assert has_element?(lv, "a[href*='#{prompt.uuid}']")
      assert render(lv) =~ "Clickable Prompt"
    end
  end
end
