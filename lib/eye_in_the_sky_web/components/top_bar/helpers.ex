defmodule EyeInTheSkyWeb.TopBar.Helpers do
  @moduledoc false
  use Phoenix.Component

  @doc """
  Look up a sort label from a list of {key, label} tuples.
  Returns the label if key matches, otherwise returns the default.
  """
  def sort_label(value, options, default \\ "Name A–Z") do
    Enum.find_value(options, default, fn {k, l} -> k == value && l end)
  end
end
