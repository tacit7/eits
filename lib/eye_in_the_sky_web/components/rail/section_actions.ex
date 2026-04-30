defmodule EyeInTheSkyWeb.Components.Rail.SectionActions do
  @moduledoc false

  import Phoenix.Component, only: [assign: 2, assign: 3]

  alias EyeInTheSkyWeb.Components.Rail.Loader

  def handle_toggle_section(%{"section" => section_str}, socket) do
    section = Loader.parse_section(section_str)
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
      {:noreply,
       socket
       |> assign(:active_section, section)
       |> assign(:flyout_open, true)
       |> assign(:mobile_open, true)
       |> assign(:proj_picker_open, false)
       |> assign(
         :flyout_sessions,
         Loader.load_flyout_sessions(
           socket.assigns.sidebar_project,
           socket.assigns.session_sort,
           socket.assigns.session_name_filter
         )
       )
       |> Loader.maybe_load_channels(section, socket.assigns.sidebar_project)
       |> Loader.maybe_load_canvases(section)
       |> Loader.maybe_load_teams(section, socket.assigns.sidebar_project)
       |> Loader.maybe_load_tasks(section, socket.assigns.sidebar_project)
       |> Loader.maybe_load_jobs(section)
       |> Loader.maybe_load_notes(section, socket.assigns.sidebar_project)
       |> Loader.maybe_load_files(section)
       |> Loader.maybe_load_agents(section, socket.assigns.sidebar_project)}
    end
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
