defmodule EyeInTheSky.IAM.Builtin.SanitizeConnectionStrings do
  @moduledoc """
  Match (intended for `instruct` effect) PostToolUse responses that contain
  database or service connection strings with embedded credentials.

  Detected patterns:
    * `postgresql://user:password@host`
    * `mysql://user:password@host`
    * `mongodb://user:password@host` / `mongodb+srv://...`
    * `redis://:password@host`
    * `amqp://user:password@host` (RabbitMQ)
    * `sqlserver://user:password@host` / `mssql://...`

  Only fires when the URI contains a non-empty password segment
  (i.e. `://...:<password>@`). URIs with no credentials are ignored.

  Intended for `PostToolUse` events — catches credentials leaking into
  tool output that the agent would then see and potentially log or repeat.
  """

  @behaviour EyeInTheSky.IAM.BuiltinMatcher

  alias EyeInTheSky.IAM.Context
  alias EyeInTheSky.IAM.Policy

  # Matches scheme://[user:]password@host — requires a non-empty password before @
  @conn_re ~r/(?:postgresql|postgres|mysql|mongodb(?:\+srv)?|redis|amqp|amqps|sqlserver|mssql):\/\/(?:[^:@\/\s]+:)?[^@\/\s]{1,}@/i

  @impl true
  def matches?(%Policy{} = _p, %Context{tool_response: response})
      when is_binary(response) do
    Regex.match?(@conn_re, response)
  end

  def matches?(_, _), do: false
end
