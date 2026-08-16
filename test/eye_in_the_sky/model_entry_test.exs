defmodule EyeInTheSky.ModelEntryTest do
  use ExUnit.Case, async: true

  alias EyeInTheSky.ModelEntry

  test "struct has the documented fields with correct defaults" do
    entry = %ModelEntry{
      provider: "claude",
      slug: "claude-opus-4-8",
      label: "Opus 4.8",
      group: "Claude Code"
    }

    assert entry.sub_provider == nil
    assert entry.premium? == false
    assert entry.legacy? == false
    assert entry.default? == false
  end

  test "all fields can be set explicitly" do
    entry = %ModelEntry{
      provider: "pi",
      slug: "ollama-lan/qwen3.6:27b",
      label: "ollama-lan/qwen3.6:27b",
      group: "Ollama (LAN)",
      sub_provider: "ollama-lan",
      premium?: false,
      legacy?: false,
      default?: false
    }

    assert entry.provider == "pi"
    assert entry.sub_provider == "ollama-lan"
  end
end
