defmodule EyeInTheSkyWeb.ProjectLive.Jobs do
  use EyeInTheSkyWeb, :live_view

  import EyeInTheSkyWeb.Helpers.ProjectLiveHelpers
  alias EyeInTheSkyWeb.Live.Shared.JobsLiveHandlers

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
  def handle_info(msg, socket), do: JobsLiveHandlers.handle_jobs_info(msg, socket)

  # run_now is handled in the parent so "Job triggered" flash propagates to @flash.
  @impl true
  def handle_event("run_now", %{"id" => id}, socket) do
    JobsLiveHandlers.handle_run_now(id, socket, socket.assigns.project_id)
  end

  # Guard events: validate ownership on the parent socket so put_flash reaches @flash.
  def handle_event(event, %{"id" => id} = params, socket)
      when event in ["edit_job", "toggle_job", "delete_job", "expand_job"] do
    JobsLiveHandlers.handle_guarded_event(event, id, params, socket, socket.assigns.project_id)
  end

  def handle_event("edit_schedule", %{"job_id" => job_id} = params, socket) do
    JobsLiveHandlers.handle_guarded_event("edit_schedule", job_id, params, socket, socket.assigns.project_id)
  end

  def handle_event(event, params, socket) do
    JobsLiveHandlers.handle_fallback_event(event, params, socket, socket.assigns.project_id)
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
