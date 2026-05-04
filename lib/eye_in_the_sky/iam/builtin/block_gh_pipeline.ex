defmodule EyeInTheSky.IAM.Builtin.BlockGhPipeline do
  @moduledoc """
  Deny `gh` CLI commands that trigger or mutate CI/CD pipelines:
  `gh run rerun/watch`, `gh workflow run/enable/disable`.

  Accidental pipeline triggers can kick off expensive or destructive CI jobs,
  deploy to production, or consume limited runner minutes.

  Supports an `"allowWorkflows"` condition — a list of workflow filename or
  name strings that are permitted. If the command contains any listed workflow,
  the policy does not match.
  """

  @behaviour EyeInTheSky.IAM.BuiltinMatcher

  alias EyeInTheSky.IAM.Context
  alias EyeInTheSky.IAM.Policy

  # Matches pipeline-mutating gh subcommands:
  #   gh workflow run/enable/disable
  #   gh run rerun/cancel  (re-triggers or cancels an existing run)
  # Does NOT match read-only gh run list/view/watch/download.
  @pipeline_re ~r/\bgh\s+(?:workflow\s+(?:run|enable|disable)|run\s+(?:rerun|cancel))\b/

  @impl true
  def matches?(%Policy{} = p, %Context{tool: "Bash", resource_content: cmd})
      when is_binary(cmd) do
    if Regex.match?(@pipeline_re, cmd) do
      not allowed?(cmd, p)
    else
      false
    end
  end

  def matches?(_, _), do: false

  defp allowed?(cmd, %Policy{condition: %{} = cond}) do
    workflows =
      Map.get(cond, "allowWorkflows") || Map.get(cond, :allowWorkflows) || []

    Enum.any?(workflows, fn wf when is_binary(wf) ->
      String.contains?(cmd, wf)
    end)
  end

  defp allowed?(_, _), do: false
end
