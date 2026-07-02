defmodule EyeInTheSkyWeb.OverviewLive.Jobs do
  @moduledoc """
  Global jobs LiveView at /jobs — shows all scheduled jobs across every project.

  Thin wrapper around `EyeInTheSkyWeb.Components.JobsPage` with `project_id: nil`,
  which puts the component into its overview/all-jobs mode.
  """

  use EyeInTheSkyWeb, :live_view

  alias EyeInTheSkyWeb.Live.Shared.JobsLiveHandlers

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      EyeInTheSky.Events.subscribe_scheduled_jobs()
    end

    socket =
      socket
      |> assign(:page_title, "Jobs")
      |> assign(:sidebar_tab, :jobs)

    {:ok, socket}
  end

  @impl true
  def handle_params(_params, _uri, socket), do: {:noreply, socket}

  @impl true
  def handle_info(msg, socket), do: JobsLiveHandlers.handle_jobs_info(msg, socket)

  # run_now is handled in the parent so "Job triggered" flash propagates to @flash.
  @impl true
  def handle_event("run_now", %{"id" => id}, socket) do
    JobsLiveHandlers.handle_run_now(id, socket, nil)
  end

  # Guard events: parse + existence check; no ownership check in global view.
  def handle_event(event, %{"id" => id} = params, socket)
      when event in ["edit_job", "toggle_job", "delete_job", "expand_job"] do
    JobsLiveHandlers.handle_guarded_event(event, id, params, socket, nil)
  end

  def handle_event("edit_schedule", %{"job_id" => job_id} = params, socket) do
    JobsLiveHandlers.handle_guarded_event("edit_schedule", job_id, params, socket, nil)
  end

  def handle_event(event, params, socket) do
    JobsLiveHandlers.handle_fallback_event(event, params, socket, nil)
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
