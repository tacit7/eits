defmodule EyeInTheSkyWeb.ProjectLive.Jobs do
  use EyeInTheSkyWeb, :live_view

  import EyeInTheSkyWeb.Helpers.ProjectLiveHelpers
  alias EyeInTheSky.ScheduledJobs
  alias EyeInTheSkyWeb.Components.JobsPage
  alias EyeInTheSkyWeb.Live.Shared.JobsHelpers

  @impl true
  def mount(%{"id" => _} = params, _session, socket) do
    if connected?(socket) do
      EyeInTheSky.Events.subscribe_scheduled_jobs()
    end

    socket =
      socket
      |> mount_project(params, sidebar_tab: :jobs, page_title_prefix: "Jobs")
      |> assign(:show_all, false)

    if is_nil(socket.assigns.project) do
      {:ok, redirect(socket, to: "/projects")}
    else
      {:ok, socket}
    end
  end

  @impl true
  def handle_params(%{"show_all" => "true"} = _params, _uri, socket) do
    {:noreply, assign(socket, :show_all, true)}
  end

  def handle_params(_params, _uri, socket) do
    {:noreply, assign(socket, :show_all, false)}
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

  # Flash bubbled from JobsPage component — component socket flash is not rendered
  # in the parent's @flash; the component uses send(self(), ...) to propagate it here.
  def handle_info({:jobs_page_flash, level, msg}, socket) do
    {:noreply, put_flash(socket, level, msg)}
  end

  def handle_info(_, socket), do: {:noreply, socket}

  # run_now is handled directly in the parent so "Job triggered" flash propagates
  # to @flash (component socket flash is not rendered here).
  @impl true
  def handle_event("run_now", %{"id" => id} = _params, socket) do
    with {:ok, int_id} <- JobsHelpers.parse_job_id(id),
         {:ok, job} <- ScheduledJobs.get_job(int_id) do
      if not is_nil(socket.assigns[:project_id]) && job.project_id != socket.assigns.project_id do
        {:noreply, put_flash(socket, :error, "Access denied")}
      else
        case ScheduledJobs.run_now(int_id, socket.assigns[:project_id]) do
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

  # Guard events: validate on the parent socket so put_flash propagates to @flash.
  # On error → flash and return. On success → relay to JobsPage for state updates.
  def handle_event(event, %{"id" => id} = params, socket)
      when event in ["edit_job", "toggle_job", "delete_job", "expand_job"] do
    with {:ok, int_id} <- JobsHelpers.parse_job_id(id),
         {:ok, job} <- ScheduledJobs.get_job(int_id) do
      if not is_nil(socket.assigns[:project_id]) && job.project_id != socket.assigns.project_id do
        {:noreply, put_flash(socket, :error, "Access denied")}
      else
        send_update(JobsPage, id: "jobs-page", event_relay: {event, params})
        {:noreply, socket}
      end
    else
      :error -> {:noreply, put_flash(socket, :error, "Invalid job ID")}
      {:error, :not_found} -> {:noreply, put_flash(socket, :error, "Job not found")}
    end
  end

  def handle_event("edit_schedule", %{"job_id" => job_id} = params, socket) do
    with {:ok, int_id} <- JobsHelpers.parse_job_id(job_id),
         {:ok, job} <- ScheduledJobs.get_job(int_id) do
      if not is_nil(socket.assigns[:project_id]) && job.project_id != socket.assigns.project_id do
        {:noreply, put_flash(socket, :error, "Access denied")}
      else
        send_update(JobsPage, id: "jobs-page", event_relay: {"edit_schedule", params})
        {:noreply, socket}
      end
    else
      :error -> {:noreply, put_flash(socket, :error, "Invalid job ID")}
      {:error, :not_found} -> {:noreply, put_flash(socket, :error, "Job not found")}
    end
  end

  # Blanket relay for all other events (save_job, cancel_form, etc.)
  def handle_event(event, params, socket) do
    send_update(JobsPage, id: "jobs-page", event_relay: {event, params})
    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <%= if msg = @flash["error"] do %>
      <div id="flash-error" role="alert" class="alert alert-error text-sm mx-4 mt-4">{msg}</div>
    <% end %>
    <%= if msg = @flash["info"] do %>
      <div id="flash-info" role="alert" class="alert alert-info text-sm mx-4 mt-4">{msg}</div>
    <% end %>
    <.live_component
      module={EyeInTheSkyWeb.Components.JobsPage}
      id="jobs-page"
      project_id={@project_id}
      project={@project}
    />
    """
  end
end
