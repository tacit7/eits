defmodule EyeInTheSkyWebWeb.NavHook do
  @moduledoc """
  LiveView on_mount hook that captures the request URI on every handle_params
  and sets deterministic mobile nav active-state assigns.

  Sets:
  - `nav_path`       — the current request path (e.g. "/projects/3/kanban")
  - `mobile_nav_tab` — one of :sessions | :tasks | :notes | :project | :none
  """

  import Phoenix.LiveView
  import Phoenix.Component, only: [assign: 3]

  alias EyeInTheSkyWebWeb.Helpers.MobileNav

  def on_mount(:default, _params, _session, socket) do
    socket =
      socket
      |> assign(:nav_path, nil)
      |> assign(:mobile_nav_tab, :sessions)
      |> attach_hook(:capture_nav_path, :handle_params, &capture_nav_path/3)

    {:cont, socket}
  end

  defp capture_nav_path(_params, url, socket) do
    path = URI.parse(url).path || "/"
    tab = MobileNav.active_tab_for_path(path)

    {:cont,
     socket
     |> assign(:nav_path, path)
     |> assign(:mobile_nav_tab, tab)}
  end
end
