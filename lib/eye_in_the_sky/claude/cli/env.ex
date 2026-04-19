defmodule EyeInTheSky.Claude.CLI.Env do
  @moduledoc """
  Builds the OS environment for spawned Claude CLI processes.

  Strips blocked vars, sanitizes PATH using explicit poisoned-entry rules,
  and injects EITS-specific vars from opts.

  ## Poisoned PATH entry rules
  An entry is stripped if it:
  - is empty or whitespace-only
  - contains `_build/prod/rel` (release bin or ERTS bin under a release)
  - contains `/erts-` (embedded ERTS from any build directory)
  """

  @blocked_vars ~w[
    CLAUDECODE
    CLAUDE_CODE_ENTRYPOINT
    ANTHROPIC_API_KEY
    BINDIR
    ROOTDIR
    EMU
  ]

  @blocked_prefixes ["RELEASE_"]

  @doc """
  Builds the environment variable list for a spawned Claude process.
  Delegates to `build_from_map/2` with `System.get_env()`.
  """
  @spec build(keyword()) :: [{charlist(), charlist()}]
  def build(opts), do: build_from_map(System.get_env(), opts)

  @doc """
  Testable variant. Accepts an explicit env map instead of `System.get_env()`.
  """
  @spec build_from_map(map(), keyword()) :: [{charlist(), charlist()}]
  def build_from_map(system_env, opts) do
    base_env =
      for {key, value} <- system_env,
          value != "",
          not blocked_key?(key) do
        sanitized = sanitize_value(key, value)
        {String.to_charlist(key), String.to_charlist(sanitized)}
      end

    env = [{~c"CI", ~c"true"}, {~c"TERM", ~c"dumb"} | base_env]

    env = maybe_add_env(env, "EITS_SESSION_ID", opts[:eits_session_id])
    env = maybe_add_env(env, "EITS_AGENT_ID", opts[:eits_agent_id])
    env = maybe_add_env(env, "EITS_AGENT_UUID", opts[:eits_agent_uuid])
    env = maybe_add_env(env, "EITS_PROJECT_ID", opts[:eits_project_id])
    env = maybe_add_env(env, "EITS_WORKFLOW", opts[:eits_workflow] || "1")
    maybe_add_env(env, "CLAUDE_CODE_EFFORT_LEVEL", opts[:effort_level])
  end

  defp blocked_key?(key) do
    key in @blocked_vars or
      Enum.any?(@blocked_prefixes, &String.starts_with?(key, &1))
  end

  defp sanitize_value("PATH", value), do: sanitize_path(value)
  defp sanitize_value(_key, value), do: value

  # Unix-only: PATH entries are colon-separated. This project runs on macOS/Linux only.
  defp sanitize_path(path) do
    path
    |> String.split(":")
    |> Enum.reject(&poisoned_path_entry?/1)
    |> Enum.join(":")
  end

  defp poisoned_path_entry?(entry) do
    trimmed = String.trim(entry)

    trimmed == "" or
      String.contains?(trimmed, "_build/prod/rel") or
      String.contains?(trimmed, "/erts-")
  end

  defp maybe_add_env(env, key, value) do
    EyeInTheSky.CLI.Port.maybe_add_env(env, key, value)
  end
end
