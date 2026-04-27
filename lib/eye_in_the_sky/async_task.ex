defmodule EyeInTheSky.AsyncTask do
  @moduledoc """
  Thin wrapper around `Task.Supervisor.start_child` that makes fire-and-forget
  tasks run synchronously in test mode.

  In test mode the Ecto SQL sandbox tears down the connection when the test
  process exits. Orphaned `Task.Supervisor` children that do DB work after
  sandbox teardown cause Postgrex disconnects that contaminate the connection
  pool and cascade into unrelated test failures.

  Setting `config :eye_in_the_sky, :async_tasks_sync, true` in `test.exs`
  makes `start/1` execute the function inline, so the task runs inside the
  test process (which owns the sandbox connection) and completes before teardown.
  """

  @doc """
  Starts `fun` as a supervised fire-and-forget task.

  In test mode (`async_tasks_sync: true`), runs synchronously instead.
  """
  @spec start(fun()) :: :ok
  def start(fun) when is_function(fun, 0) do
    if Application.get_env(:eye_in_the_sky, :async_tasks_sync, false) do
      fun.()
      :ok
    else
      Task.Supervisor.start_child(EyeInTheSky.TaskSupervisor, fun)
      :ok
    end
  end
end
