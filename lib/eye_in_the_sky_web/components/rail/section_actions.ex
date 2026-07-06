defmodule EyeInTheSkyWeb.Components.Rail.SectionActions do
  @moduledoc false

  import Phoenix.Component, only: [assign: 2, assign: 3]
  import Phoenix.LiveView, only: [push_navigate: 2]

  alias EyeInTheSkyWeb.Components.Rail.Loader

  # Canonical page per rail section. Click on a section icon NAVIGATES here
  # (desktop); the flyout panel opens via drag-right / chevron / vsbar toggle
  # instead. Sections with no page (:files; :tasks/:notes without a selected
  # project — their pages are project-scoped) keep the open-flyout behavior.
  # NOT /workspace/tasks|notes: those require workspace scope and 302 to /.
  defp section_route(:sessions, _project), do: "/sessions"
  defp section_route(:agents, _project), do: "/agents"
  defp section_route(:skills, _project), do: "/skills"
  defp section_route(:prompts, _project), do: "/prompts"
  defp section_route(:teams, _project), do: "/teams"
  defp section_route(:jobs, _project), do: "/jobs"
  defp section_route(:canvas, _project), do: "/canvases"
  defp section_route(:chat, _project), do: "/chat"
  defp section_route(:usage, _project), do: "/usage"
  defp section_route(:tasks, %{id: id}), do: "/projects/#{id}/tasks"
  defp section_route(:notes, %{id: id}), do: "/projects/#{id}/notes"
  defp section_route(_section, _project), do: nil

  def handle_toggle_section(%{"section" => section_str}, socket) do
    section = Loader.parse_section(section_str)
    route = section_route(section, socket.assigns.sidebar_project)

    # Desktop click = navigate; routeless sections open the flyout. Mobile
    # taps never reach this event — the RailState hook intercepts them in
    # capture phase and sends open_mobile_section instead (the server cannot
    # distinguish viewports; the client can).
    if route do
      {:noreply, push_navigate(socket, to: route)}
    else
      toggle_flyout_for(section, socket)
    end
  end

  @doc """
  Mobile icon tap: open the drawer AND the section's flyout (the pre-existing
  mobile browse behavior). Sent by the RailState hook's capture-phase tap
  guard, which fires only under the md breakpoint.
  """
  def handle_open_mobile_section(%{"section" => section_str}, socket) do
    section = Loader.parse_section(section_str)
    {:noreply, socket} = open_section(section, socket)
    {:noreply, assign(socket, :mobile_open, true)}
  end

  @doc """
  Opens the flyout — fired by drag-right on the icon strip (RailState hook).
  Dragging from a specific icon opens THAT section's flyout (`section` param);
  dragging from empty strip space opens the current active section's.
  """
  def handle_open_flyout(params \\ %{}, socket) do
    section =
      case params do
        %{"section" => s} when is_binary(s) -> Loader.parse_section(s)
        _ -> socket.assigns.active_section
      end

    open_section(section, socket)
  end

  defp toggle_flyout_for(section, socket) do
    current = socket.assigns.active_section
    sticky = Loader.sticky_section(socket.assigns.sidebar_tab)

    if current == section && socket.assigns.flyout_open && not Loader.sticky_section?(section) do
      if sticky do
        {:noreply,
         socket
         |> assign(:active_section, sticky)
         |> assign(:flyout_open, true)
         |> assign(:mobile_open, false)}
      else
        {:noreply, assign(socket, flyout_open: false, mobile_open: false)}
      end
    else
      open_section(section, socket)
    end
  end

  defp open_section(section, socket) do
    # NOTE: deliberately does NOT touch :mobile_open. The mobile drawer sets it
    # via open_mobile (hamburger/swipe) BEFORE any drawer tap reaches here, and
    # forcing it true from desktop paths (drag-open, :files click) would poison
    # the mobile_open-based navigate-vs-flyout branch in handle_toggle_section.
    {:noreply,
     socket
     |> assign(:active_section, section)
     |> assign(:flyout_open, true)
     |> assign(:proj_picker_open, false)
     |> assign(:session_scope, :current)
     |> assign(:session_project_visible, %{})
     |> assign(:session_project_collapsed, MapSet.new())
     |> assign(
       :flyout_sessions,
       Loader.load_flyout_sessions(
         socket.assigns.sidebar_project,
         socket.assigns.session_sort,
         socket.assigns.session_name_filter,
         socket.assigns.session_show
       )
     )
     |> Loader.maybe_load_channels(section, socket.assigns.sidebar_project)
     |> Loader.maybe_load_canvases(section)
     |> Loader.maybe_load_teams(section, socket.assigns.sidebar_project)
     |> Loader.maybe_load_tasks(section, socket.assigns.sidebar_project)
     |> Loader.maybe_load_jobs(section)
     |> Loader.maybe_load_notes(section, socket.assigns.sidebar_project)
     |> Loader.maybe_load_files(section)
     |> Loader.maybe_load_agents(section, socket.assigns.sidebar_project)
     |> Loader.maybe_load_skills(section, socket.assigns.sidebar_project)
     |> Loader.maybe_load_usage(section)}
  end

  def handle_close_flyout(socket) do
    case Loader.sticky_section(socket.assigns.sidebar_tab) do
      nil ->
        {:noreply,
         assign(socket,
           flyout_open: false,
           mobile_open: false,
           proj_picker_open: false,
           show_new_session_form: false
         )}

      sticky ->
        {:noreply,
         socket
         |> assign(:active_section, sticky)
         |> assign(:flyout_open, true)
         |> assign(:mobile_open, false)
         |> assign(:proj_picker_open, false)
         |> assign(:show_new_session_form, false)}
    end
  end
end
