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

    # Drain any startup banner (shell prompt, etc.)
    collect_until_idle(500)

    PtyServer.write(pid, "echo pty_echo_smoke\n")

    # Collect until we see the command output line, up to 10s total.
    # PTY echoes input in chunks; pattern-based collect is reliable where
    # idle-timeout collect is not. 10s gives headroom under full-suite load.
    output = collect_until_pattern("pty_echo_smoke\r\n", 10_000)

    assert output =~ "echo pty_echo_smoke"
    assert output =~ "pty_echo_smoke\r\n"
  end

  # Collect messages until `pattern` is found in the accumulated buffer,
  # or `deadline_ms` milliseconds have elapsed since the call.
  defp collect_until_pattern(pattern, deadline_ms) do
    deadline = System.monotonic_time(:millisecond) + deadline_ms
    collect_until_pattern(pattern, "", deadline)
  end

  defp collect_until_pattern(pattern, acc, deadline) do
    if acc =~ pattern do
      acc
    else
      remaining = deadline - System.monotonic_time(:millisecond)

      if remaining <= 0 do
        acc
      else
        receive do
          {:pty_output, data} ->
            collect_until_pattern(pattern, acc <> data, deadline)
        after
          min(remaining, 100) ->
            acc
        end
      end
    end
  end

  # Drain all output until `idle_ms` passes with no new data.
  defp collect_until_idle(idle_ms) do
    receive do
      {:pty_output, _data} -> collect_until_idle(idle_ms)
    after
      idle_ms -> :ok
    end
  end
end
