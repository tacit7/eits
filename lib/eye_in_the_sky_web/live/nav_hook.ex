defmodule EyeInTheSkyWeb.NavHook do
  @moduledoc """
  LiveView on_mount hook that captures the request URI on every handle_params
  and sets deterministic mobile nav active-state assigns.

  Sets:
  - `nav_path`       — the current request path (e.g. "/projects/3/kanban")
  - `mobile_nav_tab` — one of :sessions | :tasks | :notes | :project | :none

  Also handles the `palette:sessions` event for the command palette's
  "Go to Session..." submenu, so every LiveView in the :app live_session
  can serve session data over the socket without an HTTP API call.
  """

  import Phoenix.LiveView
  import Phoenix.Component, only: [assign: 3]

  alias EyeInTheSky.Sessions
  alias EyeInTheSkyWeb.Helpers.MobileNav

  def on_mount(:default, _params, _session, socket) do
    socket =
      socket
      |> assign(:nav_path, nil)
      |> assign(:mobile_nav_tab, :sessions)
      |> attach_hook(:capture_nav_path, :handle_params, &capture_nav_path/3)
      |> attach_hook(:palette_sessions, :handle_event, &handle_palette_event/3)

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

  defp handle_palette_event("palette:sessions", params, socket) do
    project_id = parse_project_id(params["project_id"])

    opts = [status_filter: "all", limit: 30]
    opts = if project_id, do: Keyword.put(opts, :project_id, project_id), else: opts

    sessions = Sessions.list_sessions_filtered(opts)

    results =
      Enum.map(sessions, fn s ->
        %{uuid: s.uuid, name: s.name, description: s.description, status: s.status}
      end)

    {:halt, push_event(socket, "palette:sessions-result", %{sessions: results})}
  end

  defp handle_palette_event(_event, _params, socket), do: {:cont, socket}

  defp parse_project_id(nil), do: nil
  defp parse_project_id(id) when is_integer(id), do: id

  defp parse_project_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {n, ""} -> n
      _ -> nil
    end
  end

  defp parse_project_id(_), do: nil
end
