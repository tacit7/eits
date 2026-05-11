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

      assert html =~ "New Prompt"
    end

    test "renders name/content input fields", %{conn: conn, project: project} do
      {:ok, _lv, html} = live(conn, ~p"/projects/#{project.id}/prompts/new")

      assert html =~ "Prompt Text"
    end
  end

  describe "render/1" do
    test "renders the create prompt submit button", %{conn: conn, project: project} do
      {:ok, _lv, html} = live(conn, ~p"/projects/#{project.id}/prompts/new")

      assert html =~ "Create Prompt"
    end

    test "renders a back link to the prompts list", %{conn: conn, project: project} do
      {:ok, _lv, html} = live(conn, ~p"/projects/#{project.id}/prompts/new")

      assert html =~ "Back to Prompts"
    end
  end

  describe "handle_event/save" do
    test "submitting a valid prompt redirects or shows success", %{conn: conn, project: project} do
      {:ok, lv, _html} = live(conn, ~p"/projects/#{project.id}/prompts/new")

      result =
        lv
        |> form("form[phx-submit='save']")
        |> render_submit(%{"prompt" => %{"prompt_text" => "Content here", "name" => "My Prompt", "slug" => ""}})

      assert {:error, {:live_redirect, %{to: path}}} = result
      assert path =~ "/projects/#{project.id}/prompts"
    end

    test "submitting blank name re-renders form with error", %{conn: conn, project: project} do
      {:ok, lv, _html} = live(conn, ~p"/projects/#{project.id}/prompts/new")

      html =
        lv
        |> form("form[phx-submit='save']")
        |> render_submit(%{"prompt" => %{"name" => "", "prompt_text" => "Content"}})

      assert html =~ "can&#39;t be blank"
    end
  end
end
