defmodule EyeInTheSky.IAM.Builtin.WarnDestructiveSql do
  @moduledoc """
  Match (intended for `instruct` effect) Bash invocations of `psql`,
  `mysql`, `sqlite3`, or `mongosh` carrying destructive SQL (DROP,
  TRUNCATE, DELETE without WHERE) as `-c` / `--command` args or via
  heredoc.
  """

  @behaviour EyeInTheSky.IAM.BuiltinMatcher

  alias EyeInTheSky.IAM.Context
  alias EyeInTheSky.IAM.Policy

  @client_re ~r/\b(?:psql|mysql|sqlite3|mongosh|mongo)\b/
  @destructive_re ~r/\b(?:DROP\s+(?:TABLE|DATABASE|SCHEMA|INDEX)|TRUNCATE\s+TABLE|DELETE\s+FROM\s+\w+\b(?!\s+WHERE))/i

  @impl true
  def matches?(%Policy{} = _p, %Context{tool: "Bash", resource_content: cmd})
      when is_binary(cmd) do
    Regex.match?(@client_re, cmd) and Regex.match?(@destructive_re, cmd)
  end

  def matches?(_, _), do: false
end
