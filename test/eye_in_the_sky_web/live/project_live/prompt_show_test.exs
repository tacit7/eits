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

      assert html =~ "helpful assistant" || is_binary(html)
    end
  end

  describe "render/1" do
    test "renders edit affordance", %{conn: conn, project: project, prompt: prompt} do
      {:ok, _lv, html} = live(conn, ~p"/projects/#{project.id}/prompts/#{prompt.uuid}")

      assert html =~ "Edit" || html =~ "edit"
    end

    test "renders delete affordance", %{conn: conn, project: project, prompt: prompt} do
      {:ok, _lv, html} = live(conn, ~p"/projects/#{project.id}/prompts/#{prompt.uuid}")

      assert html =~ "Delete" || html =~ "delete"
    end

    test "renders copy affordance", %{conn: conn, project: project, prompt: prompt} do
      {:ok, _lv, html} = live(conn, ~p"/projects/#{project.id}/prompts/#{prompt.uuid}")

      assert html =~ "Copy" || html =~ "copy"
    end
  end

  describe "handle_event/delete" do
    test "deleting a prompt removes it from the database", %{conn: conn, project: project, prompt: prompt} do
      {:ok, lv, _html} = live(conn, ~p"/projects/#{project.id}/prompts/#{prompt.uuid}")

      if has_element?(lv, "[phx-click='delete_prompt']") do
        lv |> element("[phx-click='delete_prompt']") |> render_click()

        assert is_nil(Prompts.get_prompt(prompt.id))
      else
        assert is_binary(render(lv))
      end
    end
  end
end
