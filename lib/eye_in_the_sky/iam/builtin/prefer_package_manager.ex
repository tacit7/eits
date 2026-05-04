defmodule EyeInTheSky.IAM.Builtin.PreferPackageManager do
  @moduledoc """
  Warns (instructs) when a Bash command uses a package manager that differs
  from the project's configured preferred one.

  Requires a `"packageManager"` condition key set to `"npm"`, `"yarn"`,
  `"pnpm"`, or `"bun"`. Without this condition the matcher is a no-op —
  the policy is opt-in.

  Detects the manager from the first command token or from runner prefixes
  (`npx`, `yarn`, `pnpm`, `bunx`). Only install/add/remove/run/exec
  sub-commands trigger a match.
  """

  @behaviour EyeInTheSky.IAM.BuiltinMatcher

  alias EyeInTheSky.IAM.Context
  alias EyeInTheSky.IAM.Policy

  @managers ~w(npm yarn pnpm bun)

  # Sub-commands that constitute package-manager usage worth warning about.
  @install_verbs ~w(install add remove uninstall run exec ci)

  @impl true
  def matches?(
        %Policy{condition: %{"packageManager" => preferred}},
        %Context{tool: "Bash", resource_content: cmd}
      )
      when is_binary(preferred) and is_binary(cmd) do
    case detect_manager_with_runner(cmd) do
      nil -> false
      {^preferred, _runner?} -> false
      {_other, true} -> true
      {_other, false} -> package_manager_command?(cmd)
    end
  end

  def matches?(_, _), do: false

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  # Returns {manager, runner?} or nil.
  # runner? is true for npx/bunx — those are always a "run package" action.
  defp detect_manager_with_runner(cmd) do
    # Strip leading env assignments like `NODE_ENV=prod npm install`
    tokens = cmd |> String.split() |> drop_env_assignments()

    case tokens do
      [bin | _] when bin in @managers -> {bin, false}
      # npx delegates to npm; bunx delegates to bun — inherently an exec action
      ["npx" | _] -> {"npm", true}
      ["bunx" | _] -> {"bun", true}
      _ -> nil
    end
  end

  defp drop_env_assignments(["" | rest]), do: drop_env_assignments(rest)

  defp drop_env_assignments([token | rest]) do
    if Regex.match?(~r/\A[A-Z_][A-Z0-9_]*=/, token) do
      drop_env_assignments(rest)
    else
      [token | rest]
    end
  end

  defp drop_env_assignments([]), do: []

  # Returns true only when the command contains an install/run-style verb —
  # e.g. `npm install`, `yarn add`, `pnpm run test`. Bare invocations like
  # `npm --version` are not matched.
  defp package_manager_command?(cmd) do
    Enum.any?(@install_verbs, fn verb ->
      Regex.match?(~r/\b#{Regex.escape(verb)}\b/, cmd)
    end)
  end
end
