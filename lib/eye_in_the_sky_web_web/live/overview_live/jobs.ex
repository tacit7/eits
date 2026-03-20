defmodule EyeInTheSkyWebWeb.OverviewLive.Jobs do
  use EyeInTheSkyWebWeb, :live_view

  alias EyeInTheSkyWeb.ScheduledJobs
  alias EyeInTheSkyWeb.ScheduledJobs.ScheduledJob
  alias EyeInTheSkyWeb.Projects
  import EyeInTheSkyWebWeb.Helpers.ViewHelpers, except: [format_time: 1]
  import EyeInTheSkyWebWeb.Live.Shared.JobsHelpers
  import EyeInTheSkyWebWeb.Components.JobFormDrawer
  import EyeInTheSkyWebWeb.Live.Shared.AgentScheduleHelpers
  import EyeInTheSkyWebWeb.Components.AgentScheduleForm

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      EyeInTheSkyWeb.Events.subscribe_scheduled_jobs()
    end

    all_jobs = ScheduledJobs.list_jobs()

    socket =
      socket
      |> assign(:page_title, "Scheduled Jobs")
      |> assign(:sidebar_tab, :jobs)
      |> assign(:sidebar_project, nil)
      |> assign(:all_jobs, all_jobs)
      |> assign(:jobs, all_jobs)
      |> assign(:search_query, "")
      |> assign(:filter_type, "all")
      |> assign(:filter_status, "all")
      |> assign(:filter_origin, "all")
      |> assign(:last_failed_runs, load_last_failed_runs(all_jobs))
      |> assign(:running_ids, MapSet.new(ScheduledJobs.list_running_job_ids()))
      |> assign(:last_run_map, ScheduledJobs.last_run_status_map())
      |> assign(:show_form, false)
      |> assign(:editing_job, nil)
      |> assign(:form, to_form(ScheduledJobs.change_job(%ScheduledJob{})))
      |> assign(:form_job_type, "shell_command")
      |> assign(:form_schedule_type, "interval")
      |> assign(:form_config, %{})
      |> assign(:expanded_job_id, nil)
      |> assign(:runs, [])
      |> assign(:show_claude_drawer, false)
      |> assign(:claude_model, "sonnet")
      |> assign(:web_project, Projects.get_project_by_name("EITS Web"))
      |> assign_agent_schedule_defaults()

    {:ok, socket}
  end

  @impl true
  def handle_info(:jobs_updated, socket) do
    socket =
      socket
      |> reload_all_jobs()
      |> assign(:running_ids, MapSet.new(ScheduledJobs.list_running_job_ids()))
      |> assign(:last_run_map, ScheduledJobs.last_run_status_map())
      |> maybe_reload_agent_schedule_data()

    {:noreply, socket}
  end

  @impl true
  def handle_event("new_job", _params, socket) do
    default_type =
      if socket.assigns.active_tab == :agent_schedules, do: "spawn_agent", else: "shell_command"

    {:noreply,
     socket
     |> assign(:show_form, true)
     |> assign(:editing_job, nil)
     |> assign(:form, to_form(ScheduledJobs.change_job(%ScheduledJob{})))
     |> assign(:form_job_type, default_type)
     |> assign(:form_schedule_type, "interval")
     |> assign(:form_config, %{})}
  end

  @impl true
  def handle_event("toggle_claude_drawer", params, socket),
    do: handle_toggle_claude_drawer(params, socket)

  @impl true
  def handle_event("claude_model_changed", params, socket),
    do: handle_claude_model_changed(params, socket)

  @impl true
  def handle_event("create_with_claude", params, socket) do
    handle_create_with_claude(params, socket, socket.assigns.web_project,
      error_msg: "EITS Web project not found"
    )
  end

  @impl true
  def handle_event("edit_job", %{"id" => id}, socket) do
    with {:ok, int_id} <- parse_job_id(id),
         {:ok, job} <- ScheduledJobs.get_job(int_id) do
      config = ScheduledJobs.decode_config(job)

      {:noreply,
       socket
       |> assign(:show_form, true)
       |> assign(:editing_job, job)
       |> assign(:form, to_form(ScheduledJobs.change_job(job)))
       |> assign(:form_job_type, job.job_type)
       |> assign(:form_schedule_type, job.schedule_type)
       |> assign(:form_config, config)}
    else
      :error -> {:noreply, put_flash(socket, :error, "Invalid job ID")}
      {:error, :not_found} -> {:noreply, put_flash(socket, :error, "Job not found")}
    end
  end

  @impl true
  def handle_event("cancel_form", params, socket), do: handle_cancel_form(params, socket)

  @impl true
  def handle_event("change_job_type", params, socket), do: handle_change_job_type(params, socket)

  @impl true
  def handle_event("change_schedule_type", params, socket),
    do: handle_change_schedule_type(params, socket)

  @impl true
  def handle_event("save_job", params, socket) do
    handle_save_job(params, socket, &reload_all_jobs/1)
  end

  @impl true
  def handle_event("toggle_job", %{"id" => id}, socket) do
    with {:ok, int_id} <- parse_job_id(id),
         {:ok, job} <- ScheduledJobs.get_job(int_id) do
      ScheduledJobs.toggle_job(job)
      {:noreply, reload_all_jobs(socket)}
    else
      :error -> {:noreply, put_flash(socket, :error, "Invalid job ID")}
      {:error, :not_found} -> {:noreply, put_flash(socket, :error, "Job not found")}
    end
  end

  @impl true
  def handle_event("run_now", params, socket), do: handle_run_now(params, socket)

  @impl true
  def handle_event("delete_job", %{"id" => id}, socket) do
    with {:ok, int_id} <- parse_job_id(id),
         {:ok, job} <- ScheduledJobs.get_job(int_id) do
      case ScheduledJobs.delete_job(job) do
        {:ok, _} ->
          {:noreply,
           socket
           |> reload_all_jobs()
           |> put_flash(:info, "Job deleted")}

        {:error, :system_job} ->
          {:noreply, put_flash(socket, :error, "Cannot delete system jobs")}
      end
    else
      :error -> {:noreply, put_flash(socket, :error, "Invalid job ID")}
      {:error, :not_found} -> {:noreply, put_flash(socket, :error, "Job not found")}
    end
  end

  @impl true
  def handle_event("expand_job", params, socket), do: handle_expand_job(params, socket)

  @impl true
  def handle_event("switch_tab", params, socket),
    do: handle_switch_tab(params, socket)

  @impl true
  def handle_event("schedule_prompt", params, socket),
    do: handle_schedule_prompt(params, socket)

  @impl true
  def handle_event("edit_schedule", params, socket),
    do: handle_edit_schedule(params, socket)

  @impl true
  def handle_event("cancel_schedule", params, socket),
    do: handle_cancel_schedule(params, socket)

  @impl true
  def handle_event("save_schedule", params, socket),
    do: handle_save_schedule(params, socket)

  @impl true
  def handle_event("filter_jobs", params, socket) do
    socket =
      socket
      |> assign(:search_query, params["search"] || "")
      |> assign(:filter_type, params["type"] || "all")
      |> assign(:filter_status, params["status"] || "all")
      |> assign(:filter_origin, params["origin"] || "all")

    {:noreply, assign(socket, :jobs, apply_job_filters(socket.assigns.all_jobs, socket.assigns))}
  end

  defp reload_all_jobs(socket) do
    all_jobs = ScheduledJobs.list_jobs()

    socket
    |> assign(:all_jobs, all_jobs)
    |> assign(:jobs, apply_job_filters(all_jobs, socket.assigns))
    |> assign(:last_failed_runs, load_last_failed_runs(all_jobs))
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="px-4 sm:px-6 lg:px-8 py-6">
      <div class="mb-4 flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
        <h1 class="text-xl font-semibold">Scheduled Jobs</h1>
        <div class="flex w-full flex-col gap-2 sm:w-auto sm:flex-row sm:items-center">
          <.link
            navigate="/oban"
            class="btn btn-ghost btn-sm w-full sm:w-auto text-base-content/50"
            title="Oban queue dashboard"
          >
            <.icon name="hero-queue-list" class="w-3.5 h-3.5" /> Oban
          </.link>
          <button class="btn btn-outline btn-sm w-full sm:w-auto" phx-click="toggle_claude_drawer">
            <.icon name="hero-sparkles" class="w-3.5 h-3.5" /> Create with Claude
          </button>
          <button class="btn btn-primary btn-sm w-full sm:w-auto" phx-click="new_job">
            + New Job
          </button>
        </div>
      </div>

      <div class="flex border-b border-base-300 px-4">
        <button
          class={"tab tab-bordered #{if @active_tab == :all_jobs, do: "tab-active"}"}
          phx-click="switch_tab"
          phx-value-tab="all_jobs"
        >
          All Jobs
        </button>
        <button
          class={"tab tab-bordered #{if @active_tab == :agent_schedules, do: "tab-active"}"}
          phx-click="switch_tab"
          phx-value-tab="agent_schedules"
        >
          Schedule Agents
        </button>
      </div>

      <%!-- Job Form Drawer --%>
      <.job_form_drawer
        show={@show_form}
        editing_job={@editing_job}
        form={@form}
        form_job_type={@form_job_type}
        form_schedule_type={@form_schedule_type}
        form_config={@form_config}
      />

      <%!-- Claude Create Drawer --%>
      <div class={[
        "fixed inset-y-0 right-0 safe-inset-y z-50 w-full max-w-sm bg-base-100 shadow-xl transform transition-transform duration-200 ease-in-out overflow-y-auto",
        if(@show_claude_drawer, do: "translate-x-0", else: "translate-x-full")
      ]}>
        <div class="p-6">
          <div class="flex items-center justify-between mb-6">
            <h2 class="text-lg font-semibold">Create Job with Claude</h2>
            <button class="btn btn-ghost btn-sm btn-square" phx-click="toggle_claude_drawer">
              <span class="sr-only">Close Claude drawer</span>
              <.icon name="hero-x-mark" class="w-4 h-4" />
            </button>
          </div>
          <form phx-submit="create_with_claude" class="flex flex-col gap-4">
            <div class="form-control">
              <label class="label"><span class="label-text font-medium">Model</span></label>
              <select
                name="model"
                class="select select-bordered w-full"
                phx-change="claude_model_changed"
              >
                <option value="opus" selected={@claude_model == "opus"}>
                  Opus 4.6 &bull; Most capable for complex work
                </option>
                <option value="sonnet" selected={@claude_model == "sonnet"}>
                  Sonnet 4.5 &bull; Best for everyday tasks
                </option>
                <option value="sonnet[1m]" selected={@claude_model == "sonnet[1m]"}>
                  Sonnet 4.5 (1M) &bull; 1M context window
                </option>
                <option value="haiku" selected={@claude_model == "haiku"}>
                  Haiku 4.5 &bull; Fastest for quick answers
                </option>
              </select>
            </div>

            <%= if @claude_model == "opus" do %>
              <div class="form-control">
                <label class="label"><span class="label-text font-medium">Effort Level</span></label>
                <select name="effort_level" class="select select-bordered w-full">
                  <option value="" selected>Default (high)</option>
                  <option value="low">Low</option>
                  <option value="medium">Medium</option>
                  <option value="high">High</option>
                  <option value="max">Max</option>
                </select>
              </div>
            <% end %>

            <div class="form-control">
              <label class="label"><span class="label-text font-medium">Description</span></label>
              <textarea
                name="description"
                class="textarea textarea-bordered w-full"
                rows="3"
                placeholder="What kind of job do you want to create?"
              ></textarea>
            </div>

            <div class="flex gap-2 mt-4">
              <button type="submit" class="btn btn-primary flex-1">Start</button>
              <button type="button" phx-click="toggle_claude_drawer" class="btn btn-ghost">
                Cancel
              </button>
            </div>
          </form>
        </div>
      </div>
      <%= if @show_claude_drawer do %>
        <div class="fixed inset-0 z-40 bg-black/30" phx-click="toggle_claude_drawer"></div>
      <% end %>

      <%= if @active_tab == :all_jobs do %>
        <%!-- Filter Toolbar --%>
        <form phx-change="filter_jobs" class="flex flex-wrap gap-2 my-4">
          <input
            type="text"
            name="search"
            class="input input-bordered input-sm flex-1 min-w-[200px]"
            placeholder="Search by name or description…"
            value={@search_query}
            phx-debounce="200"
          />
          <select name="type" class="select select-bordered select-sm">
            <option value="all" selected={@filter_type == "all"}>All Types</option>
            <option value="shell_command" selected={@filter_type == "shell_command"}>Shell</option>
            <option value="spawn_agent" selected={@filter_type == "spawn_agent"}>Agent</option>
            <option value="mix_task" selected={@filter_type == "mix_task"}>Mix</option>
          </select>
          <select name="status" class="select select-bordered select-sm">
            <option value="all" selected={@filter_status == "all"}>All Status</option>
            <option value="enabled" selected={@filter_status == "enabled"}>Enabled</option>
            <option value="disabled" selected={@filter_status == "disabled"}>Disabled</option>
          </select>
          <select name="origin" class="select select-bordered select-sm">
            <option value="all" selected={@filter_origin == "all"}>All Origins</option>
            <option value="system" selected={@filter_origin == "system"}>System</option>
            <option value="user" selected={@filter_origin == "user"}>User</option>
          </select>
        </form>
        <%!-- Jobs Table --%>
        <%= if length(@jobs) > 0 do %>
          <div class="md:hidden space-y-3">
            <%= for job <- @jobs do %>
              <% job_state = job_row_state(job, @running_ids, @last_run_map) %>
              <article class={"rounded-xl border border-base-content/10 bg-base-100 p-3 shadow-sm #{row_border_class(job_state)}"}>
                <button
                  class="w-full text-left"
                  phx-click="expand_job"
                  phx-value-id={job.id}
                >
                  <div class="flex items-start justify-between gap-2">
                    <div class="min-w-0">
                      <div class="flex items-center gap-1.5">
                        <h3 class="font-medium text-sm truncate">{job.name}</h3>
                        <%= if job_state == :running do %>
                          <span class="badge badge-warning badge-xs animate-pulse shrink-0">
                            running
                          </span>
                        <% end %>
                      </div>
                      <%= if job.description do %>
                        <p class="text-[11px] text-base-content/60 mt-0.5 truncate">
                          {job.description}
                        </p>
                      <% end %>
                      <p class="text-[11px] font-mono text-base-content/50 mt-1 truncate">
                        {format_schedule(job)}
                        <span class="text-base-content/30 not-italic ml-1">
                          {job.timezone || "UTC"}
                        </span>
                      </p>
                    </div>
                    <span class="badge badge-xs badge-ghost">
                      {type_label(job.job_type)}
                    </span>
                  </div>
                </button>

                <% mobile_failed_run = Map.get(@last_failed_runs, job.id) %>
                <%= if mobile_failed_run do %>
                  <div class="flex items-center gap-1.5 mt-2 flex-wrap">
                    <span class="badge badge-xs badge-error">failed</span>
                    <span class="text-xs text-error/70 truncate flex-1">
                      {format_relative_time(mobile_failed_run.started_at)}{if mobile_failed_run.result,
                        do: ": #{String.slice(mobile_failed_run.result, 0, 60)}",
                        else: ""}
                    </span>
                    <button
                      class="btn btn-ghost btn-xs text-error shrink-0"
                      phx-click="run_now"
                      phx-value-id={job.id}
                      title="Retry"
                    >
                      <.icon name="hero-arrow-path" class="w-3 h-3" />
                    </button>
                  </div>
                <% end %>

                <div class="mt-3 flex items-center justify-between">
                  <span class="text-xs text-base-content/60">Enabled</span>
                  <span class={[
                    "badge badge-xs",
                    if(job.enabled == 1, do: "badge-success", else: "badge-ghost")
                  ]}>
                    {if job.enabled == 1, do: "Yes", else: "No"}
                  </span>
                </div>

                <div class="mt-3 grid grid-cols-2 gap-x-2 gap-y-1 text-xs">
                  <span class="text-base-content/50">Last Run</span>
                  <span class="text-right" title={format_time(job.last_run_at)}>
                    {format_relative_time(job.last_run_at)}
                  </span>
                  <span class="text-base-content/50">Next Run</span>
                  <span class="text-right" title={format_time(job.next_run_at)}>
                    {format_relative_time(job.next_run_at)}
                  </span>
                  <span class="text-base-content/50">Runs</span>
                  <span class="text-right">{job.run_count || 0}</span>
                </div>

                <div class="mt-3 flex items-center justify-end gap-1 border-t border-base-content/10 pt-2">
                  <input
                    type="checkbox"
                    class="toggle toggle-xs toggle-primary"
                    checked={job.enabled == 1}
                    phx-click="toggle_job"
                    phx-value-id={job.id}
                  />
                  <button
                    class="btn btn-ghost btn-xs"
                    phx-click="run_now"
                    phx-value-id={job.id}
                    title="Run Now"
                  >
                    <.icon name="hero-play" class="w-3 h-3" />
                  </button>
                  <button
                    class="btn btn-ghost btn-xs"
                    phx-click="edit_job"
                    phx-value-id={job.id}
                    title="Edit"
                  >
                    <.icon name="hero-pencil-square" class="w-3 h-3" />
                  </button>
                  <button
                    class="btn btn-ghost btn-xs text-error"
                    phx-click="delete_job"
                    phx-value-id={job.id}
                    data-confirm="Delete this job?"
                    title="Delete"
                  >
                    <.icon name="hero-trash" class="w-3 h-3" />
                  </button>
                </div>

                <%= if @expanded_job_id == job.id do %>
                  <div class="mt-3 rounded-lg bg-base-200/50 p-2">
                    <p class="text-xs font-medium mb-2">Recent Runs</p>
                    <%= if length(@runs) > 0 do %>
                      <div class="space-y-1.5">
                        <%= for run <- @runs do %>
                          <div class="rounded-md bg-base-100/70 p-2 text-xs">
                            <div class="flex items-center justify-between gap-2">
                              <span class={"badge badge-xs #{status_badge_class(run.status)}"}>
                                {run.status}
                              </span>
                              <span class="text-base-content/60 truncate">
                                {format_time(run.started_at)}
                              </span>
                            </div>
                            <p class="mt-1 text-base-content/60 truncate">{run.result || "-"}</p>
                          </div>
                        <% end %>
                      </div>
                    <% else %>
                      <p class="text-xs text-base-content/50">No runs yet</p>
                    <% end %>
                  </div>
                <% end %>
              </article>
            <% end %>
          </div>

          <div class="hidden md:block -mx-4 sm:mx-0 overflow-x-auto px-4 sm:px-0">
            <table class="table table-sm">
              <thead>
                <tr>
                  <th>Name</th>
                  <th>Origin</th>
                  <th>Type</th>
                  <th>Schedule</th>
                  <th>Enabled</th>
                  <th>Last Run</th>
                  <th>Next Run</th>
                  <th>Runs</th>
                  <th>Actions</th>
                </tr>
              </thead>
              <tbody>
                <%= for job <- @jobs do %>
                  <% row_state = job_row_state(job, @running_ids, @last_run_map) %>
                  <tr class={"hover #{if @expanded_job_id == job.id, do: "bg-base-200"}"}>
                    <td
                      class={"cursor-pointer #{row_border_class(row_state)}"}
                      phx-click="expand_job"
                      phx-value-id={job.id}
                    >
                      <div class="flex items-center gap-1.5">
                        <span class="font-medium">{job.name}</span>
                        <%= if row_state == :running do %>
                          <span class="badge badge-warning badge-xs animate-pulse">running</span>
                        <% end %>
                      </div>
                      <%= if job.description do %>
                        <p class="text-xs text-base-content/50 mt-0.5">{job.description}</p>
                      <% end %>
                      <% failed_run = Map.get(@last_failed_runs, job.id) %>
                      <%= if failed_run do %>
                        <div class="flex items-center gap-1.5 mt-1.5 flex-wrap">
                          <span class="badge badge-xs badge-error">failed</span>
                          <span class="text-xs text-error/70">
                            {format_relative_time(failed_run.started_at)}{if failed_run.result,
                              do: ": #{String.slice(failed_run.result, 0, 60)}",
                              else: ""}
                          </span>
                          <button
                            class="btn btn-ghost btn-xs text-error"
                            phx-click="run_now"
                            phx-value-id={job.id}
                            title="Retry"
                          >
                            <.icon name="hero-arrow-path" class="w-3 h-3" />
                          </button>
                        </div>
                      <% end %>
                    </td>
                    <td>
                      <%= if job.origin == "system" do %>
                        <span class="badge badge-xs badge-neutral">System</span>
                      <% else %>
                        <span class="badge badge-xs badge-ghost">User</span>
                      <% end %>
                    </td>
                    <td>
                      <span class="badge badge-xs badge-ghost">
                        {type_label(job.job_type)}
                      </span>
                    </td>
                    <td class="text-xs">
                      <span class="font-mono">{format_schedule(job)}</span>
                      <span class="text-base-content/40 ml-1 text-[10px]">
                        {job.timezone || "UTC"}
                      </span>
                    </td>
                    <td>
                      <input
                        type="checkbox"
                        class="toggle toggle-sm toggle-primary"
                        checked={job.enabled == 1}
                        phx-click="toggle_job"
                        phx-value-id={job.id}
                      />
                    </td>
                    <td class="text-xs" title={format_time(job.last_run_at)}>
                      {format_relative_time(job.last_run_at)}
                    </td>
                    <td class="text-xs" title={format_time(job.next_run_at)}>
                      {format_relative_time(job.next_run_at)}
                    </td>
                    <td>{job.run_count || 0}</td>
                    <td>
                      <div class="flex items-center gap-1">
                        <button
                          class="btn btn-ghost btn-xs"
                          phx-click="run_now"
                          phx-value-id={job.id}
                          title="Run Now"
                          aria-label="Run job now"
                        >
                          <.icon name="hero-play" class="w-3.5 h-3.5" />
                        </button>
                        <button
                          class="btn btn-ghost btn-xs"
                          phx-click="edit_job"
                          phx-value-id={job.id}
                          title="Edit"
                          aria-label="Edit job"
                        >
                          <.icon name="hero-pencil-square" class="w-3.5 h-3.5" />
                        </button>
                        <%= if job.origin != "system" do %>
                          <button
                            class="btn btn-ghost btn-xs text-error"
                            phx-click="delete_job"
                            phx-value-id={job.id}
                            data-confirm="Delete this job?"
                            title="Delete"
                            aria-label="Delete job"
                          >
                            <.icon name="hero-trash" class="w-3.5 h-3.5" />
                          </button>
                        <% end %>
                      </div>
                    </td>
                  </tr>
                  <%!-- Expanded Run History --%>
                  <%= if @expanded_job_id == job.id do %>
                    <tr>
                      <td colspan="9" class="bg-base-200 p-4">
                        <div class="text-sm font-medium mb-2">Recent Runs</div>
                        <%= if length(@runs) > 0 do %>
                          <table class="table table-xs">
                            <thead>
                              <tr>
                                <th>Status</th>
                                <th>Started</th>
                                <th>Completed</th>
                                <th>Result</th>
                              </tr>
                            </thead>
                            <tbody>
                              <%= for run <- @runs do %>
                                <tr>
                                  <td>
                                    <span class={"badge badge-xs #{status_badge_class(run.status)}"}>
                                      {run.status}
                                    </span>
                                  </td>
                                  <td class="text-xs">{format_time(run.started_at)}</td>
                                  <td class="text-xs">{format_time(run.completed_at)}</td>
                                  <td class="text-xs max-w-xs truncate" title={run.result || ""}>
                                    {String.slice(run.result || "-", 0, 120)}
                                  </td>
                                </tr>
                              <% end %>
                            </tbody>
                          </table>
                        <% else %>
                          <p class="text-xs text-base-content/50">No runs yet</p>
                        <% end %>
                      </td>
                    </tr>
                  <% end %>
                <% end %>
              </tbody>
            </table>
          </div>
        <% else %>
          <div class="text-center py-16">
            <div class="mx-auto w-24 h-24 bg-base-200 rounded-full flex items-center justify-center mb-4">
              <.icon name="hero-calendar" class="w-12 h-12 text-base-content/40" />
            </div>
            <h3 class="text-lg font-semibold text-base-content mb-2">No scheduled jobs</h3>
            <p class="text-sm text-base-content/60">
              Create a job to schedule agent spawns, shell commands, or mix tasks
            </p>
          </div>
        <% end %>
      <% end %>

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
                          class="btn btn-ghost btn-xs"
                          phx-click="edit_schedule"
                          phx-value-job_id={job.id}
                        >
                          Edit
                        </button>
                        <button class="btn btn-ghost btn-xs" phx-click="run_now" phx-value-id={job.id}>
                          ▶
                        </button>
                      </div>
                    <% else %>
                      <span class="text-xs text-base-content/40">not scheduled</span>
                      <button
                        class="btn btn-primary btn-xs"
                        phx-click="schedule_prompt"
                        phx-value-id={prompt.id}
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
                    <button class="btn btn-ghost btn-xs" phx-click="run_now" phx-value-id={job.id}>
                      ▶
                    </button>
                    <button
                      class="btn btn-ghost btn-xs text-error"
                      phx-click="delete_job"
                      phx-value-id={job.id}
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

      <.agent_schedule_form
        show={@scheduling_prompt != nil}
        prompt={@scheduling_prompt || %{id: nil, name: "", description: nil, project_id: nil}}
        job={@scheduling_job}
        projects={@projects}
      />
    </div>
    """
  end
end
