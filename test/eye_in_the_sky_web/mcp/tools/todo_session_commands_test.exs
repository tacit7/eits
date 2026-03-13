defmodule EyeInTheSkyWeb.MCP.Tools.TodoSessionCommandsTest do
  @moduledoc """
  Tests for Todo MCP tool session-linking commands:
  remove-session, add-session-to-tasks, and unsupported maintenance commands.
  """
  use EyeInTheSkyWeb.DataCase, async: false

  alias EyeInTheSkyWeb.MCP.Tools.Todo
  alias EyeInTheSkyWeb.{Agents, Sessions, Tasks}

  @frame :test_frame

  defp json_result({:reply, %Anubis.Server.Response{content: [%{"text" => json} | _]}, @frame}) do
    Jason.decode!(json, keys: :atoms)
  end

  defp uniq, do: System.unique_integer([:positive])

  defp make_task do
    {:ok, task} =
      Tasks.create_task(%{
        uuid: Ecto.UUID.generate(),
        title: "task #{uniq()}",
        created_at: DateTime.utc_now() |> DateTime.to_iso8601()
      })

    task
  end

  defp tid(task), do: to_string(task.id)

  defp new_session do
    {:ok, agent} = Agents.create_agent(%{name: "tsess-agent-#{uniq()}", status: "idle"})

    {:ok, session} =
      Sessions.create_session(%{
        uuid: "tsess-#{uniq()}",
        agent_id: agent.id,
        started_at: DateTime.utc_now() |> DateTime.to_iso8601(),
        status: "working"
      })

    session
  end

  # ---- remove-session ----

  test "remove-session: unlinks a session from a task" do
    task = make_task()
    session = new_session()

    # Link first via add-session
    Todo.execute(%{command: "add-session", task_id: tid(task), session_id: session.uuid}, @frame)

    r =
      Todo.execute(
        %{command: "remove-session", task_id: tid(task), session_id: session.uuid},
        @frame
      )
      |> json_result()

    assert r.success == true
  end

  test "remove-session: returns success even if link doesn't exist" do
    task = make_task()
    session = new_session()

    r =
      Todo.execute(
        %{command: "remove-session", task_id: tid(task), session_id: session.uuid},
        @frame
      )
      |> json_result()

    assert r.success == true
  end

  test "remove-session: succeeds silently for unknown task (0 rows deleted)" do
    session = new_session()

    r =
      Todo.execute(
        %{command: "remove-session", task_id: "999999", session_id: session.uuid},
        @frame
      )
      |> json_result()

    # unlink is a DELETE — no rows matched is still a successful no-op
    assert r.success == true
    assert String.contains?(r.message, "0")
  end

  test "remove-session: error for unknown session" do
    task = make_task()

    r =
      Todo.execute(
        %{command: "remove-session", task_id: tid(task), session_id: "ghost-uuid"},
        @frame
      )
      |> json_result()

    assert r.success == false
  end

  # ---- add-session-to-tasks ----

  test "add-session-to-tasks: bulk-links session to multiple tasks" do
    session = new_session()
    t1 = make_task()
    t2 = make_task()
    t3 = make_task()

    r =
      Todo.execute(
        %{
          command: "add-session-to-tasks",
          session_id: session.uuid,
          task_ids: [tid(t1), tid(t2), tid(t3)]
        },
        @frame
      )
      |> json_result()

    assert r.success == true
  end

  test "add-session-to-tasks: idempotent — linking twice doesn't error" do
    session = new_session()
    task = make_task()

    Todo.execute(
      %{command: "add-session-to-tasks", session_id: session.uuid, task_ids: [tid(task)]},
      @frame
    )

    r =
      Todo.execute(
        %{command: "add-session-to-tasks", session_id: session.uuid, task_ids: [tid(task)]},
        @frame
      )
      |> json_result()

    assert r.success == true
  end

  test "add-session-to-tasks: error for unknown session" do
    task = make_task()

    r =
      Todo.execute(
        %{command: "add-session-to-tasks", session_id: "ghost-uuid", task_ids: [tid(task)]},
        @frame
      )
      |> json_result()

    assert r.success == false
  end

  test "add-session-to-tasks: empty task_ids list returns error" do
    session = new_session()

    r =
      Todo.execute(
        %{command: "add-session-to-tasks", session_id: session.uuid, task_ids: []},
        @frame
      )
      |> json_result()

    assert r.success == false
    assert String.contains?(r.message, "must not be empty")
  end

  # ---- unsupported maintenance commands ----

  test "reindex: returns unsupported error" do
    r = Todo.execute(%{command: "reindex"}, @frame) |> json_result()
    assert r.success == false

    assert String.contains?(r.message, "unsupported") or
             String.contains?(r.message, "not supported")
  end

  test "vacuum: returns unsupported error" do
    r = Todo.execute(%{command: "vacuum"}, @frame) |> json_result()
    assert r.success == false

    assert String.contains?(r.message, "unsupported") or
             String.contains?(r.message, "not supported")
  end

  test "project-sync: returns unsupported error" do
    r = Todo.execute(%{command: "project-sync"}, @frame) |> json_result()
    assert r.success == false

    assert String.contains?(r.message, "unsupported") or
             String.contains?(r.message, "not supported")
  end
end
