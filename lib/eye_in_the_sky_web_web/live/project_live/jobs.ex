defmodule EyeInTheSkyWebWeb.ProjectLive.Jobs do
  use EyeInTheSkyWebWeb, :live_view

  alias EyeInTheSkyWeb.ScheduledJobs
  alias EyeInTheSkyWeb.ScheduledJobs.{ScheduledJob, JobHelper}
  alias EyeInTheSkyWeb.Claude.AgentManager
  import EyeInTheSkyWebWeb.Helpers.ProjectLiveHelpers
  import EyeInTheSkyWebWeb.Live.Shared.JobsHelpers
  import EyeInTheSkyWebWeb.Components.JobFormDrawer

  @impl true
  def mount(%{"id" => _} = params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(EyeInTheSkyWeb.PubSub, "scheduled_jobs")
    end

    socket =
      socket
      |> mount_project(params, sidebar_tab: :jobs, page_title_prefix: "Jobs")
      |> assign(:form_scope, "project")
      |> assign(:show_form, false)
      |> assign(:editing_job, nil)
      |> assign(:changeset, ScheduledJobs.change_job(%ScheduledJob{}))
      |> assign(:form_job_type, "shell_command")
      |> assign(:form_schedule_type, "interval")
      |> assign(:form_config, %{})
      |> assign(:expanded_job_id, nil)
      |> assign(:runs, [])
      |> assign(:show_claude_drawer, false)
      |> assign(:claude_model, "sonnet")

    socket =
      if socket.assigns.project do
        project_id = socket.assigns.project_id

        socket
        |> assign(:project_jobs, ScheduledJobs.list_jobs_for_project(project_id))
        |> assign(:global_jobs, ScheduledJobs.list_global_jobs())
      else
        socket
        |> assign(:project_jobs, [])
        |> assign(:global_jobs, [])
      end

    {:ok, socket}
  end

  @impl true
  def handle_info(:jobs_updated, socket) do
    {:noreply, reload_jobs(socket)}
  end

  @impl true
  def handle_event("new_job", %{"scope" => scope}, socket) do
    {:noreply,
     socket
     |> assign(:show_form, true)
     |> assign(:editing_job, nil)
     |> assign(:form_scope, scope)
     |> assign(:changeset, ScheduledJobs.change_job(%ScheduledJob{}))
     |> assign(:form_job_type, "shell_command")
     |> assign(:form_schedule_type, "interval")
     |> assign(:form_config, %{})}
  end

  def handle_event("new_job", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_form, true)
     |> assign(:editing_job, nil)
     |> assign(:form_scope, "project")
     |> assign(:changeset, ScheduledJobs.change_job(%ScheduledJob{}))
     |> assign(:form_job_type, "shell_command")
     |> assign(:form_schedule_type, "interval")
     |> assign(:form_config, %{})}
  end

  @impl true
  def handle_event("cancel_form", params, socket), do: handle_cancel_form(params, socket)

  @impl true
  def handle_event("change_job_type", params, socket), do: handle_change_job_type(params, socket)

  @impl true
  def handle_event("change_schedule_type", params, socket),
    do: handle_change_schedule_type(params, socket)

  @impl true
  def handle_event("save_job", %{"job" => params}, socket) do
    config = build_config(params)

    project_id =
      if socket.assigns.form_scope == "global", do: nil, else: socket.assigns.project_id

    attrs =
      params
      |> Map.put("config", Jason.encode!(config))
      |> Map.put("project_id", project_id)

    result =
      if socket.assigns.editing_job do
        ScheduledJobs.update_job(socket.assigns.editing_job, attrs)
      else
        ScheduledJobs.create_job(attrs)
      end

    case result do
      {:ok, _job} ->
        {:noreply,
         socket
         |> assign(:show_form, false)
         |> reload_jobs()
         |> put_flash(:info, "Job saved")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :changeset, changeset)}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Error: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_event("edit_job", %{"id" => id}, socket) do
    job = ScheduledJobs.get_job!(String.to_integer(id))
    config = ScheduledJobs.decode_config(job)
    scope = if is_nil(job.project_id), do: "global", else: "project"

    {:noreply,
     socket
     |> assign(:show_form, true)
     |> assign(:editing_job, job)
     |> assign(:form_scope, scope)
     |> assign(:changeset, ScheduledJobs.change_job(job))
     |> assign(:form_job_type, job.job_type)
     |> assign(:form_schedule_type, job.schedule_type)
     |> assign(:form_config, config)}
  end

  @impl true
  def handle_event("toggle_job", %{"id" => id}, socket) do
    job = ScheduledJobs.get_job!(String.to_integer(id))
    ScheduledJobs.toggle_job(job)
    {:noreply, reload_jobs(socket)}
  end

  @impl true
  def handle_event("run_now", params, socket), do: handle_run_now(params, socket)

  @impl true
  def handle_event("delete_job", %{"id" => id}, socket) do
    job = ScheduledJobs.get_job!(String.to_integer(id))

    case ScheduledJobs.delete_job(job) do
      {:ok, _} ->
        {:noreply, socket |> reload_jobs() |> put_flash(:info, "Job deleted")}

      {:error, :system_job} ->
        {:noreply, put_flash(socket, :error, "Cannot delete system jobs")}
    end
  end

  @impl true
  def handle_event("expand_job", params, socket), do: handle_expand_job(params, socket)

  @impl true
  def handle_event("toggle_claude_drawer", params, socket),
    do: handle_toggle_claude_drawer(params, socket)

  @impl true
  def handle_event("claude_model_changed", params, socket),
    do: handle_claude_model_changed(params, socket)

  @impl true
  def handle_event("create_with_claude", params, socket) do
    model = params["model"] || "sonnet"
    effort_level = params["effort_level"]
    description = params["description"]
    project = socket.assigns.project

    case AgentManager.create_agent(
           model: model,
           effort_level: effort_level,
           project_id: project.id,
           project_path: project.path,
           description: "Job Helper",
           instructions: JobHelper.prompt(description, project: project)
         ) do
      {:ok, %{session: session}} ->
        {:noreply,
         socket
         |> assign(:show_claude_drawer, false)
         |> push_navigate(to: ~p"/dm/#{session.id}")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to start session: #{inspect(reason)}")}
    end
  end

  defp reload_jobs(socket) do
    socket
    |> assign(:project_jobs, ScheduledJobs.list_jobs_for_project(socket.assigns.project_id))
    |> assign(:global_jobs, ScheduledJobs.list_global_jobs())
  end

  defp format_schedule(%{schedule_type: "interval", schedule_value: val}) do
    case Integer.parse(val) do
      {s, _} when s >= 3600 -> "Every #{div(s, 3600)}h"
      {s, _} when s >= 60 -> "Every #{div(s, 60)}m"
      {s, _} -> "Every #{s}s"
      _ -> val
    end
  end

  defp format_schedule(%{schedule_type: "cron", schedule_value: val}), do: val
  defp format_schedule(_), do: "?"

  @impl true
  def render(assigns) do
    ~H"""
    <div class="px-4 sm:px-6 lg:px-8 py-6">
      <%!-- Job Form Drawer --%>
      <.job_form_drawer
        show={@show_form}
        editing_job={@editing_job}
        changeset={@changeset}
        form_job_type={@form_job_type}
        form_schedule_type={@form_schedule_type}
        form_config={@form_config}
        project_id={@project_id}
        project={@project}
        form_scope={@form_scope}
        show_daily_digest={true}
      />

      <%!-- Claude Drawer --%>
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
                  Opus 4.6 · Most capable
                </option>
                <option value="sonnet" selected={@claude_model == "sonnet"}>
                  Sonnet 4.5 · Everyday tasks
                </option>
                <option value="haiku" selected={@claude_model == "haiku"}>Haiku 4.5 · Fastest</option>
              </select>
            </div>
            <%= if @claude_model == "opus" do %>
              <div class="form-control">
                <label class="label"><span class="label-text font-medium">Effort Level</span></label>
                <select name="effort_level" class="select select-bordered w-full">
                  <option value="">Default (high)</option>
                  <option value="low">Low</option>
                  <option value="medium">Medium</option>
                  <option value="high">High</option>
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

      <%!-- Project Jobs --%>
      <div class="mb-8">
        <div class="mb-3 flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
          <div>
            <h2 class="text-base font-semibold">Scheduled Jobs</h2>
            <p class="text-xs text-base-content/50">Scoped to {@project.name}</p>
          </div>
          <div class="flex w-full flex-col gap-2 sm:w-auto sm:flex-row sm:items-center">
            <button class="btn btn-outline btn-sm w-full sm:w-auto" phx-click="toggle_claude_drawer">
              <.icon name="hero-sparkles" class="w-3.5 h-3.5" /> Create with Claude
            </button>
            <button
              class="btn btn-primary btn-sm w-full sm:w-auto"
              phx-click="new_job"
              phx-value-scope="project"
            >
              + New Job
            </button>
          </div>
        </div>
        <.jobs_table jobs={@project_jobs} expanded_job_id={@expanded_job_id} runs={@runs} />
      </div>

      <div class="divider"></div>

      <%!-- Global Jobs --%>
      <div>
        <div class="mb-3 flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
          <div>
            <h2 class="text-base font-semibold">Global Jobs</h2>
            <p class="text-xs text-base-content/50">Run across all projects</p>
          </div>
          <button
            class="btn btn-ghost btn-sm w-full sm:w-auto"
            phx-click="new_job"
            phx-value-scope="global"
          >
            + New Global Job
          </button>
        </div>
        <.jobs_table jobs={@global_jobs} expanded_job_id={@expanded_job_id} runs={@runs} />
      </div>
    </div>
    """
  end

  defp jobs_table(assigns) do
    ~H"""
    <%= if length(@jobs) > 0 do %>
      <div class="md:hidden space-y-3">
        <%= for job <- @jobs do %>
          <article class="rounded-xl border border-base-content/10 bg-base-100 p-3 shadow-sm">
            <button class="w-full text-left" phx-click="expand_job" phx-value-id={job.id}>
              <div class="flex items-start justify-between gap-2">
                <div class="min-w-0">
                  <h3 class="font-medium text-sm truncate">{job.name}</h3>
                  <%= if job.description do %>
                    <p class="text-[11px] text-base-content/60 mt-0.5 truncate">{job.description}</p>
                  <% end %>
                  <p class="text-[11px] font-mono text-base-content/50 mt-1 truncate">
                    {format_schedule(job)}
                  </p>
                </div>
                <span class={"badge badge-sm #{type_badge_class(job.job_type)}"}>
                  {type_label(job.job_type)}
                </span>
              </div>
            </button>

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
              <span class="text-right">{format_time(job.last_run_at)}</span>
              <span class="text-base-content/50">Next Run</span>
              <span class="text-right">{format_time(job.next_run_at)}</span>
              <span class="text-base-content/50">Runs</span>
              <span class="text-right">{job.run_count || 0}</span>
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
              <tr class={"hover #{if @expanded_job_id == job.id, do: "bg-base-200"}"}>
                <td class="cursor-pointer" phx-click="expand_job" phx-value-id={job.id}>
                  <div class="font-medium">{job.name}</div>
                  <%= if job.description do %>
                    <p class="text-xs text-base-content/50 mt-0.5">{job.description}</p>
                  <% end %>
                  <%= if job.origin == "system" do %>
                    <span class="badge badge-xs badge-ghost">system</span>
                  <% end %>
                </td>
                <td>
                  <span class={"badge badge-sm #{type_badge_class(job.job_type)}"}>
                    {type_label(job.job_type)}
                  </span>
                </td>
                <td class="text-xs font-mono">{format_schedule(job)}</td>
                <td>
                  <input
                    type="checkbox"
                    class="toggle toggle-sm toggle-primary"
                    checked={job.enabled == 1}
                    phx-click="toggle_job"
                    phx-value-id={job.id}
                  />
                </td>
                <td class="text-xs">{format_time(job.last_run_at)}</td>
                <td class="text-xs">{format_time(job.next_run_at)}</td>
                <td class="text-xs">{job.run_count || 0}</td>
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
                    <%= if job.origin != "system" do %>
                      <button
                        class="btn btn-ghost btn-xs"
                        phx-click="edit_job"
                        phx-value-id={job.id}
                        title="Edit"
                        aria-label="Edit job"
                      >
                        <.icon name="hero-pencil-square" class="w-3.5 h-3.5" />
                      </button>
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
              <%= if @expanded_job_id == job.id do %>
                <tr>
                  <td colspan="8" class="bg-base-200 p-4">
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
      <div class="text-center py-8 rounded-lg border border-base-300">
        <.icon name="hero-calendar" class="w-6 h-6 text-base-content/30 mx-auto mb-2" />
        <p class="text-sm text-base-content/50">No scheduled jobs</p>
      </div>
    <% end %>
    """
  end
end
