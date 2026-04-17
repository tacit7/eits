defmodule EyeInTheSky.IAM.Builtin.BlockReadOutsideCwd do
  @moduledoc """
  Deny Read/Glob/Grep and Bash file reads whose resolved absolute path
  falls outside the project's cwd (i.e., `Context.project_path`).

  Uses `Path.expand/1` and a prefix check. Paths that cannot be resolved
  (no `project_path`) do not match — fail closed in the sense of "does
  not match," not "deny."
  """

  @behaviour EyeInTheSky.IAM.BuiltinMatcher

  alias EyeInTheSky.IAM.Context
  alias EyeInTheSky.IAM.Policy

  @impl true
  def matches?(%Policy{} = _p, %Context{project_path: cwd} = ctx)
      when is_binary(cwd) do
    case extract_path(ctx) do
      nil -> false
      path -> outside?(path, cwd)
    end
  end

  def matches?(_, _), do: false

  defp extract_path(%Context{tool: tool, resource_path: path})
       when tool in ~w(Read Glob Grep) and is_binary(path),
       do: path

  defp extract_path(%Context{tool: "Bash", resource_content: cmd}) when is_binary(cmd) do
    # naive extraction: first absolute path argument
    case Regex.run(~r/(?:^|\s)(\/[^\s;&|`<>]+)/, cmd) do
      [_, p] -> p
      _ -> nil
    end
  end

  defp extract_path(_), do: nil

  defp outside?(path, cwd) do
    abs = Path.expand(path, cwd)
    root = Path.expand(cwd)
    not (abs == root or String.starts_with?(abs, root <> "/"))
  end
end
