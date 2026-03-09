defmodule EyeInTheSkyWeb.SessionManagerCase do
  @moduledoc """
  Test case template for SessionManager tests with helpers and utilities.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      import EyeInTheSkyWeb.SessionManagerCase

      @registry EyeInTheSkyWeb.Claude.Registry
      @supervisor EyeInTheSkyWeb.Claude.SessionSupervisor
    end
  end

  setup do
    # Override CLI module with mock
    Application.put_env(:eye_in_the_sky_web, :cli_module, EyeInTheSkyWeb.Claude.MockCLI)

    on_exit(fn ->
      # Restore to MockCLI (test default from config/test.exs) rather than deleting,
      # so subsequent tests aren't left with nil after delete_env removes the key.
      Application.put_env(:eye_in_the_sky_web, :cli_module, EyeInTheSkyWeb.Claude.MockCLI)
    end)

    :ok
  end

  def await_worker(session_id, timeout \\ 1000) do
    deadline = System.monotonic_time(:millisecond) + timeout
    await_worker_loop(session_id, deadline)
  end

  defp await_worker_loop(session_id, deadline) do
    case Registry.lookup(EyeInTheSkyWeb.Claude.Registry, {:session, session_id}) do
      [{pid, _}] when is_pid(pid) ->
        {:ok, pid}

      [] ->
        if System.monotonic_time(:millisecond) < deadline do
          Process.sleep(10)
          await_worker_loop(session_id, deadline)
        else
          {:error, :timeout}
        end
    end
  end

  def get_mock_port(pid) do
    state = :sys.get_state(pid)
    state.port
  end

  def send_mock_output(port, line) do
    send(port, {:send_output, line})
  end

  def send_mock_exit(port, code \\ 0) do
    send(port, {:exit, code})
  end

  def make_port_hang(port) do
    send(port, :hang)
  end

  def subscribe_session_status(session_id) do
    Phoenix.PubSub.subscribe(EyeInTheSkyWeb.PubSub, "session:#{session_id}:status")
  end

  def assert_status_broadcast(session_id, expected_status, timeout \\ 1000) do
    assert_receive {:session_status, ^session_id, ^expected_status}, timeout
  end
end
