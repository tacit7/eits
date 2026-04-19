defmodule EyeInTheSky.IAM.Builtin.BlockSudo do
  @moduledoc """
  Deny Bash commands that invoke privilege escalation: `sudo`, `doas`,
  `pkexec`, Windows `runas`/`Start-Process -Verb RunAs`.

  Supports an `"allowPatterns"` condition entry — a list of regex strings
  matched against the command. A command that matches any allowPattern
  escapes this policy.
  """

  @behaviour EyeInTheSky.IAM.BuiltinMatcher

  alias EyeInTheSky.IAM.Context
  alias EyeInTheSky.IAM.Policy

  # Word-boundary escalation tokens. Case-insensitive for Windows variants.
  @escalation_re ~r/(?:(?:^|[\s;&|`(])(?:sudo|doas|pkexec)\b)|(?:\brunas\b)|(?:Start-Process\s+[^\n]*-Verb\s+RunAs)/i

  @impl true
  def matches?(%Policy{} = p, %Context{tool: "Bash", resource_content: cmd} = _ctx)
      when is_binary(cmd) do
    if Regex.match?(@escalation_re, cmd) do
      not allowed?(cmd, p)
    else
      false
    end
  end

  def matches?(_, _), do: false

  defp allowed?(cmd, %Policy{condition: %{} = cond}) do
    patterns = Map.get(cond, "allowPatterns") || Map.get(cond, :allowPatterns) || []

    Enum.any?(patterns, fn pat when is_binary(pat) ->
      case Regex.compile(pat) do
        {:ok, re} -> Regex.match?(re, cmd)
        _ -> false
      end
    end)
  end

  defp allowed?(_, _), do: false
end
