defmodule EyeInTheSkyWeb.Api.V1.StandupTaskFilterTest do
  @moduledoc """
  Tests for the `since` and `stale_since` query params on GET /api/v1/tasks.
  """

  use EyeInTheSkyWeb.ConnCase, async: false

  import Ecto.Query, only: [from: 2]

  alias EyeInTheSky.Accounts.ApiKey
  alias EyeInTheSky.{Repo, Tasks}
  alias EyeInTheSky.Tasks.WorkflowState

  defp api_conn do
    token = "test_api_key_#{System.unique_integer([:positive])}"
    {:ok, _} = ApiKey.create(token, "test")
    Phoenix.ConnTest.build_conn() |> Plug.Conn.put_req_header("authorization", "Bearer #{token}")
  end

  setup do
    {:ok, conn: api_conn()}
  end

  # Back-date a task's updated_at to simulate it being older than the window.
  defp backdate_task(task, hours_ago) do
    past = DateTime.add(DateTime.utc_now(), -(hours_ago * 3600), :second)
    task_id = task.id

    Repo.update_all(
      from(t in "tasks", where: t.id == ^task_id),
      set: [updated_at: past]
    )
  end

  defp create_task(overrides \\ %{}) do
    {:ok, task} =
      Tasks.create_task(
        Map.merge(
          %{
            uuid: Ecto.UUID.generate(),
            title: "Task #{System.unique_integer([:positive])}",
            state_id: WorkflowState.todo_id(),
            created_at: DateTime.utc_now(),
            updated_at: DateTime.utc_now()
          },
          overrides
        )
      )

    task
  end

  describe "GET /api/v1/tasks?since=<duration>" do
    test "returns 400 on invalid duration", %{conn: conn} do
      conn = get(conn, ~p"/api/v1/tasks?since=invalid")
      resp = json_response(conn, 400)
      assert resp["error"] =~ "Invalid duration"
    end

    test "returns tasks updated within the window", %{conn: conn} do
      recent_task = create_task()
      old_task = create_task()
      backdate_task(old_task, 48)

      conn = get(conn, ~p"/api/v1/tasks?since=24h")
      resp = json_response(conn, 200)

      ids = Enum.map(resp["tasks"], & &1["id"])
      assert recent_task.id in ids
      refute old_task.id in ids
    end

    test "no since param returns all tasks (backward compat)", %{conn: conn} do
      task = create_task()
      backdate_task(task, 72)

      conn = get(conn, ~p"/api/v1/tasks")
      resp = json_response(conn, 200)

      ids = Enum.map(resp["tasks"], & &1["id"])
      assert task.id in ids
    end
  end

  describe "GET /api/v1/tasks?stale_since=<duration>" do
    test "returns 400 on invalid stale_since", %{conn: conn} do
      conn = get(conn, ~p"/api/v1/tasks?stale_since=garbage")
      resp = json_response(conn, 400)
      assert resp["error"] =~ "Invalid duration"
    end

    test "returns non-done tasks not updated within the stale window", %{conn: conn} do
      stale_task = create_task(%{state_id: WorkflowState.in_progress_id()})
      backdate_task(stale_task, 48)

      recent_task = create_task(%{state_id: WorkflowState.in_progress_id()})
      done_task = create_task(%{state_id: WorkflowState.done_id()})
      backdate_task(done_task, 48)

      conn = get(conn, ~p"/api/v1/tasks?stale_since=24h")
      resp = json_response(conn, 200)

      ids = Enum.map(resp["tasks"], & &1["id"])

      # Stale in-progress: should appear
      assert stale_task.id in ids
      # Recently updated in-progress: should NOT appear (updated_at is fresh)
      refute recent_task.id in ids
      # Done task: excluded (terminal state)
      refute done_task.id in ids
    end
  end
end
