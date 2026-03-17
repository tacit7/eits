defmodule EyeInTheSkyWebWeb.NoteLive.Edit do
  use EyeInTheSkyWebWeb, :live_view
  def mount(_params, _session, socket), do: {:ok, socket}
  def render(assigns), do: ~H"<div>stub</div>"
end
