defmodule EyeInTheSkyWebWeb.Api.V1.TaskControllerTest do
  use EyeInTheSkyWebWeb.ConnCase, async: false

  alias EyeInTheSkyWeb.{Agents, Sessions, Tasks}

  defp uniq, do: System.unique_integer([:positive])

  defp create_agent do
    {:ok, agent} =
      Agents.create_agent(%{
        uuid: Ecto.UUID.generate(),
        description: "Test agent #{uniq()}",
        source: "test"
      })

    agent
  end

  defp create_session(agent) do
    {:ok, session} =
      Sessions.create_session(%{
        uuid: Ecto.UUID.generate(),
        agent_id: agent.id,
        name: "Test session #{uniq()}",
        status: "working",
        started_at: DateTime.utc_now() |> DateTime.to_iso8601()
      })

    session
  end

  defp create_task(overrides \\ %{}) do
    {:ok, task} =
      Tasks.create_task(
        Map.merge(
          %{
            uuid: Ecto.UUID.generate(),
            title: "Test task #{uniq()}",
            state_id: 1,
            created_at: DateTime.utc_now() |> DateTime.to_iso8601()
          },
          overrides
        )
      )

    task
  end

  # ---- GET /api/v1/tasks ----

  describe "GET /api/v1/tasks" do
    test "returns task list", %{conn: conn} do
      create_task()
      conn = get(conn, ~p"/api/v1/tasks")
      resp = json_response(conn, 200)

      assert resp["success"] == true
      assert is_list(resp["tasks"])
      assert length(resp["tasks"]) >= 1
    end

    test "filters by state_id", %{conn: conn} do
      create_task(%{state_id: 1})
      conn = get(conn, ~p"/api/v1/tasks?state_id=1")
      resp = json_response(conn, 200)

      assert resp["success"] == true
      assert Enum.all?(resp["tasks"], &(&1["state_id"] == 1))
    end

    test "searches by q param", %{conn: conn} do
      unique_title = "UniqueTitleXYZ#{uniq()}"
      create_task(%{title: unique_title})
      conn = get(conn, ~p"/api/v1/tasks?q=#{unique_title}")
      resp = json_response(conn, 200)

      assert resp["success"] == true
      assert Enum.any?(resp["tasks"], &String.contains?(&1["title"], "UniqueTitleXYZ"))
    end

    test "filters by session_id", %{conn: conn} do
      agent = create_agent()
      session = create_session(agent)
      task = create_task()

      EyeInTheSkyWeb.Repo.insert_all("task_sessions", [%{task_id: task.id, session_id: session.id}],
        on_conflict: :nothing
      )

      conn = get(conn, ~p"/api/v1/tasks?session_id=#{session.uuid}")
      resp = json_response(conn, 200)

      assert resp["success"] == true
      assert Enum.any?(resp["tasks"], &(&1["id"] == task.id))
    end

    test "respects limit param", %{conn: conn} do
      for _ <- 1..5, do: create_task()
      conn = get(conn, ~p"/api/v1/tasks?limit=2")
      resp = json_response(conn, 200)

      assert length(resp["tasks"]) <= 2
    end
  end

  # ---- POST /api/v1/tasks ----

  describe "POST /api/v1/tasks" do
    test "creates a task with valid params", %{conn: conn} do
      conn = post(conn, ~p"/api/v1/tasks", %{"title" => "My new task"})
      resp = json_response(conn, 201)

      assert resp["success"] == true
      assert resp["task_id"] != nil
    end

    test "returns 422 when title is missing", %{conn: conn} do
      conn = post(conn, ~p"/api/v1/tasks", %{"description" => "no title"})
      resp = json_response(conn, 422)

      assert resp["error"] == "Failed to create task"
    end

    test "links session on create", %{conn: conn} do
      agent = create_agent()
      session = create_session(agent)

      conn =
        post(conn, ~p"/api/v1/tasks", %{
          "title" => "Task with session",
          "session_id" => session.uuid
        })

      assert json_response(conn, 201)["success"] == true
    end
  end

  # ---- GET /api/v1/tasks/:id ----

  describe "GET /api/v1/tasks/:id" do
    test "returns a task with annotations", %{conn: conn} do
      task = create_task()
      conn = get(conn, ~p"/api/v1/tasks/#{task.id}")
      resp = json_response(conn, 200)

      assert resp["success"] == true
      assert resp["task"]["id"] == task.id
      assert resp["task"]["title"] == task.title
      assert is_list(resp["annotations"])
    end

    test "returns 404 for missing task", %{conn: conn} do
      conn = get(conn, ~p"/api/v1/tasks/9999999")
      assert json_response(conn, 404)["error"] == "Task not found"
    end
  end

  # ---- PATCH /api/v1/tasks/:id ----

  describe "PATCH /api/v1/tasks/:id" do
    test "updates task state to done via shorthand", %{conn: conn} do
      task = create_task()
      conn = patch(conn, ~p"/api/v1/tasks/#{task.id}", %{"state" => "done"})
      resp = json_response(conn, 200)

      assert resp["success"] == true
      # state_id 3 = Done; state name is nil since assoc not preloaded after update
      assert resp["task"]["state_id"] == 3
    end

    test "updates task state to in progress via shorthand", %{conn: conn} do
      task = create_task()
      conn = patch(conn, ~p"/api/v1/tasks/#{task.id}", %{"state" => "start"})
      resp = json_response(conn, 200)

      assert resp["success"] == true
      # state_id 2 = In Progress
      assert resp["task"]["state_id"] == 2
    end

    test "updates state_id directly", %{conn: conn} do
      task = create_task()
      conn = patch(conn, ~p"/api/v1/tasks/#{task.id}", %{"state_id" => 3})
      resp = json_response(conn, 200)

      assert resp["success"] == true
      assert resp["task"]["state_id"] == 3
    end

    test "updates description", %{conn: conn} do
      task = create_task()
      conn = patch(conn, ~p"/api/v1/tasks/#{task.id}", %{"description" => "Updated desc"})
      resp = json_response(conn, 200)

      assert resp["success"] == true
    end

    test "returns 404 for missing task", %{conn: conn} do
      conn = patch(conn, ~p"/api/v1/tasks/9999999", %{"state" => "done"})
      assert json_response(conn, 404)["error"] == "Task not found"
    end
  end

  # ---- DELETE /api/v1/tasks/:id ----

  describe "DELETE /api/v1/tasks/:id" do
    test "deletes a task", %{conn: conn} do
      task = create_task()
      conn = delete(conn, ~p"/api/v1/tasks/#{task.id}")
      resp = json_response(conn, 200)

      assert resp["success"] == true
      assert resp["message"] == "Task deleted"
    end

    test "returns 404 for missing task", %{conn: conn} do
      conn = delete(conn, ~p"/api/v1/tasks/9999999")
      assert json_response(conn, 404)["error"] == "Task not found"
    end
  end

  # ---- POST /api/v1/tasks/:id/annotations ----

  describe "POST /api/v1/tasks/:id/annotations" do
    test "adds an annotation to a task", %{conn: conn} do
      task = create_task()
      conn = post(conn, ~p"/api/v1/tasks/#{task.id}/annotations", %{"body" => "This is a note"})
      resp = json_response(conn, 201)

      assert resp["success"] == true
      assert resp["note_id"] != nil
    end

    test "annotation with title", %{conn: conn} do
      task = create_task()

      conn =
        post(conn, ~p"/api/v1/tasks/#{task.id}/annotations", %{
          "body" => "body",
          "title" => "Decision"
        })

      assert json_response(conn, 201)["success"] == true
    end
  end

  # ---- POST /api/v1/tasks/:id/sessions ----

  describe "POST /api/v1/tasks/:id/sessions" do
    test "links a session to a task", %{conn: conn} do
      agent = create_agent()
      session = create_session(agent)
      task = create_task()

      conn =
        post(conn, ~p"/api/v1/tasks/#{task.id}/sessions", %{"session_id" => session.uuid})

      resp = json_response(conn, 200)
      assert resp["success"] == true
    end

    test "returns 400 when session_id is missing", %{conn: conn} do
      task = create_task()
      conn = post(conn, ~p"/api/v1/tasks/#{task.id}/sessions", %{})
      assert json_response(conn, 400)["error"] == "session_id is required"
    end
  end

  # ---- DELETE /api/v1/tasks/:id/sessions/:uuid ----

  describe "DELETE /api/v1/tasks/:id/sessions/:uuid" do
    test "unlinks a session from a task", %{conn: conn} do
      agent = create_agent()
      session = create_session(agent)
      task = create_task()

      EyeInTheSkyWeb.Repo.insert_all("task_sessions", [%{task_id: task.id, session_id: session.id}],
        on_conflict: :nothing
      )

      conn = delete(conn, ~p"/api/v1/tasks/#{task.id}/sessions/#{session.uuid}")
      resp = json_response(conn, 200)

      assert resp["success"] == true
    end

    test "returns 404 for unknown session", %{conn: conn} do
      task = create_task()
      conn = delete(conn, ~p"/api/v1/tasks/#{task.id}/sessions/#{Ecto.UUID.generate()}")
      assert json_response(conn, 404)["error"] == "Session not found"
    end
  end
end
