defmodule EyeInTheSkyWeb.Components.DmHelpersTest do
  use ExUnit.Case, async: true

  alias EyeInTheSkyWeb.Components.DmHelpers

  test "provider identity never presents Pi or unknown sessions as Claude" do
    assert DmHelpers.stream_provider_label(%{provider: "claude"}) == "Claude"
    assert DmHelpers.stream_provider_label(%{provider: "codex"}) == "Codex"
    assert DmHelpers.stream_provider_label(%{provider: "pi"}) == "Pi"
    assert DmHelpers.stream_provider_label(%{provider: "unrecognized"}) == "Agent"

    assert DmHelpers.provider_icon("claude") == "/images/claude.svg"
    assert DmHelpers.provider_icon("codex") == "/images/openai.svg"
    assert DmHelpers.provider_icon("pi") == "/images/logo.svg"
  end
end
