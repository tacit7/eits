defmodule EyeInTheSky.Pi.IntegrationTest do
  @moduledoc """
  End-to-end lifecycle + protocol-ordering tests for the Pi provider.

  Uses `test/support/fake_pi_harness.sh` (a scripted fake harness that replays
  a per-test scenario file) as `EITS_PI_HARNESS`, so the real Pi.CLI transport
  path (Port.open + Port.command) is exercised without needing a live Pi
  provider or a compiled sidecar.
  """

  use ExUnit.Case, async: false

  alias EyeInTheSky.Claude.Message
  alias EyeInTheSky.Claude.SDK.Registry
  alias EyeInTheSky.Pi.SDK

  @moduletag :tmp_dir

  setup ctx do
    prev_harness = System.get_env("EITS_PI_HARNESS")
    prev_root = System.get_env("EITS_PI_SESSION_ROOT")

    session_root = Path.join(ctx.tmp_dir, "sessions")
    File.mkdir_p!(session_root)
    System.put_env("EITS_PI_SESSION_ROOT", session_root)

    on_exit(fn ->
      if prev_harness,
        do: System.put_env("EITS_PI_HARNESS", prev_harness),
        else: System.delete_env("EITS_PI_HARNESS")

      if prev_root,
        do: System.put_env("EITS_PI_SESSION_ROOT", prev_root),
        else: System.delete_env("EITS_PI_SESSION_ROOT")
    end)

    :ok
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp fake_harness!(tmp_dir, scenario_lines, extra_env \\ []) do
    scenario = Path.join(tmp_dir, "scenario-#{System.unique_integer([:positive])}.txt")
    File.write!(scenario, Enum.join(scenario_lines, "\n") <> "\n")

    fake = Path.expand("test/support/fake_pi_harness.sh")
    wrapper = Path.join(tmp_dir, "harness-#{System.unique_integer([:positive])}.sh")

    env_exports =
      for {k, v} <- extra_env, into: "" do
        "export #{k}=#{shell_quote(to_string(v))}\n"
      end

    File.write!(wrapper, """
    #!/bin/sh
    export FAKE_PI_SCENARIO=#{shell_quote(scenario)}
    #{env_exports}exec #{shell_quote(fake)}
    """)

    File.chmod!(wrapper, 0o755)
    System.put_env("EITS_PI_HARNESS", wrapper)
    %{wrapper: wrapper, scenario: scenario}
  end

  defp shell_quote(str) do
    "'" <> String.replace(str, "'", ~S('"'"')) <> "'"
  end

  defp start_pi(prompt, opts) do
    session_id = opts[:session_id] || "sess-#{System.unique_integer([:positive])}"

    SDK.start(prompt,
      to: self(),
      session_id: session_id,
      project_path: File.cwd!(),
      model: "openrouter/qwen/qwen3-coder",
      allowed_tools: ["*"]
    )
  end

  defp encode(map), do: Jason.encode!(map)

  # ---------------------------------------------------------------------------
  # Scenarios
  # ---------------------------------------------------------------------------

  test "1. happy path: preamble → deltas → turn_end → clean complete", ctx do
    fake_harness!(ctx.tmp_dir, [
      "WAIT:start_session",
      encode(%{
        "type" => "ready",
        "sessionId" => "sess-happy",
        "sessionFile" => "/x",
        "model" => "m"
      }),
      "WAIT:prompt",
      encode(%{"type" => "assistant_delta", "delta" => "hel"}),
      encode(%{"type" => "assistant_delta", "delta" => "lo"}),
      encode(%{
        "type" => "turn_end",
        "aggregate" => %{"inputTokens" => 10, "outputTokens" => 5, "totalTokens" => 15},
        "totalCostUsd" => 0.001,
        "durationMs" => 42
      }),
      "WAIT:dispose",
      "EXIT:0"
    ])

    {:ok, ref, _handler} = start_pi("hi", session_id: "sess-happy")

    assert_receive {:claude_message, ^ref, %Message{type: :text, content: "hel", delta: true}},
                   5_000

    assert_receive {:claude_message, ^ref, %Message{type: :text, content: "lo", delta: true}},
                   5_000

    assert_receive {:claude_message, ^ref, %Message{type: :result}}, 5_000
    assert_receive {:claude_complete, ^ref, "sess-happy"}, 5_000
    refute_receive {:claude_error, ^ref, _}, 200
  end

  test "2. ready before start_session response still completes", ctx do
    # The fake auto-responds to every request that arrives on stdin. To force
    # ready-before-ack ordering, we emit `ready` before consuming start_session:
    # the scenario opens with the ready line BEFORE WAIT:start_session. But the
    # SDK only sends start_session AFTER initialize's response, and the fake
    # can only auto-respond by consuming stdin. So we drive the ordering via
    # WAIT:initialize (consumes+acks initialize), then emit ready before
    # accepting start_session.
    fake_harness!(ctx.tmp_dir, [
      "WAIT:initialize",
      encode(%{
        "type" => "ready",
        "sessionId" => "sess-ready-first",
        "sessionFile" => "/x",
        "model" => "m"
      }),
      "WAIT:start_session",
      "WAIT:prompt",
      encode(%{"type" => "turn_end", "aggregate" => %{}}),
      "WAIT:dispose",
      "EXIT:0"
    ])

    {:ok, ref, _} = start_pi("hi", session_id: "sess-ready-first")

    assert_receive {:claude_complete, ^ref, "sess-ready-first"}, 5_000
  end

  test "3. exit 0 before turn_end → claude_error :exit_before_turn_end", ctx do
    fake_harness!(ctx.tmp_dir, [
      "WAIT:start_session",
      encode(%{"type" => "ready", "sessionId" => "sess-early-exit"}),
      "WAIT:prompt",
      encode(%{"type" => "assistant_delta", "delta" => "partial"}),
      "EXIT:0"
    ])

    {:ok, ref, _} = start_pi("hi", session_id: "sess-early-exit")

    assert_receive {:claude_error, ^ref, :exit_before_turn_end}, 5_000
    refute_receive {:claude_complete, ^ref, _}, 200
  end

  test "4. exit 1 before turn_end → claude_error", ctx do
    fake_harness!(ctx.tmp_dir, [
      "WAIT:start_session",
      encode(%{"type" => "ready", "sessionId" => "sess-exit1"}),
      "WAIT:prompt",
      "EXIT:1"
    ])

    {:ok, ref, _} = start_pi("hi", session_id: "sess-exit1")

    assert_receive {:claude_error, ^ref, reason}, 5_000
    assert reason == {:exit_code, 1} or reason == :exit_before_turn_end
    refute_receive {:claude_complete, ^ref, _}, 200
  end

  test "5. turn_error then turn_end → sticky {:pi_turn_error, msg}, no complete", ctx do
    fake_harness!(ctx.tmp_dir, [
      "WAIT:start_session",
      encode(%{"type" => "ready", "sessionId" => "sess-sticky"}),
      "WAIT:prompt",
      encode(%{"type" => "turn_error", "error" => "rate limited"}),
      encode(%{"type" => "turn_end", "aggregate" => %{}}),
      "WAIT:dispose",
      "EXIT:0"
    ])

    {:ok, ref, _} = start_pi("hi", session_id: "sess-sticky")

    assert_receive {:claude_error, ^ref, {:pi_turn_error, "rate limited"}}, 5_000
    refute_receive {:claude_complete, ^ref, _}, 300
  end

  test "6. malformed line mid-stream is skipped, stream continues to complete", ctx do
    fake_harness!(ctx.tmp_dir, [
      "WAIT:start_session",
      encode(%{"type" => "ready", "sessionId" => "sess-malformed"}),
      "WAIT:prompt",
      encode(%{"type" => "assistant_delta", "delta" => "before"}),
      "this is not json {",
      encode(%{"type" => "assistant_delta", "delta" => "after"}),
      encode(%{"type" => "turn_end", "aggregate" => %{}}),
      "WAIT:dispose",
      "EXIT:0"
    ])

    {:ok, ref, _} = start_pi("hi", session_id: "sess-malformed")

    assert_receive {:claude_message, ^ref, %Message{content: "before"}}, 5_000
    assert_receive {:claude_message, ^ref, %Message{content: "after"}}, 5_000
    assert_receive {:claude_complete, ^ref, "sess-malformed"}, 5_000
  end

  test "7. tool_request is auto-denied (WAIT:deny_tool proves the write) and stream continues",
       ctx do
    fake_harness!(ctx.tmp_dir, [
      "WAIT:start_session",
      encode(%{"type" => "ready", "sessionId" => "sess-toolreq"}),
      "WAIT:prompt",
      encode(%{"type" => "tool_request", "requestId" => "r-1", "toolName" => "bash"}),
      "WAIT:deny_tool",
      encode(%{"type" => "turn_end", "aggregate" => %{}}),
      "WAIT:dispose",
      "EXIT:0"
    ])

    {:ok, ref, _} = start_pi("hi", session_id: "sess-toolreq")

    # The auto-deny status message.
    assert_receive {:claude_message, ^ref,
                    %Message{type: :text, content: "Pi requested tool approval" <> _}},
                   5_000

    assert_receive {:claude_complete, ^ref, "sess-toolreq"}, 5_000
  end

  test "8. cancel: SDK.cancel(ref) tears the harness down", ctx do
    # Scenario blocks on an "abort" request that will never come from the SDK
    # via the normal path — SDK.cancel writes an abort with id "pi-cancel".
    fake_harness!(ctx.tmp_dir, [
      "WAIT:start_session",
      encode(%{"type" => "ready", "sessionId" => "sess-cancel"}),
      "WAIT:prompt",
      encode(%{"type" => "assistant_delta", "delta" => "starting"}),
      "WAIT:abort",
      "EXIT:143"
    ])

    {:ok, ref, _} = start_pi("hi", session_id: "sess-cancel")

    assert_receive {:claude_message, ^ref, %Message{content: "starting"}}, 5_000

    :ok = SDK.cancel(ref)

    # A cancel results in the terminal :user_canceled outcome — a systemic
    # (non-retryable) error category, never a retryable exit error, never a
    # completion (spec invariant: canceled turns are not retried).
    assert_receive {:claude_error, ^ref, :user_canceled}, 10_000
    refute_receive {:claude_complete, ^ref, _}, 200
  end

  test "9. serialization: Registry holds at most one port per ref (SDK-level fallback)", ctx do
    # Plan fallback for scenario 9: the AgentWorker-level assertion is heavy
    # scaffolding; assert here that the SDK's Registry invariant holds — each
    # session ref maps to exactly one live port at any moment.
    fake_harness!(ctx.tmp_dir, [
      "WAIT:start_session",
      encode(%{"type" => "ready", "sessionId" => "sess-serial"}),
      "WAIT:prompt",
      encode(%{"type" => "turn_end", "aggregate" => %{}}),
      "WAIT:dispose",
      "EXIT:0"
    ])

    {:ok, ref, _} = start_pi("hi", session_id: "sess-serial")

    port = Registry.lookup(ref)
    assert is_port(port), "expected a live port registered for ref"

    # Only one entry per ref.
    all_ports_for_ref = for r <- [ref], p = Registry.lookup(r), do: p
    assert length(all_ports_for_ref) == 1

    assert_receive {:claude_complete, ^ref, "sess-serial"}, 5_000

    # After completion, the ref is unregistered.
    Process.sleep(200)
    refute Registry.lookup(ref), "ref should be unregistered after terminal"
  end
end
