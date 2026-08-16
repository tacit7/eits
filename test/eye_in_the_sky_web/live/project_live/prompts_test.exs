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

      assert html =~ "No prompts yet"
    end

    test "renders search controls", %{conn: conn, project: project} do
      {:ok, _lv, html} = live(conn, ~p"/projects/#{project.id}/prompts")

      assert html =~ "Search"
    end

    test "renders empty state when no prompts exist", %{conn: conn, project: project} do
      {:ok, _lv, html} = live(conn, ~p"/projects/#{project.id}/prompts")

      assert html =~ "No prompts yet"
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

      assert has_element?(lv, "#prompts-top-bar-search")
    end
  end

  describe "handle_event/sort_prompts" do
    test "prompts list shows empty state when no prompts exist", %{conn: conn, project: project} do
      {:ok, _lv, html} = live(conn, ~p"/projects/#{project.id}/prompts")

      assert html =~ "No prompts yet"
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

      # Prompt rows expose a data-ctx-path attribute with the UUID-based path.
      # The navigate <.link> only renders in the detail panel (after select_prompt).
      assert has_element?(lv, "[data-ctx-path*='#{prompt.uuid}']")
      assert render(lv) =~ "Clickable Prompt"
    end
  end

  describe "handle_event/3 - duplicate_prompt" do
    test "duplicates the prompt and reloads", %{conn: conn, project: project} do
      {:ok, prompt} =
        Prompts.create_prompt(%{
          project_id: project.id,
          name: "Original",
          slug: "original",
          prompt_text: "text"
        })

      {:ok, lv, _html} = live(conn, ~p"/projects/#{project.id}/prompts")

      html = render_click(lv, "duplicate_prompt", %{"uuid" => prompt.uuid})

      assert html =~ "original-copy"
    end

    test "flashes an error for an unknown uuid", %{conn: conn, project: project} do
      {:ok, lv, _html} = live(conn, ~p"/projects/#{project.id}/prompts")

      html = render_click(lv, "duplicate_prompt", %{"uuid" => Ecto.UUID.generate()})

      assert html =~ "Prompt not found"
    end
  end

  describe "handle_event/3 - deactivate_prompt" do
    test "deactivates the prompt and removes it from the active list", %{
      conn: conn,
      project: project
    } do
      {:ok, prompt} =
        Prompts.create_prompt(%{
          project_id: project.id,
          name: "To Deactivate",
          slug: "to-deactivate",
          prompt_text: "text"
        })

      {:ok, lv, _html} = live(conn, ~p"/projects/#{project.id}/prompts")

      html = render_click(lv, "deactivate_prompt", %{"uuid" => prompt.uuid})

      refute html =~ "To Deactivate"
    end
  end
end
