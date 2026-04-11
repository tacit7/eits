defmodule EyeInTheSkyWeb.Components.AgentScheduleSection do
  @moduledoc """
  LiveComponent for the Schedule Agents tab.

  Owns all agent-schedule state (prompts, prompt_job_map, scheduling_prompt,
  scheduling_job, orphaned_jobs, projects) and handles the schedule event
  handlers previously in jobs_page.ex.

  Receives active_tab as an attr from jobs_page. When it switches to
  :agent_schedules, this component loads its data via maybe_reload_agent_schedule_data.

  cancel_schedule and save_schedule come from agent_schedule_form (no phx-target),
  so they bubble to the parent LiveView → jobs_page relay → send_update here with
  event_relay: {event, params}.

  schedule_prompt, edit_schedule, run_now, delete_job buttons in this component's
  render all target @myself directly.
  """

  use EyeInTheSkyWeb, :live_component

  import EyeInTheSkyWeb.Live.Shared.AgentScheduleHelpers
  import EyeInTheSkyWeb.Live.Shared.JobsHelpers, only: [handle_run_now: 2, handle_delete_job: 4, parse_job_id: 1]
  import EyeInTheSkyWeb.Components.AgentScheduleForm

  alias EyeInTheSky.ScheduledJobs

  # ---------------------------------------------------------------------------
  # Lifecycle
  # ---------------------------------------------------------------------------

  @impl true
  # Refresh request from jobs_page on jobs_refresh
  def update(%{action: :refresh}, socket) do
    {:ok, maybe_reload_agent_schedule_data(socket)}
  end

  # Relay from jobs_page for cancel_schedule / save_schedule (no phx-target on agent_schedule_form)
  def update(%{event_relay: {event, params}}, socket) do
    case dispatch_event(event, params, socket) do
      {:noreply, new_socket} -> {:ok, new_socket}
      _ -> {:ok, socket}
    end
  end

  # Normal attrs update — called on every parent re-render with project_id + active_tab
  def update(assigns, socket) do
    prev_tab = Map.get(socket.assigns, :active_tab, :all_jobs)
    prev_project_id = Map.get(socket.assigns, :project_id)
    new_tab = assigns.active_tab
    initialized = Map.has_key?(socket.assigns, :initialized)

    socket =
      if initialized do
        socket
        |> assign(:project_id, assigns.project_id)
        |> assign(:active_tab, new_tab)
      else
        socket
        |> assign(:initialized, true)
        |> assign(:project_id, assigns.project_id)
        |> assign(:active_tab, new_tab)
        |> assign(
          prompts: [],
          prompt_job_map: %{},
          scheduling_prompt: nil,
          scheduling_job: nil,
          orphaned_jobs: [],
          projects: EyeInTheSky.Projects.list_projects()
        )
      end

    # Load schedule data when switching to agent_schedules tab OR when project_id
    # changes while already on the agent_schedules tab (avoids stale data).
    tab_switched = new_tab == :agent_schedules and prev_tab != :agent_schedules
    project_changed = initialized and new_tab == :agent_schedules and assigns.project_id != prev_project_id

    socket =
      if tab_switched or project_changed do
        maybe_reload_agent_schedule_data(socket)
      else
        socket
      end

    {:ok, socket}
  end

  # ---------------------------------------------------------------------------
  # Events (buttons in this render target @myself; relay handles the rest)
  # ---------------------------------------------------------------------------

  @impl true
  def handle_event(event, params, socket) do
    dispatch_event(event, params, socket)
  end

  defp dispatch_event("schedule_prompt", params, socket),
    do: handle_schedule_prompt(params, socket)

  defp dispatch_event("edit_schedule", params, socket),
    do: handle_edit_schedule(params, socket)

  defp dispatch_event("cancel_schedule", params, socket),
    do: handle_cancel_schedule(params, socket)

  defp dispatch_event("save_schedule", params, socket),
    do: handle_save_schedule(params, socket)

  defp dispatch_event("run_now", %{"id" => id} = params, socket) do
    with {:ok, int_id} <- parse_job_id(id),
         {:ok, job} <- ScheduledJobs.get_job(int_id) do
      if not is_nil(socket.assigns.project_id) && job.project_id != socket.assigns.project_id do
        {:noreply, Phoenix.LiveView.put_flash(socket, :error, "Access denied")}
      else
        handle_run_now(params, socket)
      end
    else
      :error -> {:noreply, Phoenix.LiveView.put_flash(socket, :error, "Invalid job ID")}
      {:error, :not_found} -> {:noreply, Phoenix.LiveView.put_flash(socket, :error, "Job not found")}
    end
  end

  defp dispatch_event("delete_job", params, socket),
    do: handle_delete_job(params, socket, &reload_orphaned_jobs/1, socket.assigns.project_id)

  defp dispatch_event(_event, _params, socket), do: {:noreply, socket}

  defp reload_orphaned_jobs(socket) do
    assign(socket, :orphaned_jobs, ScheduledJobs.list_orphaned_agent_jobs())
  end

  # ---------------------------------------------------------------------------
  # Template
  # ---------------------------------------------------------------------------

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <%= if @active_tab == :agent_schedules do %>
        <div class="p-4 space-y-6">
          <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-3">
            <%= for prompt <- @prompts do %>
              <% job = Map.get(@prompt_job_map, prompt.id) %>
              <div class={"card bg-base-200 border #{if job, do: "border-primary", else: "border-base-300"}"}>
                <div class="card-body p-4 gap-2">
                  <div class="flex items-start justify-between">
                    <div class="flex items-center gap-1.5">
                      <h3 class="font-semibold text-sm leading-tight">{prompt.name}</h3>
                      <%= if Map.get(prompt, :source) do %>
                        <span class={"badge badge-xs #{if prompt.source == :project, do: "badge-info", else: "badge-ghost"}"}>
                          {if prompt.source == :project, do: "project", else: "global"}
                        </span>
                      <% end %>
                    </div>
                    <%= if job do %>
                      <span class="badge badge-success badge-xs whitespace-nowrap">● active</span>
                    <% end %>
                  </div>
                  <p class="text-xs text-base-content/60 line-clamp-2">{prompt.description}</p>
                  <div class="flex items-center justify-between mt-1">
                    <%= if job do %>
                      <span class="font-mono text-xs text-base-content/50">{job.schedule_value}</span>
                      <div class="flex gap-1">
                        <button
                          class="btn btn-ghost btn-xs min-h-[44px] min-w-[44px]"
                          phx-click="edit_schedule"
                          phx-value-job_id={job.id}
                          phx-target={@myself}
                        >
                          Edit
                        </button>
                        <button
                          class="btn btn-ghost btn-xs min-h-[44px] min-w-[44px]"
                          phx-click="run_now"
                          phx-value-id={job.id}
                          phx-target={@myself}
                        >
                          ▶
                        </button>
                      </div>
                    <% else %>
                      <span class="text-xs text-base-content/40">not scheduled</span>
                      <button
                        class="btn btn-primary btn-xs"
                        phx-click="schedule_prompt"
                        phx-value-id={prompt.id}
                        phx-target={@myself}
                      >
                        + Schedule
                      </button>
                    <% end %>
                  </div>
                </div>
              </div>
            <% end %>
          </div>

          <%= if @orphaned_jobs != [] do %>
            <div>
              <p class="text-xs font-semibold uppercase tracking-wide text-base-content/40 mb-2">
                Detached Schedules
              </p>
              <div class="space-y-2">
                <%= for job <- @orphaned_jobs do %>
                  <div class="flex items-center gap-3 p-3 rounded-lg bg-base-200 border border-warning/40">
                    <div class="flex-1 min-w-0">
                      <span class="text-sm truncate">{job.name}</span>
                      <span class="badge badge-warning badge-xs ml-2">Prompt deactivated</span>
                    </div>
                    <span class="font-mono text-xs text-base-content/50 shrink-0">
                      {job.schedule_value}
                    </span>
                    <button
                      class="btn btn-ghost btn-xs min-h-[44px] min-w-[44px]"
                      phx-click="run_now"
                      phx-value-id={job.id}
                      phx-target={@myself}
                    >
                      ▶
                    </button>
                    <button
                      class="btn btn-ghost btn-xs text-error min-h-[44px] min-w-[44px]"
                      phx-click="delete_job"
                      phx-value-id={job.id}
                      phx-target={@myself}
                    >
                      Delete
                    </button>
                  </div>
                <% end %>
              </div>
            </div>
          <% end %>
        </div>
      <% end %>

      <%!-- Agent Schedule Form — save_schedule / cancel_schedule events have no phx-target,
           so they bubble to the parent LiveView which relays them back here via jobs_page
           send_update event_relay. Rendered outside the tab guard so it can show
           regardless of which tab is active. --%>
      <.agent_schedule_form
        show={@scheduling_prompt != nil}
        prompt={@scheduling_prompt || %{id: nil, name: "", description: nil, project_id: nil}}
        job={@scheduling_job}
        projects={@projects}
        context_project_id={@project_id}
      />
    </div>
    """
  end
end
