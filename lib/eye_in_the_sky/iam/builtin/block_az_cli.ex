defmodule EyeInTheSky.IAM.Builtin.BlockAzCli do
  @moduledoc """
  Deny Bash invocations of destructive Azure CLI (`az`) operations:
  `az vm delete`, `az group delete`, `az sql db delete`,
  `az aks delete`, `az webapp delete`, `az functionapp delete`.
  """

  @behaviour EyeInTheSky.IAM.BuiltinMatcher

  alias EyeInTheSky.IAM.Context
  alias EyeInTheSky.IAM.Policy

  @destructive_re ~r/\baz\s+(?:
    vm\s+delete|
    group\s+delete|
    sql\s+(?:db|server)\s+delete|
    aks\s+delete|
    webapp\s+delete|
    functionapp\s+delete
  )/xi

  @impl true
  def matches?(%Policy{} = _p, %Context{tool: "Bash", resource_content: cmd})
      when is_binary(cmd) do
    Regex.match?(@destructive_re, cmd)
  end

  def matches?(_, _), do: false
end
