defmodule EyeInTheSky.IAM.Builtin.BlockCurlPipeSh do
  @moduledoc """
  Deny `curl|wget|iwr|irm ... | sh/bash/zsh/python` style one-shot remote
  execution pipelines.
  """

  @behaviour EyeInTheSky.IAM.BuiltinMatcher

  alias EyeInTheSky.IAM.Context
  alias EyeInTheSky.IAM.Policy

  @pipe_re ~r/\b(?:curl|wget|iwr|irm|Invoke-WebRequest|Invoke-RestMethod)\b[^|]*\|\s*(?:sh|bash|zsh|dash|ksh|fish|python[23]?|ruby|perl|node|pwsh|powershell)\b/i

  @impl true
  def matches?(%Policy{} = _p, %Context{tool: "Bash", resource_content: cmd})
      when is_binary(cmd) do
    Regex.match?(@pipe_re, cmd)
  end

  def matches?(_, _), do: false
end
