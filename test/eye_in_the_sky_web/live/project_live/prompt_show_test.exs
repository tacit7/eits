defmodule EyeInTheSkyWeb.ProjectLive.PromptShowTest do
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

    uuid = Ecto.UUID.generate()

    {:ok, prompt} =
      Prompts.create_prompt(%{
        project_id: project.id,
        name: "Test Prompt",
        uuid: uuid,
        slug: "test-prompt-#{System.unique_integer([:positive])}",
        prompt_text: "You are a helpful assistant."
      })

    %{project: project, prompt: prompt}
  end

  describe "mount/3" do
    test "renders the prompt name", %{conn: conn, project: project, prompt: prompt} do
      {:ok, _lv, html} = live(conn, ~p"/projects/#{project.id}/prompts/#{prompt.uuid}")

      assert html =~ prompt.name
    end

    test "renders the prompt content", %{conn: conn, project: project, prompt: prompt} do
      {:ok, _lv, html} = live(conn, ~p"/projects/#{project.id}/prompts/#{prompt.uuid}")

      assert html =~ "helpful assistant"
    end
  end

  describe "render/1" do
    test "renders edit affordance", %{conn: conn, project: project, prompt: prompt} do
      {:ok, _lv, html} = live(conn, ~p"/projects/#{project.id}/prompts/#{prompt.uuid}")

      assert html =~ ~s(phx-click="edit")
    end

    test "renders delete affordance", %{conn: conn, project: project, prompt: prompt} do
      {:ok, _lv, html} = live(conn, ~p"/projects/#{project.id}/prompts/#{prompt.uuid}")

      assert html =~ "Deactivate"
    end

  end

  describe "handle_event/delete" do
    test "deactivating a prompt navigates back to the prompts list", %{conn: conn, project: project, prompt: prompt} do
      {:ok, lv, _html} = live(conn, ~p"/projects/#{project.id}/prompts/#{prompt.uuid}")

      assert has_element?(lv, "[phx-click='delete']")

      result = lv |> element("[phx-click='delete']") |> render_click()

      assert {:error, {:live_redirect, %{to: path}}} = result
      assert path =~ "/projects/#{project.id}/prompts"
    end
  end
end
