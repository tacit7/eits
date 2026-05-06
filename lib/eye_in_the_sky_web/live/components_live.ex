defmodule EyeInTheSkyWeb.ComponentsLive do
  use EyeInTheSkyWeb, :live_view

  @sections [
    {"foundation", "Foundation"},
    {"navigation", "Navigation"},
    {"rows", "Rows"},
    {"layout", "Layout"}
  ]

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       active_section: "foundation",
       page_title: "Component Library",
       sections: @sections,
       form: Phoenix.Component.to_form(%{}, as: :demo)
     )}
  end

  @impl true
  def handle_event("set_section", %{"section" => section}, socket) do
    {:noreply, assign(socket, active_section: section)}
  end

  @impl true
  def handle_event("noop", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event(event, _params, socket) do
    require Logger
    Logger.debug("ComponentsLive: Unexpected handle_event: #{event}")
    {:noreply, socket}
  end
end
