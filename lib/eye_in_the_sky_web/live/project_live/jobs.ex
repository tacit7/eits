defmodule EyeInTheSkyWeb.ProjectLive.Jobs do
  use EyeInTheSkyWeb, :live_view

  import EyeInTheSkyWeb.Helpers.ProjectLiveHelpers
  alias EyeInTheSkyWeb.Components.JobsPage

  @impl true
  def mount(%{"id" => _} = params, _session, socket) do
    if connected?(socket) do
      EyeInTheSky.Events.subscribe_scheduled_jobs()
    end

    socket = mount_project(socket, params, sidebar_tab: :jobs, page_title_prefix: "Jobs")

    if is_nil(socket.assigns.project) do
      {:ok, redirect(socket, to: "/projects")}
    else
      {:ok, socket}
    end
  end

  @impl true
  def handle_info(:jobs_updated, socket) do
    send_update(JobsPage, id: "jobs-page", jobs_refresh: true)
    {:noreply, socket}
  end

  def handle_info(:do_reload_jobs, socket) do
    send_update(JobsPage, id: "jobs-page", do_reload_jobs: true)
    {:noreply, socket}
  end

  # agent_schedule_form lacks phx-target so its events still bubble here.
  @impl true
  def handle_event(event, params, socket)
      when event in ["cancel_schedule", "save_schedule"] do
    send_update(JobsPage, id: "jobs-page", event_relay: {event, params})
    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.live_component
      module={EyeInTheSkyWeb.Components.JobsPage}
      id="jobs-page"
      project_id={@project_id}
      project={@project}
    />
    """
  end
end
