defmodule EyeInTheSkyWeb.Claude.MockCLI do
  @moduledoc """
  Test double for CLI module. Sends controllable messages instead of spawning ports.
  """

  def spawn_new_session(prompt, opts) do
    spawn_mock_session(:new, prompt, opts)
  end

  def continue_session(prompt, opts) do
    spawn_mock_session(:continue, prompt, opts)
  end

  def resume_session(_session_id, prompt, opts) do
    spawn_mock_session(:resume, prompt, opts)
  end

  def cancel(port) do
    send(port, :cancel)
    :ok
  end

  defp spawn_mock_session(_type, _prompt, opts) do
    caller = Keyword.get(opts, :caller)
    session_ref = Keyword.get(opts, :session_ref)

    port = spawn_link(fn -> mock_port_loop(caller, session_ref) end)

    {:ok, port, session_ref}
  end

  defp mock_port_loop(caller, ref) do
    receive do
      {:send_output, line} ->
        send(caller, {:claude_output, ref, line})
        mock_port_loop(caller, ref)

      {:exit, code} ->
        send(caller, {:claude_exit, ref, code})

      :cancel ->
        send(caller, {:claude_exit, ref, 130})

      :hang ->
        mock_port_loop(caller, ref)
    after
      60_000 -> :ok
    end
  end
end