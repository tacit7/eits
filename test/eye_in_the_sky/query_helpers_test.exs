defmodule EyeInTheSky.QueryHelpersTest do
  use EyeInTheSky.DataCase, async: false

  import EyeInTheSky.Factory
  import Ecto.Query, warn: false

  alias EyeInTheSky.{QueryHelpers, Repo, Tasks}
  alias EyeInTheSky.Tasks.Task

  defp make_task(attrs \\ %{}) do
    defaults = %{
      uuid: Ecto.UUID.generate(),
      title: "task #{uniq()}",
      created_at: DateTime.utc_now() |> DateTime.to_iso8601()
    }

    {:ok, task} = Tasks.create_task(Map.merge(defaults, attrs))
    task
  end

  defp link_task_to_session(task, session) do
    Repo.insert_all("task_sessions", [%{task_id: task.id, session_id: session.id}],
      on_conflict: :nothing
    )
  end

  # ---- for_session_join ----

  describe "for_session_join/4" do
    # Tasks use created_at/updated_at strings, not inserted_at. Always pass order_by explicitly.
    @task_order [order_by: [asc: :id]]

    test "returns tasks linked to a session via task_sessions (default keys)" do
      session = new_session()
      task = make_task()
      link_task_to_session(task, session)

      result = QueryHelpers.for_session_join(Task, session.id, "task_sessions", @task_order)

      assert task.id in Enum.map(result, & &1.id)
    end

    test "does not return tasks linked to a different session" do
      session_a = new_session()
      session_b = new_session()
      task = make_task()
      link_task_to_session(task, session_a)

      result = QueryHelpers.for_session_join(Task, session_b.id, "task_sessions", @task_order)

      refute task.id in Enum.map(result, & &1.id)
    end

    test "returns empty list when no tasks are linked" do
      session = new_session()
      assert QueryHelpers.for_session_join(Task, session.id, "task_sessions", @task_order) == []
    end

    test "respects :limit opt" do
      session = new_session()
      for _ <- 1..3, do: link_task_to_session(make_task(), session)

      result =
        QueryHelpers.for_session_join(
          Task,
          session.id,
          "task_sessions",
          @task_order ++ [limit: 1]
        )

      assert length(result) == 1
    end

    test "accepts explicit :entity_key and :session_key matching defaults" do
      session = new_session()
      task = make_task()
      link_task_to_session(task, session)

      result =
        QueryHelpers.for_session_join(
          Task,
          session.id,
          "task_sessions",
          @task_order ++ [entity_key: :task_id, session_key: :session_id]
        )

      assert task.id in Enum.map(result, & &1.id)
    end

    test "applies :preload opt without error" do
      session = new_session()
      task = make_task()
      link_task_to_session(task, session)

      result =
        QueryHelpers.for_session_join(
          Task,
          session.id,
          "task_sessions",
          @task_order ++ [preload: [:state]]
        )

      assert length(result) >= 1
    end
  end

  # ---- count_for_session_join ----

  describe "count_for_session_join/4" do
    test "returns correct count for linked tasks" do
      session = new_session()
      for _ <- 1..3, do: link_task_to_session(make_task(), session)

      assert QueryHelpers.count_for_session_join(Task, session.id, "task_sessions") >= 3
    end

    test "returns 0 when no tasks are linked" do
      session = new_session()
      assert QueryHelpers.count_for_session_join(Task, session.id, "task_sessions") == 0
    end

    test "does not count tasks linked to other sessions" do
      session_a = new_session()
      session_b = new_session()
      link_task_to_session(make_task(), session_a)

      assert QueryHelpers.count_for_session_join(Task, session_b.id, "task_sessions") == 0
    end

    test "accepts explicit :entity_key and :session_key matching defaults" do
      session = new_session()
      link_task_to_session(make_task(), session)

      count =
        QueryHelpers.count_for_session_join(Task, session.id, "task_sessions",
          entity_key: :task_id,
          session_key: :session_id
        )

      assert count >= 1
    end
  end
end
