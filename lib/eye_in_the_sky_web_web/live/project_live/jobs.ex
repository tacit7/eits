defmodule EyeInTheSkyWebWeb.ProjectLive.Jobs do
  use EyeInTheSkyWebWeb, :live_view

  alias EyeInTheSkyWeb.{Projects, ScheduledJobs}
  alias EyeInTheSkyWeb.ScheduledJobs.ScheduledJob

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(EyeInTheSkyWeb.PubSub, "scheduled_jobs")
    end

    project_id =
      case Integer.parse(id) do
        {int, ""} -> int
        _ -> nil
      end

    socket =
      if project_id do
        project = Projects.get_project!(project_id)

        socket
        |> assign(:page_title, "Jobs - #{project.name}")
        |> assign(:project, project)
        |> assign(:project_id, project_id)
        |> assign(:sidebar_tab, :jobs)
        |> assign(:sidebar_project, project)
        |> assign(:project_jobs, ScheduledJobs.list_jobs_for_project(project_id))
        |> assign(:global_jobs, ScheduledJobs.list_global_jobs())
        |> assign(:form_scope, "project")
        |> assign(:show_form, false)
        |> assign(:editing_job, nil)
        |> assign(:changeset, ScheduledJobs.change_job(%ScheduledJob{}))
        |> assign(:form_job_type, "shell_command")
        |> assign(:form_schedule_type, "interval")
        |> assign(:form_config, %{})
        |> assign(:expanded_job_id, nil)
        |> assign(:runs, [])
      else
        socket
        |> assign(:page_title, "Project Not Found")
        |> assign(:project, nil)
        |> assign(:project_id, nil)
        |> assign(:sidebar_tab, :jobs)
        |> assign(:sidebar_project, nil)
        |> assign(:project_jobs, [])
        |> assign(:global_jobs, [])
        |> assign(:form_scope, "project")
        |> assign(:show_form, false)
        |> assign(:editing_job, nil)
        |> assign(:changeset, ScheduledJobs.change_job(%ScheduledJob{}))
        |> assign(:form_job_type, "shell_command")
        |> assign(:form_schedule_type, "interval")
        |> assign(:form_config, %{})
        |> assign(:expanded_job_id, nil)
        |> assign(:runs, [])
        |> put_flash(:error, "Invalid project ID")
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
  def handle_event("cancel_form", _params, socket) do
    {:noreply, assign(socket, :show_form, false)}
  end

  @impl true
  def handle_event("change_job_type", %{"job" => %{"job_type" => jt}}, socket) do
    {:noreply, assign(socket, :form_job_type, jt)}
  end

  @impl true
  def handle_event("change_schedule_type", %{"job" => %{"schedule_type" => st}}, socket) do
    {:noreply, assign(socket, :form_schedule_type, st)}
  end

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
  def handle_event("run_now", %{"id" => id}, socket) do
    ScheduledJobs.run_now(String.to_integer(id))
    {:noreply, put_flash(socket, :info, "Job triggered")}
  end

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
  def handle_event("expand_job", %{"id" => id}, socket) do
    job_id = String.to_integer(id)

    if socket.assigns.expanded_job_id == job_id do
      {:noreply, assign(socket, expanded_job_id: nil, runs: [])}
    else
      runs = ScheduledJobs.list_runs_for_job(job_id)
      {:noreply, assign(socket, expanded_job_id: job_id, runs: runs)}
    end
  end

  defp reload_jobs(socket) do
    socket
    |> assign(:project_jobs, ScheduledJobs.list_jobs_for_project(socket.assigns.project_id))
    |> assign(:global_jobs, ScheduledJobs.list_global_jobs())
  end

  defp build_config(params) do
    case params["job_type"] do
      "spawn_agent" ->
        %{
          "instructions" => params["config_instructions"] || "",
          "model" => params["config_model"] || "sonnet",
          "project_path" => params["config_project_path"] || "",
          "description" => params["config_description"] || ""
        }

      "shell_command" ->
        %{
          "command" => params["config_command"] || "",
          "working_dir" => params["config_working_dir"] || "",
          "timeout_ms" => parse_int(params["config_timeout_ms"], 30_000)
        }

      "mix_task" ->
        args =
          (params["config_args"] || "")
          |> String.split(",", trim: true)
          |> Enum.map(&String.trim/1)

        %{
          "task" => params["config_task"] || "",
          "args" => args,
          "project_path" => params["config_project_path"] || ""
        }

      _ ->
        %{}
    end
  end

  defp parse_int(nil, default), do: default
  defp parse_int("", default), do: default

  defp parse_int(str, default) do
    case Integer.parse(str) do
      {n, _} -> n
      :error -> default
    end
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

  defp format_time(nil), do: "-"

  defp format_time(iso) when is_binary(iso) do
    case NaiveDateTime.from_iso8601(String.replace(iso, "Z", "")) do
      {:ok, dt} -> Calendar.strftime(dt, "%m/%d %H:%M")
      _ -> iso
    end
  end

  defp type_badge_class("spawn_agent"), do: "badge-primary"
  defp type_badge_class("shell_command"), do: "badge-warning"
  defp type_badge_class("mix_task"), do: "badge-accent"
  defp type_badge_class(_), do: "badge-ghost"

  defp type_label("spawn_agent"), do: "Agent"
  defp type_label("shell_command"), do: "Shell"
  defp type_label("mix_task"), do: "Mix"
  defp type_label(t), do: t

  defp status_badge_class("running"), do: "badge-info"
  defp status_badge_class("completed"), do: "badge-success"
  defp status_badge_class("failed"), do: "badge-error"
  defp status_badge_class(_), do: "badge-ghost"

  defp cfg(config, key) do
    case config do
      %{^key => val} when is_binary(val) -> val
      %{^key => val} when is_list(val) -> Enum.join(val, ", ")
      %{^key => val} -> to_string(val)
      _ -> ""
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="px-4 sm:px-6 lg:px-8 py-6">

      <%!-- Job Form Drawer --%>
      <%= if @show_form do %>
        <div class="fixed inset-y-0 right-0 z-50 w-full max-w-md bg-base-100 shadow-xl overflow-y-auto">
          <div class="p-6">
            <div class="flex items-center justify-between mb-4">
              <div>
                <h2 class="text-lg font-semibold">
                  {if @editing_job, do: "Edit Job", else: "New Job"}
                </h2>
                <p class="text-xs text-base-content/50 mt-0.5">
                  {if @form_scope == "global",
                    do: "Global — runs across all projects",
                    else: "Project — scoped to #{@project && @project.name}"}
                </p>
              </div>
              <button class="btn btn-ghost btn-sm btn-square" phx-click="cancel_form">
                <.icon name="hero-x-mark" class="w-4 h-4" />
              </button>
            </div>

            <.form for={@changeset} phx-submit="save_job" phx-change="change_job_type" class="space-y-4">
              <input type="hidden" name="job[project_id]" value={@project_id} />
              <div class="form-control">
                <label class="label"><span class="label-text">Name</span></label>
                <input
                  type="text"
                  name="job[name]"
                  value={(@editing_job && @editing_job.name) || ""}
                  class="input input-bordered w-full"
                  required
                />
              </div>

              <div class="form-control">
                <label class="label"><span class="label-text">Description</span></label>
                <input
                  type="text"
                  name="job[description]"
                  value={(@editing_job && @editing_job.description) || ""}
                  class="input input-bordered w-full"
                />
              </div>

              <div class="grid grid-cols-2 gap-4">
                <div class="form-control">
                  <label class="label"><span class="label-text">Job Type</span></label>
                  <select name="job[job_type]" class="select select-bordered w-full">
                    <option value="shell_command" selected={@form_job_type == "shell_command"}>Shell Command</option>
                    <option value="spawn_agent" selected={@form_job_type == "spawn_agent"}>Spawn Agent</option>
                    <option value="mix_task" selected={@form_job_type == "mix_task"}>Mix Task</option>
                    <option value="daily_digest" selected={@form_job_type == "daily_digest"}>Daily Digest</option>
                  </select>
                </div>

                <div class="form-control">
                  <label class="label"><span class="label-text">Schedule Type</span></label>
                  <select name="job[schedule_type]" class="select select-bordered w-full" phx-change="change_schedule_type">
                    <option value="interval" selected={@form_schedule_type == "interval"}>Interval</option>
                    <option value="cron" selected={@form_schedule_type == "cron"}>Cron</option>
                  </select>
                </div>
              </div>

              <div class="form-control">
                <label class="label">
                  <span class="label-text">
                    {if @form_schedule_type == "interval", do: "Interval (seconds)", else: "Cron Expression"}
                  </span>
                </label>
                <input
                  type="text"
                  name="job[schedule_value]"
                  value={(@editing_job && @editing_job.schedule_value) || ""}
                  placeholder={if @form_schedule_type == "interval", do: "60", else: "*/5 * * * *"}
                  class="input input-bordered w-full font-mono"
                  required
                />
              </div>

              <%= if @form_job_type == "shell_command" do %>
                <div class="form-control">
                  <label class="label"><span class="label-text">Command</span></label>
                  <input type="text" name="job[config_command]" value={cfg(@form_config, "command")} class="input input-bordered w-full font-mono" />
                </div>
                <div class="form-control">
                  <label class="label"><span class="label-text">Working Directory</span></label>
                  <input type="text" name="job[config_working_dir]" value={cfg(@form_config, "working_dir")} class="input input-bordered w-full" />
                </div>
              <% end %>

              <%= if @form_job_type == "spawn_agent" do %>
                <div class="form-control">
                  <label class="label"><span class="label-text">Instructions</span></label>
                  <textarea name="job[config_instructions]" class="textarea textarea-bordered w-full" rows="3"><%= cfg(@form_config, "instructions") %></textarea>
                </div>
                <div class="grid grid-cols-2 gap-4">
                  <div class="form-control">
                    <label class="label"><span class="label-text">Model</span></label>
                    <select name="job[config_model]" class="select select-bordered w-full">
                      <option value="haiku" selected={cfg(@form_config, "model") == "haiku"}>Haiku</option>
                      <option value="sonnet" selected={cfg(@form_config, "model") in ["sonnet", ""]}>Sonnet</option>
                      <option value="opus" selected={cfg(@form_config, "model") == "opus"}>Opus</option>
                    </select>
                  </div>
                  <div class="form-control">
                    <label class="label"><span class="label-text">Project Path</span></label>
                    <input type="text" name="job[config_project_path]" value={cfg(@form_config, "project_path")} class="input input-bordered w-full" />
                  </div>
                </div>
                <div class="form-control">
                  <label class="label"><span class="label-text">Agent Description</span></label>
                  <input type="text" name="job[config_description]" value={cfg(@form_config, "description")} class="input input-bordered w-full" />
                </div>
              <% end %>

              <%= if @form_job_type == "mix_task" do %>
                <div class="form-control">
                  <label class="label"><span class="label-text">Task Name</span></label>
                  <input type="text" name="job[config_task]" value={cfg(@form_config, "task")} class="input input-bordered w-full font-mono" />
                </div>
                <div class="form-control">
                  <label class="label"><span class="label-text">Arguments (comma-separated)</span></label>
                  <input type="text" name="job[config_args]" value={cfg(@form_config, "args")} class="input input-bordered w-full" />
                </div>
                <div class="form-control">
                  <label class="label"><span class="label-text">Project Path</span></label>
                  <input type="text" name="job[config_project_path]" value={cfg(@form_config, "project_path")} class="input input-bordered w-full" />
                </div>
              <% end %>

              <div class="flex justify-end gap-2 pt-4">
                <button type="button" class="btn btn-ghost btn-sm" phx-click="cancel_form">Cancel</button>
                <button type="submit" class="btn btn-primary btn-sm">Save</button>
              </div>
            </.form>
          </div>
        </div>
        <div class="fixed inset-0 z-40 bg-black/30" phx-click="cancel_form"></div>
      <% end %>

      <%!-- Project Jobs --%>
      <div class="mb-8">
        <div class="flex items-center justify-between mb-3">
          <div>
            <h2 class="text-base font-semibold">Scheduled Jobs</h2>
            <p class="text-xs text-base-content/50">Scoped to {@project.name}</p>
          </div>
          <button class="btn btn-primary btn-sm" phx-click="new_job" phx-value-scope="project">
            + New Job
          </button>
        </div>
        <.jobs_table jobs={@project_jobs} expanded_job_id={@expanded_job_id} runs={@runs} />
      </div>

      <div class="divider"></div>

      <%!-- Global Jobs --%>
      <div>
        <div class="flex items-center justify-between mb-3">
          <div>
            <h2 class="text-base font-semibold">Global Jobs</h2>
            <p class="text-xs text-base-content/50">Run across all projects</p>
          </div>
          <button class="btn btn-ghost btn-sm" phx-click="new_job" phx-value-scope="global">
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
      <div class="overflow-x-auto">
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
                    <button class="btn btn-ghost btn-xs" phx-click="run_now" phx-value-id={job.id} title="Run Now">
                      <.icon name="hero-play" class="w-3.5 h-3.5" />
                    </button>
                    <%= if job.origin != "system" do %>
                      <button class="btn btn-ghost btn-xs" phx-click="edit_job" phx-value-id={job.id} title="Edit">
                        <.icon name="hero-pencil-square" class="w-3.5 h-3.5" />
                      </button>
                      <button
                        class="btn btn-ghost btn-xs text-error"
                        phx-click="delete_job"
                        phx-value-id={job.id}
                        data-confirm="Delete this job?"
                        title="Delete"
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
                            <th>Status</th><th>Started</th><th>Completed</th><th>Result</th>
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
