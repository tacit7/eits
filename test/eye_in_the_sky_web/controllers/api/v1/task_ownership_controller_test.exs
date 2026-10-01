defmodule EyeInTheSkyWeb.Api.V1.TaskOwnershipControllerTest do
  use EyeInTheSkyWeb.ConnCase, async: false
  import EyeInTheSky.Factory
  alias EyeInTheSky.Tasks

  setup do
    owner = create_session(create_agent())
    target = create_session(create_agent())
    {:ok, task} = Tasks.create_task(%{title: "API ownership", state_id: 1})
    {:ok, _} = Tasks.claim_task(task, owner.id)
    %{task: task, owner: owner, target: target}
  end

  test "release resolves UUID, clears ownership, and retries", c do
    for _ <- 1..2 do
      response = post(c.conn, "/api/v1/tasks/#{c.task.id}/release", %{session_id: c.owner.uuid})
      assert %{"success" => true, "task" => %{"state_id" => 1}} = json_response(response, 200)
    end
  end

  test "handoff resolves integer target and rejects non-owner", c do
    path = "/api/v1/tasks/#{c.task.id}/handoff"
    assert json_response(post(c.conn, path, %{session_id: c.target.uuid, to: c.owner.id}), 403)

    for _ <- 1..2 do
      assert %{"task" => %{"session_id" => id}} =
               json_response(
                 post(c.conn, path, %{session_id: c.owner.uuid, to: "#{c.target.id}"}),
                 200
               )

      assert id == c.target.id
    end
  end

  test "missing and malformed session or target return 400", c do
    for params <- [
          %{},
          %{session_id: c.owner.id},
          %{session_id: c.owner.id, to: "invalid"},
          %{session_id: [], to: c.target.id},
          %{session_id: c.owner.id, to: %{}}
        ] do
      assert json_response(post(c.conn, "/api/v1/tasks/#{c.task.id}/handoff", params), 400)
    end
  end

  test "completed tasks and missing tasks have stable errors", c do
    {:ok, current} = Tasks.get_task(c.task.id)
    {:ok, _} = Tasks.complete_task(current, "Done")

    for action <- ["release", "handoff"] do
      params = %{session_id: c.owner.id, to: c.target.uuid}
      assert json_response(post(c.conn, "/api/v1/tasks/#{c.task.id}/#{action}", params), 409)
      assert json_response(post(c.conn, "/api/v1/tasks/999999999/#{action}", params), 404)
    end
  end
end
