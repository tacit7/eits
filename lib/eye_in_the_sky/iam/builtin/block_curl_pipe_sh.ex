defmodule EyeInTheSky.IAM.Builtin.BlockCurlPipeSh do
  @moduledoc """
  Deny remote-execution one-liners:

    * pipe form: `curl|wget|iwr|irm ... | sh/bash/zsh/python/...`
    * process substitution: `bash <(curl …)`, `sh <(wget …)`, `source <(curl …)`
    * eval/exec of a downloaded payload via backticks or `$(...)`: e.g.
      `eval "$(curl ...)"`, `bash -c "$(wget ...)"`.
  """

  @behaviour EyeInTheSky.IAM.BuiltinMatcher

  alias EyeInTheSky.IAM.Context
  alias EyeInTheSky.IAM.Policy

  @fetchers "curl|wget|iwr|irm|Invoke-WebRequest|Invoke-RestMethod|fetch"
  @shells "sh|bash|zsh|dash|ksh|fish|python[23]?|ruby|perl|node|pwsh|powershell"

  @pipe_re ~r/\b(?:#{@fetchers})\b[^|]*\|\s*(?:#{@shells})\b/i
  @proc_sub_re ~r/\b(?:#{@shells}|source|\.)\s+(?:-[A-Za-z]+\s+)*<\(\s*(?:#{@fetchers})\b/i
  @cmd_sub_re ~r/\b(?:#{@shells}|eval|exec|source|\.)\b[^"'`$]*["']?\$\(\s*(?:#{@fetchers})\b/i
  @backtick_re ~r/\b(?:#{@shells}|eval|exec)\b[^`]*`\s*(?:#{@fetchers})\b/i

  @impl true
  def matches?(%Policy{} = _p, %Context{tool: "Bash", resource_content: cmd})
      when is_binary(cmd) do
    Regex.match?(@pipe_re, cmd) or
      Regex.match?(@proc_sub_re, cmd) or
      Regex.match?(@cmd_sub_re, cmd) or
      Regex.match?(@backtick_re, cmd)
  end

  def matches?(_, _), do: false
end
