defmodule EyeInTheSky.Claude.CLI.Env do
  @moduledoc """
  Builds the OS environment for spawned Claude CLI processes.

  Extracted from `EyeInTheSky.Claude.CLI` to isolate environment construction
  from the rest of the CLI spawning logic. `CLI` calls `build/1` from its
  private `build_env/1` function; all other callers should continue to use
  the `CLI` public API.
  """

  # Vars that must be stripped so spawned Claude processes don't inherit
  # session-level state or bypass Max plan OAuth with a potentially empty key.
  @blocked_vars ~w[CLAUDECODE CLAUDE_CODE_ENTRYPOINT ANTHROPIC_API_KEY]

  @doc """
  Builds the environment variable list for a spawned Claude process.

  Strips blocked vars, passes through the rest of the system environment,
  and injects EITS-specific vars from `opts`.
  """
  @spec build(keyword()) :: [{charlist(), charlist()}]
  def build(opts) do
    base_env =
      for {key, value} <- System.get_env(),
          value != "",
          key not in @blocked_vars do
        {String.to_charlist(key), String.to_charlist(value)}
      end

    env = [
      {~c"CI", ~c"true"},
      {~c"TERM", ~c"dumb"}
      | base_env
    ]

    env = maybe_add_env(env, "EITS_SESSION_ID", opts[:eits_session_id])
    env = maybe_add_env(env, "EITS_AGENT_ID", opts[:eits_agent_id])
    env = maybe_add_env(env, "EITS_WORKFLOW", opts[:eits_workflow] || "1")
    maybe_add_env(env, "CLAUDE_CODE_EFFORT_LEVEL", opts[:effort_level])
  end

  defp maybe_add_env(env, key, value) do
    EyeInTheSky.CLI.Port.maybe_add_env(env, key, value)
  end
end
