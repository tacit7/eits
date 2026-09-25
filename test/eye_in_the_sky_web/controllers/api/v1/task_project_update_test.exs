defmodule EyeInTheSkyWeb.Api.V1.TaskProjectUpdateTest do
  use EyeInTheSkyWeb.ConnCase, async: false

  import EyeInTheSky.Factory

  alias EyeInTheSky.Accounts.ApiKey
  alias EyeInTheSky.{Projects, Tasks}
  alias EyeInTheSky.Tasks.WorkflowState

  setup do
    token = "test_api_key_#{uniq()}"
    {:ok, _} = ApiKey.create(token, "test")
    conn = build_conn() |> put_req_header("authorization", "Bearer #{token}")

    {:ok, project} =
      Projects.create_project(%{name: "Project #{uniq()}", path: "/tmp/project-#{uniq()}"})

    %{conn: conn, project: project}
  end

  test "rejects assigning an unscoped task without partially updating fields", context do
    task = create_task(nil)

    conn =
      patch(context.conn, ~p"/api/v1/tasks/#{task.id}", %{
        "project_id" => context.project.id,
        "title" => "Changed title",
        "description" => "Changed description",
        "priority" => 2,
        "state_id" => WorkflowState.done_id()
      })

    assert_rejected(conn)
    assert_unchanged(task)
  end

  test "rejects project changes before state transitions and session linking", context do
    task = create_task(context.project.id)
    session = new_session()

    conn =
      patch(context.conn, ~p"/api/v1/tasks/#{task.id}", %{
        "project_id" => nil,
        "state" => "start",
        "session_id" => session.uuid
      })

    assert_rejected(conn)
    assert_unchanged(task)
    assert Tasks.get_task!(task.id).sessions == []
  end

  test "rejects any supplied project_id rather than silently ignoring it", context do
    task = create_task(context.project.id)

    for project_id <- [context.project.id, to_string(context.project.id), "", "invalid"] do
      conn = patch(context.conn, ~p"/api/v1/tasks/#{task.id}", %{"project_id" => project_id})
      assert_rejected(conn)
      assert_unchanged(task)
    end
  end

  test "supported updates without project_id still succeed", context do
    task = create_task(context.project.id)

    conn =
      patch(context.conn, ~p"/api/v1/tasks/#{task.id}", %{
        "title" => "Updated title",
        "description" => "Updated description",
        "priority" => 2,
        "state_id" => WorkflowState.done_id()
      })

    assert json_response(conn, 200)["success"] == true
    updated = Tasks.get_task!(task.id)
    assert updated.title == "Updated title"
    assert updated.description == "Updated description"
    assert updated.priority == 2
    assert updated.state_id == WorkflowState.done_id()
    assert updated.project_id == task.project_id
  end

  defp create_task(project_id) do
    {:ok, task} =
      Tasks.create_task(%{
        uuid: Ecto.UUID.generate(),
        title: "Original title",
        description: "Original description",
        state_id: WorkflowState.todo_id(),
        project_id: project_id,
        created_at: DateTime.utc_now()
      })

    task
  end

  defp assert_rejected(conn) do
    response = json_response(conn, 422)

    assert response["error"] ==
             "project_id cannot be updated; task project reassignment is not supported"

    refute response["success"]
  end

  defp assert_unchanged(task) do
    updated = Tasks.get_task!(task.id)

    for field <- [:project_id, :title, :description, :priority, :state_id, :updated_at] do
      assert Map.fetch!(updated, field) == Map.fetch!(task, field)
    end
  end
end
