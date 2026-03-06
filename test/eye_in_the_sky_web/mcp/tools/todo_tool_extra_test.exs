defmodule EyeInTheSkyWeb.MCP.Tools.TodoToolExtraTest do
  @moduledoc """
  Additional tests for Todo MCP tool commands not covered by TodoToolTest:
  start, tag, add-session, create with tags/session.
  """
  use EyeInTheSkyWeb.DataCase, async: false

  alias EyeInTheSkyWeb.MCP.Tools.Todo
  alias EyeInTheSkyWeb.{Agents, Sessions, Tasks}

  @frame :test_frame

  defp json_result({:reply, %Anubis.Server.Response{content: [%{"text" => json} | _]}, @frame}) do
    Jason.decode!(json, keys: :atoms)
  end

  defp uniq, do: System.unique_integer([:positive])

  defp make_task(attrs \\ %{}) do
    defaults = %{
      uuid: Ecto.UUID.generate(),
      title: "task #{uniq()}",
      created_at: DateTime.utc_now() |> DateTime.to_iso8601()
    }

    {:ok, task} = Tasks.create_task(Map.merge(defaults, attrs))
    task
  end

  defp tid(task), do: to_string(task.id)

  defp new_session do
    {:ok, agent} = Agents.create_agent(%{name: "todo-agent-#{uniq()}", status: "idle"})

    {:ok, session} =
      Sessions.create_session(%{
        uuid: "todo-sess-#{uniq()}",
        agent_id: agent.id,
        started_at: DateTime.utc_now() |> DateTime.to_iso8601(),
        status: "working"
      })

    session
  end

  # ---- start ----

  test "start: moves task to In Progress" do
    t = make_task()
    r = Todo.execute(%{command: "start", task_id: tid(t)}, @frame) |> json_result()
    assert r.success == true
    assert r.message == "Task moved to In Progress"
  end

  test "start: error for unknown task" do
    r = Todo.execute(%{command: "start", task_id: "999999999"}, @frame) |> json_result()
    assert r.success == false
    assert String.contains?(r.message, "not found")
  end

  # ---- tag ----

  test "tag: adds tags to a task" do
    t = make_task()
    r = Todo.execute(%{command: "tag", task_id: tid(t), tags: ["bug", "urgent"]}, @frame) |> json_result()
    assert r.success == true
    assert String.contains?(r.message, "Tags updated")
  end

  test "tag: handles empty tags list" do
    t = make_task()
    r = Todo.execute(%{command: "tag", task_id: tid(t), tags: []}, @frame) |> json_result()
    assert r.success == true
  end

  test "tag: error for unknown task" do
    r = Todo.execute(%{command: "tag", task_id: "999999999", tags: ["test"]}, @frame) |> json_result()
    assert r.success == false
    assert String.contains?(r.message, "not found")
  end

  # ---- add-session ----

  test "add-session: links session to task" do
    t = make_task()
    s = new_session()
    r = Todo.execute(%{command: "add-session", task_id: tid(t), session_id: s.uuid}, @frame) |> json_result()
    assert r.success == true
    assert String.contains?(r.message, "Session linked")
  end

  test "add-session: error when session_id missing" do
    t = make_task()
    r = Todo.execute(%{command: "add-session", task_id: tid(t)}, @frame) |> json_result()
    assert r.success == false
    assert r.message == "session_id required"
  end

  # ---- create with session linking ----

  test "create: links session when session_id provided" do
    s = new_session()

    r =
      Todo.execute(
        %{command: "create", title: "Linked task #{uniq()}", session_id: s.uuid},
        @frame
      )
      |> json_result()

    assert r.success == true
    assert r.message == "Task created"
  end

  # ---- create with tags ----

  test "create: processes tags when provided" do
    r =
      Todo.execute(
        %{command: "create", title: "Tagged task #{uniq()}", tags: ["feature", "v2"]},
        @frame
      )
      |> json_result()

    assert r.success == true
    assert r.message == "Task created"
  end

  # ---- list with limit ----

  test "list: respects limit parameter" do
    for _ <- 1..5, do: make_task()

    r = Todo.execute(%{command: "list", limit: 2}, @frame) |> json_result()
    assert r.success == true
    assert length(r.tasks) <= 2
  end

  # ---- search with limit ----

  test "search: respects limit parameter" do
    for i <- 1..5, do: make_task(%{title: "limitcheck#{uniq()}_#{i}"})

    r = Todo.execute(%{command: "search", query: "limitcheck", limit: 2}, @frame) |> json_result()
    assert r.success == true
    assert length(r.tasks) <= 2
  end

  # ---- annotate edge case ----

  test "annotate: includes title when provided" do
    t = make_task()

    r =
      Todo.execute(
        %{command: "annotate", task_id: tid(t), body: "note body", title: "note title"},
        @frame
      )
      |> json_result()

    assert r.success == true
    assert is_integer(r.note_id)
  end

  # ---- status with priority ----

  test "status: updates priority" do
    t = make_task()
    r = Todo.execute(%{command: "status", task_id: tid(t), priority: 5}, @frame) |> json_result()
    assert r.success == true
  end
end
