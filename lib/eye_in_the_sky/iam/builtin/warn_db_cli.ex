defmodule EyeInTheSky.IAM.Builtin.WarnDbCli do
  @moduledoc """
  Match any Bash invocation of a database CLI client.

  Covered clients: psql, sqlite3, mysql, mysqladmin, mysqlcheck,
  mariadb, mariadb-admin, cockroach, mongosh, mongo, redis-cli,
  redis-server, cqlsh (Cassandra), ysqlsh/ycqlsh (YugabyteDB),
  influx, dbeaver, pgcli, mycli, litecli.

  Matches the bare binary name at word boundary — captures both
  direct invocations (`psql -U ...`) and path-prefixed ones
  (`/usr/bin/psql ...`).

  Intended for `instruct` or `deny` effect. Common use cases:
  - Warn agents before running ad-hoc queries on production databases
  - Block direct DB access entirely for restricted agent types
  - Audit which agents are reaching outside the application layer
  """

  @behaviour EyeInTheSky.IAM.BuiltinMatcher

  alias EyeInTheSky.IAM.Context
  alias EyeInTheSky.IAM.Policy

  @db_cli_re ~r/\b(?:psql|sqlite3|mysql|mysqladmin|mysqlcheck|mariadb(?:-admin)?|cockroach|mongosh?|redis-(?:cli|server)|cqlsh|y(?:sql|cql)sh|influx|pgcli|mycli|litecli)\b/

  @impl true
  def matches?(%Policy{} = _p, %Context{tool: "Bash", resource_content: cmd})
      when is_binary(cmd) do
    Regex.match?(@db_cli_re, cmd)
  end

  def matches?(_, _), do: false
end
