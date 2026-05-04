defmodule EyeInTheSky.IAM.Builtin.BlockGcloud do
  @moduledoc """
  Deny Bash invocations of destructive `gcloud` operations:
  `compute instances delete`, `projects delete`, `sql instances delete`,
  `container clusters delete`, `functions delete`, `run services delete`.
  """

  @behaviour EyeInTheSky.IAM.BuiltinMatcher

  alias EyeInTheSky.IAM.Context
  alias EyeInTheSky.IAM.Policy

  @destructive_re ~r/\bgcloud\s+(?:
    compute\s+instances\s+delete|
    projects\s+delete|
    sql\s+instances\s+delete|
    container\s+clusters\s+delete|
    functions\s+delete|
    run\s+services\s+delete
  )/xi

  @impl true
  def matches?(%Policy{} = _p, %Context{tool: "Bash", resource_content: cmd})
      when is_binary(cmd) do
    Regex.match?(@destructive_re, cmd)
  end

  def matches?(_, _), do: false
end
