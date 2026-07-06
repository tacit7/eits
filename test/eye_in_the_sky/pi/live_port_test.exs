defmodule EyeInTheSky.Pi.LivePortTest do
  @moduledoc """
  Live transport smoke test for the Pi harness. Excluded by default; run with:

      scripts/build-pi-harness.sh
      mix test test/eye_in_the_sky/pi/live_port_test.exs --include live_pi

  Proves `Port.command/2` from a process that is NOT the port owner works for
  our topology (SDK writes; `CLI.Port.spawn_handler` handler owns the port)
  and that the compiled harness responds over a real BEAM port.
  """

  use ExUnit.Case, async: false
  @moduletag :live_pi

  alias EyeInTheSky.Pi.CLI

  setup do
    case CLI.resolve_harness_command() do
      {:ok, _} -> :ok
      {:error, _} -> raise "harness missing — run scripts/build-pi-harness.sh"
    end
  end

  test "initialize round-trip over a real port, written from a non-owner process" do
    parent = self()
    {:ok, port, _ref} = CLI.spawn_harness(caller: parent, project_path: System.tmp_dir!())

    # Write from a DIFFERENT process than the port owner (the CLI.Port output
    # handler owns `port` after Port.connect/2). This is the exact topology
    # Pi.SDK uses: the SDK handler task writes ndjson via Port.command.
    task =
      Task.async(fn ->
        CLI.send_ndjson(port, %{id: "pi-1", type: "initialize", protocolVersion: 1})
      end)

    assert :ok = Task.await(task, 5_000)

    assert_receive {:claude_output, _ref, line}, 30_000

    assert %{"id" => "pi-1", "success" => true, "data" => %{"protocolVersion" => 1}} =
             Jason.decode!(line)

    CLI.cancel(port)
    assert_receive {:claude_exit, _ref, _code}, 10_000
  end
end
