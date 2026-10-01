defmodule EyeInTheSkyWeb.Components.Rail.TaskDetailTest do
  use EyeInTheSkyWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias EyeInTheSkyWeb.Components.Rail.Modals.TaskDetail

  defp base_task(overrides \\ %{}) do
    Map.merge(
      %{
        id: 123,
        uuid: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",
        title: "Rail task",
        description: "Task body",
        project_id: 456,
        state_id: 1
      },
      overrides
    )
  end

  describe "task_detail_modal/1" do
    test "links project-scoped tasks back to the project task list" do
      html =
        render_component(&TaskDetail.task_detail_modal/1,
          task: base_task(),
          index: 0,
          total: 1
        )

      assert html =~ ~s(href="/projects/456/tasks?task_id=123")
    end

    test "links global tasks to the workspace task list with task uuid context" do
      html =
        render_component(&TaskDetail.task_detail_modal/1,
          task: base_task(%{project_id: nil}),
          index: 0,
          total: 1
        )

      assert html =~ ~s(href="/workspace/tasks?uuid=aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee")
      refute html =~ ~s(href="/projects")
    end
  end
end
