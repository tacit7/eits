defmodule EyeInTheSky.IAM.EvaluationSource do
  @moduledoc """
  Label helper for evaluation source tuples.

  Prevents raw tuple formats from leaking into LiveView and trace rendering
  code. All display paths should call `label/1` rather than pattern-matching
  on the source tuple directly.

  ## Source types

    * `:global` — policy matched from the global pool (standard IAM policies).
    * `{:document, id, name, agent_type}` — policy contributed by a named
      policy document attached to the given agent type.
  """

  @type t :: :global | {:document, integer(), String.t(), String.t()}

  @doc """
  Returns a human-readable label for a source value.

      iex> EvaluationSource.label(:global)
      "global"

      iex> EvaluationSource.label({:document, 1, "NoDeployments", "code-reviewer"})
      ~s(document "NoDeployments" → code-reviewer)
  """
  @spec label(t()) :: String.t()
  def label(:global), do: "global"
  def label({:document, _id, name, agent_type}), do: ~s(document "#{name}" → #{agent_type})
end
