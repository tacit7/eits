defmodule EyeInTheSky.IAM.Builtin.BlockEnvFiles do
  @moduledoc """
  Deny any access to `.env`, `.env.*`, or files matching an extended
  pattern via Read/Write/Edit/Glob, and Bash commands that `cat`/`less`/
  `head`/`tail` a `.env` file.

  Supports `"allowFiles"` — list of exact paths that escape this policy
  (e.g. `.env.example`).
  """

  @behaviour EyeInTheSky.IAM.BuiltinMatcher

  alias EyeInTheSky.IAM.Context
  alias EyeInTheSky.IAM.Policy

  @env_path_re ~r/(?:^|\/)\.env(?:\.[A-Za-z0-9._-]+)?$/
  @env_bash_re ~r/\b(?:cat|less|more|head|tail|bat)\s+[^|;&]*\.env(?:\.[A-Za-z0-9._-]+)?(?:\s|$)/

  @impl true
  def matches?(%Policy{} = p, %Context{} = ctx) do
    hit? =
      cond do
        ctx.tool in ~w(Read Write Edit Glob) and is_binary(ctx.resource_path) ->
          Regex.match?(@env_path_re, ctx.resource_path)

        ctx.tool == "Bash" and is_binary(ctx.resource_content) ->
          Regex.match?(@env_bash_re, ctx.resource_content)

        true ->
          false
      end

    hit? and not allowed?(ctx, p)
  end

  defp allowed?(%Context{resource_path: path}, %Policy{condition: %{} = cond})
       when is_binary(path) do
    files = Map.get(cond, "allowFiles") || Map.get(cond, :allowFiles) || []
    Enum.any?(files, &(&1 == path or String.ends_with?(path, &1)))
  end

  defp allowed?(_, _), do: false
end
