defmodule EyeInTheSkyWeb.Live.Shared.JobsLiveHandlers do
  @moduledoc false

  import Phoenix.LiveView, only: [put_flash: 3]
  alias EyeInTheSky.ScheduledJobs
  alias EyeInTheSkyWeb.Components.JobsPage
  alias EyeInTheSkyWeb.Live.Shared.JobsHelpers

  # Events that JobsPage's dispatch_event handles and the global view may forward.
  @forwarded_events ~w(
    new_job
    cancel_form
    change_job_type
    change_schedule_type
    validate_cron
    save_job
    confirm_run_job
    cancel_run_job
    toggle_claude_drawer
    switch_tab
    cancel_schedule
    save_schedule
    filter_jobs
    toggle_job_select
    select_all_jobs
    bulk_enable
    bulk_disable
    clear_bulk_selection
  )

  # ---------------------------------------------------------------------------
  # handle_jobs_info — delegates to from both LiveViews' handle_info/2
  # ---------------------------------------------------------------------------

  def handle_jobs_info(:jobs_updated, socket) do
    Phoenix.LiveView.send_update(JobsPage, id: "jobs-page", jobs_refresh: true)
    {:noreply, socket}
  end

  def handle_jobs_info(:do_reload_jobs, socket) do
    Phoenix.LiveView.send_update(JobsPage, id: "jobs-page", do_reload_jobs: true)
    {:noreply, socket}
  end

  def handle_jobs_info({:jobs_page_flash, level, msg}, socket) do
    {:noreply, put_flash(socket, level, msg)}
  end

  def handle_jobs_info(_, socket), do: {:noreply, socket}

  # ---------------------------------------------------------------------------
  # handle_run_now — project_id is nil for global, integer for scoped view
  # ---------------------------------------------------------------------------

  def handle_run_now(id, socket, project_id) do
    with {:ok, int_id} <- JobsHelpers.parse_job_id(id),
         {:ok, job} <- ScheduledJobs.get_job(int_id) do
      if not is_nil(project_id) && job.project_id != project_id do
        {:noreply, put_flash(socket, :error, "Access denied")}
      else
        case ScheduledJobs.run_now(int_id, project_id) do
          {:ok, _} ->
            {:noreply, put_flash(socket, :info, "Job triggered")}

          {:error, :unauthorized} ->
            {:noreply, put_flash(socket, :error, "Access denied")}

          {:error, reason} ->
            {:noreply, put_flash(socket, :error, "Failed to trigger job: #{inspect(reason)}")}
        end
      end
    else
      :error -> {:noreply, put_flash(socket, :error, "Invalid job ID")}
      {:error, :not_found} -> {:noreply, put_flash(socket, :error, "Job not found")}
    end
  end

  # ---------------------------------------------------------------------------
  # handle_guarded_event — for edit_job, toggle_job, delete_job, expand_job,
  # edit_schedule. id_or_job_id is the raw string from params.
  # Ownership check fires only when project_id is not nil.
  # ---------------------------------------------------------------------------

  def handle_guarded_event(event, id_or_job_id, params, socket, project_id) do
    with {:ok, int_id} <- JobsHelpers.parse_job_id(id_or_job_id),
         {:ok, job} <- ScheduledJobs.get_job(int_id) do
      if not is_nil(project_id) && job.project_id != project_id do
        {:noreply, put_flash(socket, :error, "Access denied")}
      else
        Phoenix.LiveView.send_update(JobsPage, id: "jobs-page", event_relay: {event, params})
        {:noreply, socket}
      end
    else
      :error -> {:noreply, put_flash(socket, :error, "Invalid job ID")}
      {:error, :not_found} -> {:noreply, put_flash(socket, :error, "Job not found")}
    end
  end

  # ---------------------------------------------------------------------------
  # handle_fallback_event — catch-all relay.
  # Scoped view (project_id != nil): relay all events unconditionally.
  # Global view (project_id == nil): whitelist-only; reject unknown events.
  # ---------------------------------------------------------------------------

  def handle_fallback_event(event, params, socket, project_id) do
    if is_nil(project_id) do
      if event in @forwarded_events do
        Phoenix.LiveView.send_update(JobsPage, id: "jobs-page", event_relay: {event, params})
        {:noreply, socket}
      else
        {:noreply, put_flash(socket, :error, "Unknown event: #{event}")}
      end
    else
      Phoenix.LiveView.send_update(JobsPage, id: "jobs-page", event_relay: {event, params})
      {:noreply, socket}
    end
  end
end
