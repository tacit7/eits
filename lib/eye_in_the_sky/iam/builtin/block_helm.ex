defmodule EyeInTheSky.IAM.Builtin.BlockHelm do
  @moduledoc """
  Deny Bash invocations of destructive `helm` operations:
  `helm uninstall`, `helm delete` (alias), `helm rollback`.

  `helm install` and `helm upgrade` are not blocked by default — add them to
  the `"blockCommands"` condition list if needed.
  """

  @behaviour EyeInTheSky.IAM.BuiltinMatcher

  alias EyeInTheSky.IAM.Context
  alias EyeInTheSky.IAM.Policy

  @blocked ~w(uninstall delete rollback)

  @impl true
  def matches?(%Policy{} = p, %Context{tool: "Bash", resource_content: cmd})
      when is_binary(cmd) do
    if Regex.match?(~r/\bhelm\b/, cmd) do
      subcmd = extract_subcommand(cmd)
      base_blocked = effective_blocked(p)
      subcmd != nil and subcmd in base_blocked
    else
      false
    end
  end

  def matches?(_, _), do: false

  defp extract_subcommand(cmd) do
    case Regex.run(~r/\bhelm\s+(\w+)/, cmd) do
      [_, sub] -> sub
      _ -> nil
    end
  end

  defp effective_blocked(%Policy{condition: %{} = cond}) do
    extra = Map.get(cond, "blockCommands") || Map.get(cond, :blockCommands) || []
    (@blocked ++ extra) |> Enum.uniq()
  end

  defp effective_blocked(_), do: @blocked
end
