defmodule EyeInTheSky.IAM.Builtin.ProtectEnvVars do
  @moduledoc """
  Deny Bash commands that dump or export sensitive environment variables:
  bare `env`, `printenv`, `export`, or `echo $VAR` style reads of sensitive
  names.

  Supports `"sensitiveVarPattern"` — a regex (as a string) that matches a
  variable name considered sensitive. Default covers common secret/token
  patterns.
  """

  @behaviour EyeInTheSky.IAM.BuiltinMatcher

  alias EyeInTheSky.IAM.Context
  alias EyeInTheSky.IAM.Policy

  @default_sensitive_re ~r/(?:SECRET|TOKEN|KEY|PASSWORD|PASSWD|CREDENTIAL|API[_-]?KEY|AUTH)/i

  @dump_re ~r/(?:^|[\s;&|`(])(?:env|printenv|export)\b/

  @impl true
  def matches?(%Policy{} = p, %Context{tool: "Bash", resource_content: cmd})
      when is_binary(cmd) do
    sensitive = sensitive_pattern(p)

    Regex.match?(@dump_re, cmd) or echoes_sensitive?(cmd, sensitive)
  end

  def matches?(_, _), do: false

  defp echoes_sensitive?(cmd, re) do
    Regex.scan(~r/\$\{?([A-Z_][A-Z0-9_]*)\}?/, cmd)
    |> Enum.any?(fn [_, var] -> Regex.match?(re, var) end)
  end

  defp sensitive_pattern(%Policy{condition: %{} = cond}) do
    case Map.get(cond, "sensitiveVarPattern") || Map.get(cond, :sensitiveVarPattern) do
      nil ->
        @default_sensitive_re

      pat when is_binary(pat) ->
        case Regex.compile(pat, "i") do
          {:ok, re} -> re
          _ -> @default_sensitive_re
        end
    end
  end

  defp sensitive_pattern(_), do: @default_sensitive_re
end
