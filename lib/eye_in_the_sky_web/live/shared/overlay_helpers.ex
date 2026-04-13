defmodule EyeInTheSkyWeb.Live.Shared.OverlayHelpers do
  @moduledoc "Helpers for toggling overlay visibility in LiveView contexts."

  def toggle_overlay(current, target) when current == target, do: nil
  def toggle_overlay(_current, target), do: target
end
