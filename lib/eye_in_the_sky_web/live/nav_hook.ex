defmodule EyeInTheSkyWeb.NavHook do
  @moduledoc """
  LiveView on_mount hook that captures the request URI on every handle_params
  and sets deterministic mobile nav active-state assigns.

  Sets:
  - `nav_path`         — the current request path (e.g. "/projects/3/kanban")
  - `mobile_nav_tab`   — one of :sessions | :tasks | :notes | :project | :none
  - `palette_projects` — list of %{id, name} maps for the command palette

  Palette events are delegated to PaletteHandlers and PaletteAgentHandlers.
  """

  import Phoenix.LiveView, only: [attach_hook: 4, push_event: 3, connected?: 1]
  import Phoenix.Component, only: [assign: 3]

  alias EyeInTheSky.Events
  alias EyeInTheSky.Projects
  alias EyeInTheSky.Settings
  alias EyeInTheSkyWeb.Helpers.MobileNav
  alias EyeInTheSkyWeb.NavHook.PaletteAgentHandlers
  alias EyeInTheSkyWeb.NavHook.PaletteHandlers

  def on_mount(:default, _params, _session, socket) do
    if connected?(socket), do: Events.subscribe_agents()

    projects =
      Projects.list_projects()
      |> Enum.map(&%{id: &1.id, name: &1.name})

    socket =
      socket
      |> assign(:nav_path, nil)
      |> assign(:mobile_nav_tab, :sessions)
      |> assign(:palette_projects, projects)
      |> assign(:palette_shortcut, Settings.get("palette_shortcut") || "auto")
      |> attach_hook(:capture_nav_path, :handle_params, &capture_nav_path/3)
      |> attach_hook(:session_failed_toast, :handle_info, &maybe_push_session_failed/2)
      |> attach_hook(:palette_sessions, :handle_event, &PaletteHandlers.handle_palette_event/3)
      |> attach_hook(
        :palette_create_task,
        :handle_event,
        &PaletteHandlers.handle_create_task_event/3
      )
      |> attach_hook(
        :palette_create_note,
        :handle_event,
        &PaletteHandlers.handle_create_note_event/3
      )
      |> attach_hook(
        :palette_create_chat,
        :handle_event,
        &PaletteHandlers.handle_create_chat_event/3
      )
      |> attach_hook(
        :palette_create_agent,
        :handle_event,
        &PaletteAgentHandlers.handle_create_agent/3
      )
      |> attach_hook(
        :palette_update_agent,
        :handle_event,
        &PaletteAgentHandlers.handle_update_agent/3
      )
      |> attach_hook(
        :palette_list_agents,
        :handle_event,
        &PaletteAgentHandlers.handle_list_agents/3
      )
      |> attach_hook(:palette_get_agent, :handle_event, &PaletteAgentHandlers.handle_get_agent/3)
      |> attach_hook(
        :palette_delete_agent,
        :handle_event,
        &PaletteAgentHandlers.handle_delete_agent/3
      )

    {:cont, socket}
  end

  defp maybe_push_session_failed({:agent_stopped, %{status: "failed"} = session}, socket) do
    title = Map.get(session, :name) || Map.get(session, :title) || "Session"
    reason = Map.get(session, :status_reason)

    {:cont, push_event(socket, "session:failed", %{title: title, reason: reason})}
  end

  defp maybe_push_session_failed(_msg, socket), do: {:cont, socket}

  defp capture_nav_path(_params, url, socket) do
    path = URI.parse(url).path || "/"
    tab = MobileNav.active_tab_for_path(path)

    {:cont,
     socket
     |> assign(:nav_path, path)
     |> assign(:mobile_nav_tab, tab)}
  end
end
