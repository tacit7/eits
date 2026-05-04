defmodule EyeInTheSky.IAM.Builtin.WarnLargeFileWrite do
  @moduledoc """
  Match (intended for `instruct` effect) Write/Edit/MultiEdit tool calls
  whose content exceeds a configurable byte threshold.

  Writing very large files is often unintentional — agents generating fixture
  data, embedding binaries, or producing runaway outputs. The default
  threshold is 100 KB. Override via the `"maxBytes"` condition entry.

  Does not fire on Bash — the resource_content for Bash is the command
  string, not the file being written.
  """

  @behaviour EyeInTheSky.IAM.BuiltinMatcher

  alias EyeInTheSky.IAM.Context
  alias EyeInTheSky.IAM.Policy

  @default_max_bytes 100_000

  @impl true
  def matches?(%Policy{} = p, %Context{tool: tool, resource_content: content})
      when tool in ["Write", "Edit", "MultiEdit"] and is_binary(content) do
    max = max_bytes(p)
    byte_size(content) > max
  end

  def matches?(_, _), do: false

  defp max_bytes(%Policy{condition: %{} = cond}) do
    case Map.get(cond, "maxBytes") || Map.get(cond, :maxBytes) do
      n when is_integer(n) and n > 0 -> n
      _ -> @default_max_bytes
    end
  end

  defp max_bytes(_), do: @default_max_bytes
end
