defmodule EyeInTheSkyWeb.OverviewLive.Jobs do
  @moduledoc """
  Global jobs LiveView at /jobs — shows all scheduled jobs across every project.

  Thin wrapper around `EyeInTheSkyWeb.Components.JobsPage` with `project_id: nil`,
  which puts the component into its overview/all-jobs mode.
  """

  use EyeInTheSkyWeb, :live_view

  alias EyeInTheSky.ScheduledJobs
  alias EyeInTheSkyWeb.Components.JobsPage
  alias EyeInTheSkyWeb.Live.Shared.JobsHelpers

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
  def handle_info(:jobs_updated, socket) do
    send_update(JobsPage, id: "jobs-page", jobs_refresh: true)
    {:noreply, socket}
  end

  def handle_info(:do_reload_jobs, socket) do
    send_update(JobsPage, id: "jobs-page", do_reload_jobs: true)
    {:noreply, socket}
  end

  def handle_info({:jobs_page_flash, level, msg}, socket) do
    {:noreply, put_flash(socket, level, msg)}
  end

  def handle_info(_, socket), do: {:noreply, socket}

  @impl true
  def handle_event("run_now", %{"id" => id} = _params, socket) do
    with {:ok, int_id} <- JobsHelpers.parse_job_id(id),
         {:ok, _job} <- ScheduledJobs.get_job(int_id) do
      case ScheduledJobs.run_now(int_id, nil) do
        {:ok, _} ->
          {:noreply, put_flash(socket, :info, "Job triggered")}

        {:error, reason} ->
          {:noreply, put_flash(socket, :error, "Failed to trigger job: #{inspect(reason)}")}
      end
    else
      :error -> {:noreply, put_flash(socket, :error, "Invalid job ID")}
      {:error, :not_found} -> {:noreply, put_flash(socket, :error, "Job not found")}
    end
  end

  def handle_event(event, %{"id" => id} = params, socket)
      when event in ["edit_job", "toggle_job", "delete_job", "expand_job"] do
    with {:ok, _int_id} <- JobsHelpers.parse_job_id(id),
         {:ok, _job} <- ScheduledJobs.get_job(String.to_integer(id)) do
      send_update(JobsPage, id: "jobs-page", event_relay: {event, params})
      {:noreply, socket}
    else
      :error -> {:noreply, put_flash(socket, :error, "Invalid job ID")}
      {:error, :not_found} -> {:noreply, put_flash(socket, :error, "Job not found")}
    end
  end

  def handle_event("edit_schedule", %{"job_id" => job_id} = params, socket) do
    with {:ok, _int_id} <- JobsHelpers.parse_job_id(job_id),
         {:ok, _job} <- ScheduledJobs.get_job(String.to_integer(job_id)) do
      send_update(JobsPage, id: "jobs-page", event_relay: {"edit_schedule", params})
      {:noreply, socket}
    else
      :error -> {:noreply, put_flash(socket, :error, "Invalid job ID")}
      {:error, :not_found} -> {:noreply, put_flash(socket, :error, "Job not found")}
    end
  end

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
