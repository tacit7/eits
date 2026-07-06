defmodule EyeInTheSky.Claude.ProviderStrategyPiTest do
  use ExUnit.Case, async: true

  alias EyeInTheSky.Claude.ProviderStrategy

  test "for_provider dispatches pi" do
    assert ProviderStrategy.for_provider("pi") == EyeInTheSky.Claude.ProviderStrategy.Pi
  end

  test "for_provider default unchanged" do
    assert ProviderStrategy.for_provider("claude") == EyeInTheSky.Claude.ProviderStrategy.Claude
    assert ProviderStrategy.for_provider("codex") == EyeInTheSky.Claude.ProviderStrategy.Codex
  end

  test "pi strategy builds opts with session dir keyed by conversation id and bypass tools" do
    state = %{
      provider_conversation_id: "conv-uuid-1",
      project_path: "/tmp",
      eits_session_uuid: "sess-uuid",
      session_id: 42,
      agent_id: 7,
      project_id: 1
    }

    opts =
      EyeInTheSky.Claude.ProviderStrategy.Pi.build_opts(state, %{model: "openrouter/qwen/qwen3-coder"})

    assert opts[:session_id] == "conv-uuid-1"
    assert opts[:model] == "openrouter/qwen/qwen3-coder"
    assert opts[:allowed_tools] == ["*"]
    assert opts[:project_path] == "/tmp"
    assert is_binary(opts[:turn_id])
  end
end
