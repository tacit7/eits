defmodule EyeInTheSkyWeb.MCP.Tools.TodoToolTest do
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

  # task_id in the tool is always the integer PK as a string
  defp tid(task), do: to_string(task.id)

  # ---- create ----

  test "create: makes a task and returns task_id" do
    r = Todo.execute(%{command: "create", title: "Do something"}, @frame) |> json_result()
    assert r.success == true
    assert r.message == "Task created"
    assert is_binary(r.task_id)
  end

  test "create: includes description" do
    r = Todo.execute(%{command: "create", title: "T", description: "details"}, @frame) |> json_result()
    assert r.success == true
  end

  # ---- done ----

  test "done: marks task done" do
    t = make_task()
    r = Todo.execute(%{command: "done", task_id: tid(t)}, @frame) |> json_result()
    assert r.success == true
  end

  test "done: error for unknown task" do
    r = Todo.execute(%{command: "done", task_id: "999999999"}, @frame) |> json_result()
    assert r.success == false
  end

  # ---- status ----

  test "status: updates task state_id" do
    t = make_task()
    r = Todo.execute(%{command: "status", task_id: tid(t), state_id: 2}, @frame) |> json_result()
    assert r.success == true
  end

  test "status: error for unknown task" do
    r = Todo.execute(%{command: "status", task_id: "999999999", state_id: 1}, @frame) |> json_result()
    assert r.success == false
  end

  # ---- list ----

  test "list: returns all tasks" do
    make_task()
    r = Todo.execute(%{command: "list"}, @frame) |> json_result()
    assert r.success == true
    assert is_list(r.tasks)
    assert length(r.tasks) >= 1
  end

  # ---- list-agent ----

  test "list-agent: returns empty list for unknown agent UUID" do
    r = Todo.execute(%{command: "list-agent", agent_id: "nobody"}, @frame) |> json_result()
    assert r.success == true
    assert is_list(r.tasks)
  end

  # ---- list-session ----

  test "list-session: returns tasks list for session UUID" do
    {:ok, agent} = Agents.create_agent(%{name: "s#{uniq()}", status: "active"})
    {:ok, session} = Sessions.create_session(%{
      uuid: "ss-#{uniq()}",
      agent_id: agent.id,
      started_at: DateTime.utc_now() |> DateTime.to_iso8601(),
      status: "active"
    })
    r = Todo.execute(%{command: "list-session", session_id: session.uuid}, @frame) |> json_result()
    assert r.success == true
    assert is_list(r.tasks)
  end

  # ---- search ----

  test "search: returns tasks matching query" do
    make_task(%{title: "searchable task xyzabc#{uniq()}"})
    r = Todo.execute(%{command: "search", query: "xyzabc"}, @frame) |> json_result()
    assert r.success == true
    assert is_list(r.tasks)
  end

  test "search: empty list for no match" do
    r = Todo.execute(%{command: "search", query: "zzznomatchqwerty"}, @frame) |> json_result()
    assert r.success == true
    assert r.tasks == []
  end

  # ---- delete ----

  test "delete: removes a task" do
    t = make_task()
    r = Todo.execute(%{command: "delete", task_id: tid(t)}, @frame) |> json_result()
    assert r.success == true
  end

  test "delete: error for unknown task" do
    r = Todo.execute(%{command: "delete", task_id: "999999999"}, @frame) |> json_result()
    assert r.success == false
  end

  # ---- annotate ----

  test "annotate: adds note to a task" do
    t = make_task()
    r = Todo.execute(%{command: "annotate", task_id: tid(t), body: "some note"}, @frame) |> json_result()
    assert r.success == true
  end

  # ---- unknown command ----

  test "unknown command: returns text response, not an error" do
    {:reply, response, @frame} = Todo.execute(%{command: "bogus_cmd"}, @frame)
    assert response.isError == false
    assert length(response.content) == 1
  end
end
