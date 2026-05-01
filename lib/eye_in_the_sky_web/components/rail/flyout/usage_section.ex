defmodule EyeInTheSkyWeb.Components.Rail.Flyout.UsageSection do
  @moduledoc false
  use EyeInTheSkyWeb, :html

  alias EyeInTheSkyWeb.Components.Rail.Flyout.Helpers

  def usage_content(assigns) do
    ~H"""
    <Helpers.simple_link href="/usage" label="Usage Dashboard" icon="hero-chart-bar" />
    """
  end
end
