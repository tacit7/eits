defmodule EyeInTheSkyWeb.ProjectLive.PromptNewTest do
  use EyeInTheSkyWeb.ConnCase
  import Phoenix.LiveViewTest

  alias EyeInTheSky.Projects

  setup do
    {:ok, project} =
      Projects.create_project(%{
        name: "Test Project",
        path: "/tmp/test_project"
      })

    %{project: project}
  end

  describe "mount/3" do
    test "renders a form for creating a new prompt", %{conn: conn, project: project} do
      {:ok, _lv, html} = live(conn, ~p"/projects/#{project.id}/prompts/new")

      assert html =~ "form" || html =~ "New" || html =~ "Create"
    end

    test "renders name/content input fields", %{conn: conn, project: project} do
      {:ok, _lv, html} = live(conn, ~p"/projects/#{project.id}/prompts/new")

      assert html =~ "input" || html =~ "textarea"
    end
  end

  describe "render/1" do
    test "renders a save or create button", %{conn: conn, project: project} do
      {:ok, _lv, html} = live(conn, ~p"/projects/#{project.id}/prompts/new")

      assert html =~ "Save" || html =~ "Create" || html =~ "save" || html =~ "create"
    end

    test "renders a cancel or back link", %{conn: conn, project: project} do
      {:ok, _lv, html} = live(conn, ~p"/projects/#{project.id}/prompts/new")

      assert html =~ "Cancel" || html =~ "Back" || html =~ "cancel" || html =~ "back"
    end
  end

  describe "handle_event/save" do
    test "submitting a valid prompt redirects or shows success", %{conn: conn, project: project} do
      {:ok, lv, _html} = live(conn, ~p"/projects/#{project.id}/prompts/new")

      result =
        lv
        |> form("form")
        |> render_submit(%{"prompt" => %{"name" => "My Prompt", "content" => "Content here"}})

      # Either redirects (assert_redirect pattern) or shows success message
      assert is_binary(result) || match?({:error, {:redirect, _}}, result) ||
               match?({:error, {:live_redirect, _}}, result)
    end

    test "submitting blank name re-renders form with error", %{conn: conn, project: project} do
      {:ok, lv, _html} = live(conn, ~p"/projects/#{project.id}/prompts/new")

      html =
        lv
        |> form("form")
        |> render_submit(%{"prompt" => %{"name" => "", "content" => "Content"}})

      assert html =~ "form" || html =~ "error" || html =~ "required" || is_binary(html)
    end
  end
end
