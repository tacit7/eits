defmodule EyeInTheSkyWeb.Api.V1.TaskControllerTest do
  use EyeInTheSkyWeb.ConnCase, async: false

  import Ecto.Query, only: [from: 2]

  alias EyeInTheSky.{Repo, Tasks}
  alias EyeInTheSky.Tasks.WorkflowState
  alias EyeInTheSky.Accounts.ApiKey

  import EyeInTheSky.Factory

  defp api_conn do
    token = "test_api_key_#{System.unique_integer([:positive])}"
    {:ok, _} = ApiKey.create(token, "test")
    Phoenix.ConnTest.build_conn() |> Plug.Conn.put_req_header("authorization", "Bearer #{token}")
  end

  setup do
    {:ok, conn: api_conn()}
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
      assert resp["tasks"] != []
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

      EyeInTheSky.Repo.insert_all(
        "task_sessions",
        [%{task_id: task.id, session_id: session.id}],
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

    test "links session atomically when starting a task", %{conn: conn} do
      agent = create_agent()
      session = create_session(agent)
      task = create_task()

      patch(conn, ~p"/api/v1/tasks/#{task.id}", %{
        "state" => "start",
        "session_id" => session.uuid
      })

      linked =
        Repo.exists?(
          from(ts in "task_sessions",
            where: ts.task_id == ^task.id and ts.session_id == ^session.id
          )
        )

      assert linked
    end

    test "start without session_id succeeds without linking", %{conn: conn} do
      task = create_task()
      conn = patch(conn, ~p"/api/v1/tasks/#{task.id}", %{"state" => "start"})
      resp = json_response(conn, 200)

      assert resp["success"] == true
      assert resp["task"]["state_id"] == 2
    end

    test "start is idempotent for session linking", %{conn: conn} do
      agent = create_agent()
      session = create_session(agent)
      task = create_task()

      patch(conn, ~p"/api/v1/tasks/#{task.id}", %{
        "state" => "start",
        "session_id" => session.uuid
      })

      patch(api_conn(), ~p"/api/v1/tasks/#{task.id}", %{
        "state" => "start",
        "session_id" => session.uuid
      })

      count =
        Repo.one(
          from(ts in "task_sessions",
            where: ts.task_id == ^task.id and ts.session_id == ^session.id,
            select: count()
          )
        )

      assert count == 1
    end
  end

  # ---- tasks quick workflow (POST /tasks + PATCH /tasks/:id state=start) ----

  describe "tasks quick workflow" do
    test "create with session then start links session and sets state 2", %{conn: conn} do
      agent = create_agent()
      session = create_session(agent)

      # Step 1: create with session_id (mirrors eits tasks create)
      create_resp =
        post(conn, ~p"/api/v1/tasks", %{
          "title" => "quick workflow task",
          "session_id" => session.uuid
        })

      task_id = json_response(create_resp, 201)["task_id"]
      assert task_id != nil

      # Step 2: start with session_id (mirrors eits tasks start)
      patch(api_conn(), ~p"/api/v1/tasks/#{task_id}", %{
        "state" => "start",
        "session_id" => session.uuid
      })

      task = Tasks.get_task!(task_id)
      assert task.state_id == 2

      linked =
        Repo.exists?(
          from(ts in "task_sessions",
            where: ts.task_id == ^task.id and ts.session_id == ^session.id
          )
        )

      assert linked
    end

    test "quick workflow without session still sets state 2", %{conn: conn} do
      create_resp = post(conn, ~p"/api/v1/tasks", %{"title" => "no session quick"})
      task_id = json_response(create_resp, 201)["task_id"]

      patch(api_conn(), ~p"/api/v1/tasks/#{task_id}", %{"state" => "start"})

      task = Tasks.get_task!(task_id)
      assert task.state_id == 2
    end

    test "double-starting the same task with same session is idempotent", %{conn: conn} do
      agent = create_agent()
      session = create_session(agent)

      create_resp =
        post(conn, ~p"/api/v1/tasks", %{
          "title" => "idempotent quick",
          "session_id" => session.uuid
        })

      task_id = json_response(create_resp, 201)["task_id"]
      task = Tasks.get_task!(task_id)

      patch(api_conn(), ~p"/api/v1/tasks/#{task_id}", %{
        "state" => "start",
        "session_id" => session.uuid
      })

      patch(api_conn(), ~p"/api/v1/tasks/#{task_id}", %{
        "state" => "start",
        "session_id" => session.uuid
      })

      count =
        Repo.one(
          from(ts in "task_sessions",
            where: ts.task_id == ^task.id and ts.session_id == ^session.id,
            select: count()
          )
        )

      assert count == 1
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

      EyeInTheSky.Repo.insert_all(
        "task_sessions",
        [%{task_id: task.id, session_id: session.id}],
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

  describe "POST /api/v1/tasks/:id/complete" do
    setup %{conn: conn} do
      {:ok, project} = EyeInTheSky.Projects.create_project(%{name: "CompleteTest#{uniq()}", path: "/tmp/complete_#{uniq()}"})
      {:ok, task} = Tasks.create_task(%{title: "Complete me", project_id: project.id, state_id: 1, uuid: Ecto.UUID.generate(), created_at: DateTime.utc_now()})
      %{conn: conn, task: task}
    end

    test "marks task done and creates annotation", %{conn: conn, task: task} do
      conn = post(conn, ~p"/api/v1/tasks/#{task.id}/complete", %{
        "message" => "All done"
      })
      assert %{"success" => true} = json_response(conn, 200)
      {:ok, updated} = Tasks.get_task(task.id)
      assert updated.state_id == WorkflowState.done_id()

      note = Repo.one(
        from n in EyeInTheSky.Notes.Note,
          where: n.parent_type == "task" and n.parent_id == ^to_string(task.id) and n.body == "All done"
      )
      assert note != nil
    end

    test "returns 404 for missing task", %{conn: conn} do
      conn = post(conn, ~p"/api/v1/tasks/999999/complete", %{"message" => "done"})
      assert json_response(conn, 404)
    end

    test "requires message", %{conn: conn, task: task} do
      conn = post(conn, ~p"/api/v1/tasks/#{task.id}/complete", %{})
      assert %{"success" => false} = json_response(conn, 422)
    end

    test "calling complete twice is idempotent — task stays Done", %{conn: conn, task: task} do
      post(conn, ~p"/api/v1/tasks/#{task.id}/complete", %{"message" => "first"})
      conn2 = post(conn, ~p"/api/v1/tasks/#{task.id}/complete", %{"message" => "second"})
      assert %{"success" => true} = json_response(conn2, 200)
      {:ok, updated} = Tasks.get_task(task.id)
      assert updated.state_id == WorkflowState.done_id()
    end
  end

  describe "PATCH /api/v1/tasks/:id - state aliases" do
    test "state: in-review moves to In Review", %{conn: conn} do
      task = create_task()
      conn = patch(conn, ~p"/api/v1/tasks/#{task.id}", %{"state" => "in-review"})
      assert %{"success" => true} = json_response(conn, 200)
      updated = Tasks.get_task!(task.id)
      assert updated.state_id == WorkflowState.in_review_id()
    end

    test "state: todo moves to To Do", %{conn: conn} do
      task = create_task(%{state_id: WorkflowState.in_progress_id()})
      conn = patch(conn, ~p"/api/v1/tasks/#{task.id}", %{"state" => "todo"})
      assert %{"success" => true} = json_response(conn, 200)
      updated = Tasks.get_task!(task.id)
      assert updated.state_id == WorkflowState.todo_id()
    end

    test "state: done moves to Done", %{conn: conn} do
      task = create_task()
      conn = patch(conn, ~p"/api/v1/tasks/#{task.id}", %{"state" => "done"})
      assert %{"success" => true} = json_response(conn, 200)
      updated = Tasks.get_task!(task.id)
      assert updated.state_id == WorkflowState.done_id()
    end

    test "state_id integer still works", %{conn: conn} do
      task = create_task()
      conn = patch(conn, ~p"/api/v1/tasks/#{task.id}", %{"state_id" => WorkflowState.done_id()})
      assert %{"success" => true} = json_response(conn, 200)
      updated = Tasks.get_task!(task.id)
      assert updated.state_id == WorkflowState.done_id()
    end

    test "invalid alias returns 422", %{conn: conn} do
      task = create_task()
      conn = patch(conn, ~p"/api/v1/tasks/#{task.id}", %{"state" => "purple"})
      assert %{"success" => false, "error" => msg} = json_response(conn, 422)
      assert String.contains?(msg, "Unknown state alias")
    end

    test "alias is case-insensitive", %{conn: conn} do
      task = create_task()
      conn = patch(conn, ~p"/api/v1/tasks/#{task.id}", %{"state" => "DONE"})
      assert %{"success" => true} = json_response(conn, 200)
      updated = Tasks.get_task!(task.id)
      assert updated.state_id == WorkflowState.done_id()
    end
  end
end
