defmodule EyeInTheSky.IAM.Builtin.BlockKubectl do
  @moduledoc """
  Deny Bash invocations of destructive `kubectl` operations:
  `delete`, `drain`, `cordon`, `exec` (shell into pod), `replace --force`,
  and `rollout restart`.

  Non-destructive reads (`get`, `describe`, `logs`, `top`, `explain`) are
  not blocked. Use the `"allowVerbs"` condition list to whitelist additional
  verbs.
  """

  @behaviour EyeInTheSky.IAM.BuiltinMatcher

  alias EyeInTheSky.IAM.Context
  alias EyeInTheSky.IAM.Policy

  @destructive_verbs ~w(delete drain cordon exec replace rollout)

  @impl true
  def matches?(%Policy{} = p, %Context{tool: "Bash", resource_content: cmd})
      when is_binary(cmd) do
    if Regex.match?(~r/\bkubectl\b/, cmd) do
      verb = extract_verb(cmd)
      verb != nil and verb in effective_blocked_verbs(p)
    else
      false
    end
  end

  def matches?(_, _), do: false

  defp extract_verb(cmd) do
    case Regex.run(~r/\bkubectl\s+(\w+)/, cmd) do
      [_, verb] -> verb
      _ -> nil
    end
  end

  defp effective_blocked_verbs(%Policy{condition: %{} = cond}) do
    allowed = Map.get(cond, "allowVerbs") || Map.get(cond, :allowVerbs) || []
    @destructive_verbs -- allowed
  end

  defp effective_blocked_verbs(_), do: @destructive_verbs
end
