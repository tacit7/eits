defmodule EyeInTheSkyWeb.Components.JobsPage do
  @moduledoc """
  Shared LiveComponent for both ProjectLive.Jobs and OverviewLive.Jobs.

  Accepts:
    - project_id: integer | nil  (nil = overview / all-jobs view)
    - project:    Project struct | nil

  Manages all jobs-page state internally. Parent LiveViews subscribe to
  PubSub and relay :jobs_updated via send_update/2. Events from child
  function components (job_form_drawer, jobs_table, agent_schedule_form)
  that lack phx-target are forwarded by the parent's handle_event blanket
  relay using the same send_update pattern.

  Agent-schedule state and the Claude AI drawer are delegated to:
    - EyeInTheSkyWeb.Components.AgentScheduleSection
    - EyeInTheSkyWeb.Components.AIJobCreator
  """

  use EyeInTheSkyWeb, :live_component

  alias EyeInTheSky.ScheduledJobs
  alias EyeInTheSky.ScheduledJobs.ScheduledJob
  alias EyeInTheSkyWeb.Components.AIJobCreator
  alias EyeInTheSkyWeb.Components.AgentScheduleSection
  import EyeInTheSkyWeb.Live.Shared.JobsHelpers
  import EyeInTheSkyWeb.Components.JobFormDrawer
  import EyeInTheSkyWeb.Components.JobsTable

  # ---------------------------------------------------------------------------
  # Lifecycle
  # ---------------------------------------------------------------------------

  @impl true
  def mount(socket) do
    {:ok, socket}
  end

  @impl true
  # PubSub relay: parent's handle_info(:jobs_updated) calls
  # send_update(__MODULE__, id: "jobs-page", jobs_refresh: true)
  def update(%{jobs_refresh: true}, socket) do
    socket =
      socket
      |> load_jobs()
      |> assign(:running_ids, MapSet.new(ScheduledJobs.list_running_job_ids()))
      |> assign(:last_run_map, ScheduledJobs.last_run_status_map())

    send_update(AgentScheduleSection, id: "agent-schedule-section", action: :refresh)

    {:ok, socket}
  end

  # Event relay: parent's handle_event blanket calls
  # send_update(__MODULE__, id: "jobs-page", event_relay: {event, params})
  def update(%{event_relay: {event, params}}, socket) do
    case dispatch_event(event, params, socket) do
      {:noreply, new_socket} -> {:ok, new_socket}
      _ -> {:ok, socket}
    end
  end

  # Initial mount — called once with project_id + project attrs.
  def update(assigns, socket) do
    if Map.has_key?(socket.assigns, :project_id) do
      # Re-mount (e.g. project context changed); refresh jobs if project changed.
      prev_project_id = socket.assigns.project_id

      socket =
        socket
        |> assign(:project_id, assigns.project_id)
        |> assign(:project, assigns.project)

      socket =
        if assigns.project_id != prev_project_id do
          socket
          |> load_jobs(apply_filters: false)
        else
          socket
        end

      {:ok, socket}
    else
      socket =
        socket
        |> assign(:project_id, assigns.project_id)
        |> assign(:project, assigns.project)
        |> assign(:form_scope, if(assigns.project_id, do: "project", else: "global"))
        |> assign(:show_form, false)
        |> assign(:editing_job, nil)
        |> assign(:form, to_form(ScheduledJobs.change_job(%ScheduledJob{})))
        |> assign(:form_job_type, "shell_command")
        |> assign(:form_schedule_type, "interval")
        |> assign(:form_config, %{})
        |> assign(:expanded_job_id, nil)
        |> assign(:runs, [])
        |> assign(:search_query, "")
        |> assign(:filter_type, "all")
        |> assign(:filter_status, "all")
        |> assign(:filter_origin, "all")
        |> assign(:running_ids, MapSet.new(ScheduledJobs.list_running_job_ids()))
        |> assign(:last_run_map, ScheduledJobs.last_run_status_map())
        |> assign(:active_tab, :all_jobs)
        |> load_jobs(apply_filters: false)

      {:ok, socket}
    end
  end

  # ---------------------------------------------------------------------------
  # handle_event — for events emitted from the component's own template
  # (phx-target={@myself}).  All other events reach here via the parent's
  # blanket relay (update/2 event_relay branch above).
  # ---------------------------------------------------------------------------

  @impl true
  def handle_event(event, params, socket) do
    case dispatch_event(event, params, socket) do
      {:noreply, new_socket} -> {:noreply, new_socket}
      other -> other
    end
  end

  # ---------------------------------------------------------------------------
  # dispatch_event — single dispatch table shared by handle_event/3 and the
  # update/2 relay branch.
  # ---------------------------------------------------------------------------

  defp dispatch_event("new_job", %{"scope" => scope}, socket) do
    default_type =
      if socket.assigns.active_tab == :agent_schedules, do: "spawn_agent", else: "shell_command"

    {:noreply,
     socket
     |> assign(:show_form, true)
     |> assign(:editing_job, nil)
     |> assign(:form_scope, scope)
     |> assign(:form, to_form(ScheduledJobs.change_job(%ScheduledJob{})))
     |> assign(:form_job_type, default_type)
     |> assign(:form_schedule_type, "interval")
     |> assign(:form_config, %{})}
  end

  defp dispatch_event("new_job", _params, socket) do
    default_type =
      if socket.assigns.active_tab == :agent_schedules, do: "spawn_agent", else: "shell_command"

    default_scope = if socket.assigns.project_id, do: "project", else: "global"

    {:noreply,
     socket
     |> assign(:show_form, true)
     |> assign(:editing_job, nil)
     |> assign(:form_scope, default_scope)
     |> assign(:form, to_form(ScheduledJobs.change_job(%ScheduledJob{})))
     |> assign(:form_job_type, default_type)
     |> assign(:form_schedule_type, "interval")
     |> assign(:form_config, %{})}
  end

  defp dispatch_event("cancel_form", params, socket),
    do: handle_cancel_form(params, socket)

  defp dispatch_event("change_job_type", params, socket),
    do: handle_change_job_type(params, socket)

  defp dispatch_event("change_schedule_type", params, socket),
    do: handle_change_schedule_type(params, socket)

  defp dispatch_event("save_job", params, socket) do
    handle_save_job(params, socket, &load_jobs/1, scoping_project_id: socket.assigns.project_id)
  end

  defp dispatch_event("edit_job", params, socket),
    do: handle_edit_job(params, socket, socket.assigns.project_id)

  defp dispatch_event("toggle_job", params, socket),
    do: handle_toggle_job(params, socket, &load_jobs/1, socket.assigns.project_id)

  defp dispatch_event("run_now", %{"id" => id} = params, socket) do
    with {:ok, int_id} <- parse_job_id(id),
         {:ok, job} <- ScheduledJobs.get_job(int_id),
         :ok <- check_job_access(job, socket.assigns.project_id) do
      handle_run_now(params, socket)
    else
      :error -> {:noreply, put_flash(socket, :error, "Invalid job ID")}
      {:error, :not_found} -> {:noreply, put_flash(socket, :error, "Job not found")}
      {:error, :access_denied} -> {:noreply, put_flash(socket, :error, "Access denied")}
    end
  end

  defp dispatch_event("delete_job", params, socket),
    do: handle_delete_job(params, socket, &load_jobs/1, socket.assigns.project_id)

  defp dispatch_event("expand_job", params, socket),
    do: handle_expand_job(params, socket)

  # Relay to AIJobCreator — toggle open/close from jobs_page header buttons
  defp dispatch_event("toggle_claude_drawer", _params, socket) do
    send_update(AIJobCreator, id: "ai-job-creator", action: :toggle_drawer)
    {:noreply, socket}
  end

  defp dispatch_event("switch_tab", %{"tab" => tab}, socket) do
    new_tab = if tab == "agent_schedules", do: :agent_schedules, else: :all_jobs
    {:noreply, assign(socket, :active_tab, new_tab)}
  end

  # Relay schedule form events to AgentScheduleSection.
  # cancel_schedule and save_schedule come from agent_schedule_form (no phx-target),
  # bubbling through the parent LiveView → here via event_relay.
  defp dispatch_event(event, params, socket)
       when event in ["cancel_schedule", "save_schedule"] do
    send_update(AgentScheduleSection,
      id: "agent-schedule-section",
      event_relay: {event, params}
    )

    {:noreply, socket}
  end

  defp dispatch_event("filter_jobs", params, socket) do
    if socket.assigns.project_id do
      handle_filter_jobs(params, socket, [
        {:all_project_jobs, :project_jobs},
        {:all_global_jobs, :global_jobs}
      ])
    else
      handle_filter_jobs(params, socket, [{:all_jobs, :jobs}])
    end
  end

  defp dispatch_event(_event, _params, socket), do: {:noreply, socket}

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp load_jobs(socket, opts \\ []) do
    apply_filters = Keyword.get(opts, :apply_filters, true)
    project_id = socket.assigns.project_id

    if project_id do
      all_project = ScheduledJobs.list_jobs_for_project(project_id)
      all_global = ScheduledJobs.list_global_jobs()

      socket
      |> assign(:all_project_jobs, all_project)
      |> assign(:all_global_jobs, all_global)
      |> assign(:project_jobs, if(apply_filters, do: apply_job_filters(all_project, socket.assigns), else: all_project))
      |> assign(:global_jobs, if(apply_filters, do: apply_job_filters(all_global, socket.assigns), else: all_global))
      |> assign(:last_failed_runs, load_last_failed_runs(all_project ++ all_global))
    else
      all_jobs = ScheduledJobs.list_jobs()

      socket
      |> assign(:all_jobs, all_jobs)
      |> assign(:jobs, if(apply_filters, do: apply_job_filters(all_jobs, socket.assigns), else: all_jobs))
      |> assign(:last_failed_runs, load_last_failed_runs(all_jobs))
    end
  end

  defp check_job_access(_job, nil), do: :ok
  defp check_job_access(%{project_id: job_project_id}, project_id) when job_project_id != project_id, do: {:error, :access_denied}
  defp check_job_access(_job, _project_id), do: :ok

  # ---------------------------------------------------------------------------
  # Template
  # ---------------------------------------------------------------------------

  @impl true
  def render(assigns) do
    ~H"""
    <div class="px-4 sm:px-6 lg:px-8 py-6">
      <%!-- Overview-only header with title + action buttons --%>
      <%= if is_nil(@project_id) do %>
        <div class="mb-4 flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
          <h1 class="text-xl font-semibold">Scheduled Jobs</h1>
          <div class="flex w-full flex-col gap-2 sm:w-auto sm:flex-row sm:items-center">
            <.link
              navigate="/oban"
              class="btn btn-ghost btn-sm min-h-[44px] w-full sm:w-auto text-base-content/50"
              title="Oban queue dashboard"
            >
              <.icon name="hero-queue-list" class="w-3.5 h-3.5" /> Oban
            </.link>
            <button
              class="btn btn-outline btn-sm min-h-[44px] w-full sm:w-auto"
              phx-click="toggle_claude_drawer"
              phx-target={@myself}
            >
              <.icon name="hero-sparkles" class="w-3.5 h-3.5" /> Create with Claude
            </button>
            <button
              class="btn btn-primary btn-sm min-h-[44px] w-full sm:w-auto"
              phx-click="new_job"
              phx-target={@myself}
            >
              + New Job
            </button>
          </div>
        </div>
      <% end %>

      <div class={"flex border-b border-base-300 #{if @project_id, do: "", else: "px-4"} mb-4"}>
        <button
          class={"btn btn-sm min-h-[44px] #{if @active_tab == :all_jobs, do: "btn-active"}"}
          phx-click="switch_tab"
          phx-value-tab="all_jobs"
          phx-target={@myself}
        >
          All Jobs
        </button>
        <button
          class={"btn btn-sm min-h-[44px] #{if @active_tab == :agent_schedules, do: "btn-active"}"}
          phx-click="switch_tab"
          phx-value-tab="agent_schedules"
          phx-target={@myself}
        >
          Schedule Agents
        </button>
      </div>

      <%!-- Job Form Drawer — events (cancel_form, save_job, etc.) go to parent LiveView
           which relays them back here via send_update event_relay. --%>
      <%= if @project_id do %>
        <.job_form_drawer
          show={@show_form}
          editing_job={@editing_job}
          form={@form}
          form_job_type={@form_job_type}
          form_schedule_type={@form_schedule_type}
          form_config={@form_config}
          project_id={@project_id}
          project={@project}
          form_scope={@form_scope}
          show_daily_digest={true}
        />
      <% else %>
        <.job_form_drawer
          show={@show_form}
          editing_job={@editing_job}
          form={@form}
          form_job_type={@form_job_type}
          form_schedule_type={@form_schedule_type}
          form_config={@form_config}
        />
      <% end %>

      <%!-- Claude AI Drawer — manages show_claude_drawer / claude_model state internally.
           "Create with Claude" buttons above target @myself (jobs_page), which relays
           via send_update(AIJobCreator, action: :toggle_drawer). --%>
      <.live_component
        module={AIJobCreator}
        id="ai-job-creator"
        project_id={@project_id}
        project={@project}
      />

      <%= if @active_tab == :all_jobs do %>
        <%!-- Filter Toolbar --%>
        <form phx-change="filter_jobs" phx-target={@myself} class="flex flex-wrap gap-2 my-4">
          <input
            type="text"
            name="search"
            class="input input-bordered input-sm flex-1 min-w-[200px] text-base"
            placeholder="Search by name or description…"
            value={@search_query}
            phx-debounce="200"
          />
          <select name="type" class="select select-bordered select-sm min-h-[44px]">
            <option value="all" selected={@filter_type == "all"}>All Types</option>
            <option value="shell_command" selected={@filter_type == "shell_command"}>Shell</option>
            <option value="spawn_agent" selected={@filter_type == "spawn_agent"}>Agent</option>
            <option value="mix_task" selected={@filter_type == "mix_task"}>Mix</option>
          </select>
          <select name="status" class="select select-bordered select-sm min-h-[44px]">
            <option value="all" selected={@filter_status == "all"}>All Status</option>
            <option value="enabled" selected={@filter_status == "enabled"}>Enabled</option>
            <option value="disabled" selected={@filter_status == "disabled"}>Disabled</option>
          </select>
          <select name="origin" class="select select-bordered select-sm min-h-[44px]">
            <option value="all" selected={@filter_origin == "all"}>All Origins</option>
            <option value="system" selected={@filter_origin == "system"}>System</option>
            <option value="user" selected={@filter_origin == "user"}>User</option>
          </select>
        </form>

        <%= if @project_id do %>
          <%!-- Project-scoped jobs --%>
          <div class="mb-8">
            <div class="mb-3 flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
              <div>
                <h2 class="text-base font-semibold">Scheduled Jobs</h2>
                <p class="text-xs text-base-content/50">Scoped to {@project.name}</p>
              </div>
              <div class="flex w-full flex-col gap-2 sm:w-auto sm:flex-row sm:items-center">
                <button
                  class="btn btn-outline btn-sm min-h-[44px] w-full sm:w-auto"
                  phx-click="toggle_claude_drawer"
                  phx-target={@myself}
                >
                  <.icon name="hero-sparkles" class="w-3.5 h-3.5" /> Create with Claude
                </button>
                <button
                  class="btn btn-primary btn-sm min-h-[44px] w-full sm:w-auto"
                  phx-click="new_job"
                  phx-value-scope="project"
                  phx-target={@myself}
                >
                  + New Job
                </button>
              </div>
            </div>
            <.jobs_table
              jobs={@project_jobs}
              expanded_job_id={@expanded_job_id}
              runs={@runs}
              running_ids={@running_ids}
              last_run_map={@last_run_map}
              last_failed_runs={@last_failed_runs}
            />
          </div>

          <div class="divider"></div>

          <%!-- Global jobs --%>
          <div>
            <div class="mb-3 flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
              <div>
                <h2 class="text-base font-semibold">Global Jobs</h2>
                <p class="text-xs text-base-content/50">Run across all projects</p>
              </div>
              <button
                class="btn btn-ghost btn-sm min-h-[44px] w-full sm:w-auto"
                phx-click="new_job"
                phx-value-scope="global"
                phx-target={@myself}
              >
                + New Global Job
              </button>
            </div>
            <.jobs_table
              jobs={@global_jobs}
              expanded_job_id={@expanded_job_id}
              runs={@runs}
              running_ids={@running_ids}
              last_run_map={@last_run_map}
              last_failed_runs={@last_failed_runs}
            />
          </div>
        <% else %>
          <%!-- Overview: single unified table --%>
          <.jobs_table
            jobs={@jobs}
            expanded_job_id={@expanded_job_id}
            runs={@runs}
            running_ids={@running_ids}
            last_run_map={@last_run_map}
            last_failed_runs={@last_failed_runs}
            show_origin={true}
          />
        <% end %>
      <% end %>

      <%!-- Agent Schedule Section — manages schedule state + form internally.
           Receives active_tab so it loads data on tab switch.
           Always rendered so the scheduling form can appear above the tab content. --%>
      <.live_component
        module={AgentScheduleSection}
        id="agent-schedule-section"
        project_id={@project_id}
        active_tab={@active_tab}
      />
    </div>
    """
  end
end
