defmodule EyeInTheSkyWeb.OverviewLive.Jobs do
  use EyeInTheSkyWeb, :live_view

  alias EyeInTheSkyWeb.Components.JobsPage

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      EyeInTheSky.Events.subscribe_scheduled_jobs()
    end

    socket =
      socket
      |> assign(:page_title, "Scheduled Jobs")
      |> assign(:sidebar_tab, :jobs)
      |> assign(:sidebar_project, nil)

    {:ok, socket}
  end

  @impl true
  def handle_info(:jobs_updated, socket) do
    send_update(JobsPage, id: "jobs-page", jobs_refresh: true)
    {:noreply, socket}
  end

  # Forward all events from child function components (job_form_drawer,
  # jobs_table, agent_schedule_form) that lack phx-target to the component.
  @impl true
  def handle_event(event, params, socket) do
    send_update(JobsPage, id: "jobs-page", event_relay: {event, params})
    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.live_component
      module={EyeInTheSkyWeb.Components.JobsPage}
      id="jobs-page"
      project_id={nil}
      project={nil}
    />
    """
  end
end
