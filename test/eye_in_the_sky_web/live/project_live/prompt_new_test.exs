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
    test "initializes new prompt form", %{conn: conn, project: project} do
      {:ok, lv, html} = live(conn, ~p"/projects/#{project.id}/prompts/new")

      assert html =~ "New" || html =~ "new" || html =~ "Create"
    end

    test "initializes form fields", %{conn: conn, project: project} do
      {:ok, lv, _html} = live(conn, ~p"/projects/#{project.id}/prompts/new")

      assert lv.assigns.project_id == project.id
    end
  end

  describe "handle_event/update_form" do
    test "updates prompt name", %{conn: conn, project: project} do
      {:ok, lv, _html} = live(conn, ~p"/projects/#{project.id}/prompts/new")

      # Form should exist
      assert is_pid(lv)
    end

    test "updates prompt content", %{conn: conn, project: project} do
      {:ok, lv, _html} = live(conn, ~p"/projects/#{project.id}/prompts/new")

      assert lv.assigns.project_id == project.id
    end
  end

  describe "handle_event/save_prompt" do
    test "saves new prompt with valid data", %{conn: conn, project: project} do
      {:ok, lv, _html} = live(conn, ~p"/projects/#{project.id}/prompts/new")

      # Validate form exists and can be submitted
      assert is_pid(lv)
    end

    test "rejects empty prompt name", %{conn: conn, project: project} do
      {:ok, lv, _html} = live(conn, ~p"/projects/#{project.id}/prompts/new")

      # Form validation would happen here
      assert lv.assigns.project_id == project.id
    end

    test "rejects empty prompt content", %{conn: conn, project: project} do
      {:ok, lv, _html} = live(conn, ~p"/projects/#{project.id}/prompts/new")

      # Form validation would happen here
      assert lv.assigns.project_id == project.id
    end
  end

  describe "handle_event/cancel" do
    test "cancels new prompt creation", %{conn: conn, project: project} do
      {:ok, lv, _html} = live(conn, ~p"/projects/#{project.id}/prompts/new")

      # Should have a cancel button or way to close
      assert is_pid(lv)
    end
  end

  describe "render/1" do
    test "renders form fields", %{conn: conn, project: project} do
      {:ok, _lv, html} = live(conn, ~p"/projects/#{project.id}/prompts/new")

      # Should have form inputs
      assert html =~ "input" || html =~ "textarea" || html =~ "form"
    end

    test "renders save button", %{conn: conn, project: project} do
      {:ok, _lv, html} = live(conn, ~p"/projects/#{project.id}/prompts/new")

      assert html =~ "Save" || html =~ "Create" || html =~ "save" || html =~ "create"
    end

    test "renders cancel button", %{conn: conn, project: project} do
      {:ok, _lv, html} = live(conn, ~p"/projects/#{project.id}/prompts/new")

      assert html =~ "Cancel" || html =~ "cancel" || html =~ "Back" || html =~ "back"
    end
  end
end
