defmodule EyeInTheSky.IAM.Builtin.WarnSchemaAlteration do
  @moduledoc """
  Match (intended for `instruct` effect) Bash invocations of `psql`,
  `mysql`, `sqlite3`, or `mongosh` carrying DDL schema-alteration statements:
  `ALTER TABLE`, `DROP COLUMN`, `RENAME COLUMN`, `RENAME TABLE`,
  `ALTER COLUMN`, `MODIFY COLUMN`.

  Distinct from `warn_destructive_sql` which covers data destruction (DROP
  TABLE, TRUNCATE, DELETE without WHERE). Schema alterations are structural
  changes that may be irreversible or require migrations.
  """

  @behaviour EyeInTheSky.IAM.BuiltinMatcher

  alias EyeInTheSky.IAM.Context
  alias EyeInTheSky.IAM.Policy

  @client_re ~r/\b(?:psql|mysql|sqlite3|mongosh|mongo)\b/
  @alteration_re ~r/\b(?:ALTER\s+TABLE|DROP\s+COLUMN|RENAME\s+(?:COLUMN|TABLE)|ALTER\s+COLUMN|MODIFY\s+COLUMN)\b/i

  @impl true
  def matches?(%Policy{} = _p, %Context{tool: "Bash", resource_content: cmd})
      when is_binary(cmd) do
    Regex.match?(@client_re, cmd) and Regex.match?(@alteration_re, cmd)
  end

  def matches?(_, _), do: false
end
