defmodule EyeInTheSky.Terminal.PtyServerTest do
  use ExUnit.Case, async: false

  alias EyeInTheSky.Terminal.{PtyServer, PtySupervisor}

  test "echoes typed input back through the PTY" do
    {:ok, pid} = PtySupervisor.start_pty(subscriber: self(), cols: 120, rows: 40)

    on_exit(fn ->
      if Process.alive?(pid) do
        PtyServer.stop(pid)
      end
    end)

    _initial_output = collect_output()

    PtyServer.write(pid, "echo pty_echo_smoke\n")

    output = collect_output()

    assert output =~ "echo pty_echo_smoke"
    assert output =~ "pty_echo_smoke\r\n"
  end

  defp collect_output(chunks \\ [], idle_ms \\ 200, total_ms \\ 2_000)

  defp collect_output(chunks, _idle_ms, total_ms) when total_ms <= 0 do
    IO.iodata_to_binary(Enum.reverse(chunks))
  end

  defp collect_output(chunks, idle_ms, total_ms) do
    receive do
      {:pty_output, data} ->
        collect_output([data | chunks], idle_ms, total_ms - idle_ms)
    after
      idle_ms ->
        IO.iodata_to_binary(Enum.reverse(chunks))
    end
  end
end
