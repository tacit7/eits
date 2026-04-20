defmodule EyeInTheSkyWeb.Components.Rail.Helpers do
  @moduledoc """
  Shared utility functions used by Rail and its sub-components.
  """

  @doc """
  Returns the uppercase initial letter of a project's name, or "E" as a fallback.
  Handles nil project, nil name, and blank names safely.
  """
  def project_initial(nil), do: "E"

  def project_initial(%{name: name}) when is_binary(name) do
    name
    |> String.trim()
    |> case do
      "" -> "E"
      trimmed -> trimmed |> String.first() |> String.upcase()
    end
  end

  def project_initial(_), do: "E"
end
