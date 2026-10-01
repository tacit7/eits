defmodule EyeInTheSky.SDK.MessageHandlerExtensionTest do
  use ExUnit.Case, async: true

  alias EyeInTheSky.SDK.MessageHandler

  defmodule FakeParser do
    # line IS the instruction, keeps tests declarative
    def parse_stream_line("protocol:" <> rest), do: {:protocol, %{"raw" => rest}}
    def parse_stream_line("error:" <> reason), do: {:error, {:fake_parse_error, reason}}
    def parse_stream_line("skip"), do: :skip
    def parse_stream_line(_), do: :skip
  end

  defmodule DefaultSDK do
    use EyeInTheSky.SDK.MessageHandler
    def handle_message(_msg, state), do: {:continue, state}
    def handle_result(_data, _state), do: :ok
  end

  defmodule PiLikeSDK do
    use EyeInTheSky.SDK.MessageHandler
    def handle_message(_msg, state), do: {:continue, state}
    def handle_result(_data, _state), do: :ok

    def handle_protocol_event(%{"raw" => "boom"}, _state), do: {:halt, :preamble_failed}

    def handle_protocol_event(data, state) do
      send(state.caller_pid, {:protocol_seen, data})
      {:continue, state}
    end

    def on_clean_exit(%{turn_end_seen: true} = state), do: {:complete, state[:session_id]}
    def on_clean_exit(_state), do: {:error, :exit_before_turn_end}
  end

  defp run_handler(module, extra_state \\ %{}) do
    parent = self()
    sdk_ref = make_ref()
    state = Map.merge(%{sdk_ref: sdk_ref, caller_pid: parent, session_id: "s1"}, extra_state)
    pid = spawn(fn -> MessageHandler.run_loop(module, state, parser: FakeParser) end)
    {sdk_ref, pid}
  end

  test "default modules keep legacy abnormal-exit reasons (Claude/Codex unchanged)" do
    {sdk_ref, pid} = run_handler(DefaultSDK)
    send(pid, {:claude_exit, :cli_ref, 137})
    assert_receive {:claude_error, ^sdk_ref, {:exit_code, 137}}, 1_000

    {sdk_ref2, pid2} = run_handler(DefaultSDK)
    send(pid2, {:claude_exit, :cli_ref, :timeout})
    assert_receive {:claude_error, ^sdk_ref2, :timeout}, 1_000
  end

  test "default modules keep exit-0-is-success behavior (Claude/Codex unchanged)" do
    {sdk_ref, pid} = run_handler(DefaultSDK)
    send(pid, {:claude_exit, :cli_ref, 0})
    assert_receive {:claude_complete, ^sdk_ref, "s1"}, 1_000
  end

  test "default modules ignore protocol events (skip-equivalent)" do
    {sdk_ref, pid} = run_handler(DefaultSDK)
    send(pid, {:claude_output, :cli_ref, "protocol:whatever"})
    send(pid, {:claude_exit, :cli_ref, 0})
    assert_receive {:claude_complete, ^sdk_ref, "s1"}, 1_000
    refute_received {:claude_error, ^sdk_ref, _}
  end

  test "handle_protocol_event receives protocol data" do
    {_sdk_ref, pid} = run_handler(PiLikeSDK, %{turn_end_seen: true})
    send(pid, {:claude_output, :cli_ref, "protocol:hello"})
    assert_receive {:protocol_seen, %{"raw" => "hello"}}, 1_000
  end

  test "handle_protocol_event halt emits claude_error and stops" do
    {sdk_ref, pid} = run_handler(PiLikeSDK, %{turn_end_seen: false})
    send(pid, {:claude_output, :cli_ref, "protocol:boom"})
    assert_receive {:claude_error, ^sdk_ref, :preamble_failed}, 1_000
    Process.sleep(50)
    refute Process.alive?(pid)
  end

  test "on_clean_exit can turn exit-0 into an error (Pi invariant)" do
    {sdk_ref, pid} = run_handler(PiLikeSDK, %{turn_end_seen: false})
    send(pid, {:claude_exit, :cli_ref, 0})
    assert_receive {:claude_error, ^sdk_ref, :exit_before_turn_end}, 1_000
  end

  test "on_clean_exit completes when turn_end was seen" do
    {sdk_ref, pid} = run_handler(PiLikeSDK, %{turn_end_seen: true})
    send(pid, {:claude_exit, :cli_ref, 0})
    assert_receive {:claude_complete, ^sdk_ref, "s1"}, 1_000
  end

  test "default on_stream_error preserves parser {:error, reason} unchanged (Claude/Codex)" do
    {sdk_ref, pid} = run_handler(DefaultSDK)
    send(pid, {:claude_output, :cli_ref, "error:bad_json"})
    assert_receive {:claude_error, ^sdk_ref, {:fake_parse_error, "bad_json"}}, 1_000
    # Loop exits after sending claude_error; wait briefly for stop_and_unregister.
    wait_for_death(pid, 500)
    refute Process.alive?(pid)
  end

  defp wait_for_death(pid, timeout_ms) do
    deadline = System.monotonic_time(:millisecond) + timeout_ms

    Stream.repeatedly(fn ->
      if Process.alive?(pid) do
        Process.sleep(10)
        :alive
      else
        :dead
      end
    end)
    |> Enum.find(fn s ->
      s == :dead or System.monotonic_time(:millisecond) >= deadline
    end)
  end

  test "default on_stream_error preserves handle_protocol_event {:halt, reason} unchanged" do
    {sdk_ref, pid} = run_handler(PiLikeSDK, %{turn_end_seen: false})
    send(pid, {:claude_output, :cli_ref, "protocol:boom"})
    # PiLikeSDK.on_stream_error is the default (returns reason unchanged), so
    # :preamble_failed reaches the caller as-is.
    assert_receive {:claude_error, ^sdk_ref, :preamble_failed}, 1_000
  end
end
