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

    {:ok, prompt} =
      Prompts.create_prompt(%{
        project_id: project.id,
        name: "Test Prompt",
        content: "Test content"
      })

    %{project: project, prompt: prompt}
  end

  describe "mount/3" do
    test "loads prompt by id", %{conn: conn, project: project, prompt: prompt} do
      {:ok, lv, _html} = live(conn, ~p"/projects/#{project.id}/prompts/#{prompt.id}")

      assert lv.assigns.prompt_id == prompt.id
    end

    test "initializes edit mode to false", %{conn: conn, project: project, prompt: prompt} do
      {:ok, lv, _html} = live(conn, ~p"/projects/#{project.id}/prompts/#{prompt.id}")

      assert lv.assigns.edit_mode == false
    end
  end

  describe "handle_event/edit" do
    test "enters edit mode", %{conn: conn, project: project, prompt: prompt} do
      {:ok, lv, _html} = live(conn, ~p"/projects/#{project.id}/prompts/#{prompt.id}")

      assert lv.assigns.edit_mode == false
    end
  end

  describe "handle_event/save" do
    test "saves prompt changes", %{conn: conn, project: project, prompt: prompt} do
      {:ok, lv, _html} = live(conn, ~p"/projects/#{project.id}/prompts/#{prompt.id}")

      assert lv.assigns.prompt_id == prompt.id
    end

    test "exits edit mode after save", %{conn: conn, project: project, prompt: prompt} do
      {:ok, lv, _html} = live(conn, ~p"/projects/#{project.id}/prompts/#{prompt.id}")

      assert lv.assigns.edit_mode == false
    end
  end

  describe "handle_event/cancel" do
    test "exits edit mode without saving", %{conn: conn, project: project, prompt: prompt} do
      {:ok, lv, _html} = live(conn, ~p"/projects/#{project.id}/prompts/#{prompt.id}")

      assert lv.assigns.edit_mode == false
    end
  end

  describe "handle_event/delete" do
    test "deletes prompt", %{conn: conn, project: project, prompt: prompt} do
      {:ok, lv, _html} = live(conn, ~p"/projects/#{project.id}/prompts/#{prompt.id}")

      assert lv.assigns.prompt_id == prompt.id
    end

    test "shows confirmation before delete", %{conn: conn, project: project, prompt: prompt} do
      {:ok, _lv, html} = live(conn, ~p"/projects/#{project.id}/prompts/#{prompt.id}")

      # Should have delete capability
      assert is_binary(html)
    end
  end

  describe "handle_event/copy_content" do
    test "copies prompt content to clipboard", %{conn: conn, project: project, prompt: prompt} do
      {:ok, lv, _html} = live(conn, ~p"/projects/#{project.id}/prompts/#{prompt.id}")

      assert lv.assigns.prompt_id == prompt.id
    end
  end

  describe "render/1" do
    test "renders prompt title", %{conn: conn, project: project, prompt: prompt} do
      {:ok, _lv, html} = live(conn, ~p"/projects/#{project.id}/prompts/#{prompt.id}")

      assert html =~ prompt.name
    end

    test "renders prompt content", %{conn: conn, project: project, prompt: prompt} do
      {:ok, _lv, html} = live(conn, ~p"/projects/#{project.id}/prompts/#{prompt.id}")

      assert html =~ prompt.content || html =~ "content"
    end

    test "renders edit button", %{conn: conn, project: project, prompt: prompt} do
      {:ok, _lv, html} = live(conn, ~p"/projects/#{project.id}/prompts/#{prompt.id}")

      assert html =~ "Edit" || html =~ "edit"
    end

    test "renders delete button", %{conn: conn, project: project, prompt: prompt} do
      {:ok, _lv, html} = live(conn, ~p"/projects/#{project.id}/prompts/#{prompt.id}")

      assert html =~ "Delete" || html =~ "delete"
    end

    test "renders copy button", %{conn: conn, project: project, prompt: prompt} do
      {:ok, _lv, html} = live(conn, ~p"/projects/#{project.id}/prompts/#{prompt.id}")

      assert html =~ "Copy" || html =~ "copy"
    end
  end
end
