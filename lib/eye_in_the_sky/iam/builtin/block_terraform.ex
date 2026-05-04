defmodule EyeInTheSky.IAM.Builtin.BlockTerraform do
  @moduledoc """
  Deny Bash invocations of `terraform destroy` and `terraform apply`.

  `terraform apply` with `-auto-approve` is especially dangerous —
  no confirmation prompt. Both operations modify live infrastructure.

  Use the `"allowCommands"` condition list (exact subcommand strings) to
  permit specific commands (e.g. `["plan"]`).
  """

  @behaviour EyeInTheSky.IAM.BuiltinMatcher

  alias EyeInTheSky.IAM.Context
  alias EyeInTheSky.IAM.Policy

  @blocked ~w(destroy apply)

  @impl true
  def matches?(%Policy{} = p, %Context{tool: "Bash", resource_content: cmd})
      when is_binary(cmd) do
    if Regex.match?(~r/\bterraform\b/, cmd) do
      subcmd = extract_subcommand(cmd)
      subcmd != nil and subcmd in effective_blocked(p)
    else
      false
    end
  end

  def matches?(_, _), do: false

  defp extract_subcommand(cmd) do
    case Regex.run(~r/\bterraform\s+(\w+)/, cmd) do
      [_, sub] -> sub
      _ -> nil
    end
  end

  defp effective_blocked(%Policy{condition: %{} = cond}) do
    allowed = Map.get(cond, "allowCommands") || Map.get(cond, :allowCommands) || []
    @blocked -- allowed
  end

  defp effective_blocked(_), do: @blocked
end
