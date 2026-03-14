defmodule EyeInTheSkyWebWeb.OverviewLive.Jobs do
  use EyeInTheSkyWebWeb, :live_view

  alias EyeInTheSkyWeb.ScheduledJobs
  alias EyeInTheSkyWeb.ScheduledJobs.{ScheduledJob, JobHelper}
  alias EyeInTheSkyWeb.Projects
  alias EyeInTheSkyWeb.Claude.AgentManager
  import EyeInTheSkyWebWeb.ControllerHelpers

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(EyeInTheSkyWeb.PubSub, "scheduled_jobs")
    end

    socket =
      socket
      |> assign(:page_title, "Scheduled Jobs")
      |> assign(:sidebar_tab, :jobs)
      |> assign(:sidebar_project, nil)
      |> assign(:jobs, ScheduledJobs.list_jobs())
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
      |> assign(:web_project, Projects.get_project_by_name("EITS Web"))

    {:ok, socket}
  end

  @impl true
  def handle_info(:jobs_updated, socket) do
    {:noreply, assign(socket, :jobs, ScheduledJobs.list_jobs())}
  end

  @impl true
  def handle_event("new_job", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_form, true)
     |> assign(:editing_job, nil)
     |> assign(:changeset, ScheduledJobs.change_job(%ScheduledJob{}))
     |> assign(:form_job_type, "shell_command")
     |> assign(:form_schedule_type, "interval")
     |> assign(:form_config, %{})}
  end

  @impl true
  def handle_event("toggle_claude_drawer", _params, socket) do
    {:noreply, assign(socket, :show_claude_drawer, !socket.assigns.show_claude_drawer)}
  end

  @impl true
  def handle_event("claude_model_changed", %{"model" => model}, socket) do
    {:noreply, assign(socket, :claude_model, model)}
  end

  @impl true
  def handle_event("create_with_claude", params, socket) do
    model = params["model"] || "sonnet"
    effort_level = params["effort_level"]
    description = params["description"]
    project = socket.assigns.web_project

    instructions = job_helper_prompt(description)

    case AgentManager.create_agent(
           model: model,
           effort_level: effort_level,
           project_id: project.id,
           project_path: project.path,
           description: "Job Helper",
           instructions: instructions
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

  @impl true
  def handle_event("edit_job", %{"id" => id}, socket) do
    job = ScheduledJobs.get_job!(String.to_integer(id))
    config = ScheduledJobs.decode_config(job)

    {:noreply,
     socket
     |> assign(:show_form, true)
     |> assign(:editing_job, job)
     |> assign(:changeset, ScheduledJobs.change_job(job))
     |> assign(:form_job_type, job.job_type)
     |> assign(:form_schedule_type, job.schedule_type)
     |> assign(:form_config, config)}
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
    attrs = Map.put(params, "config", Jason.encode!(config))

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
         |> assign(:jobs, ScheduledJobs.list_jobs())
         |> put_flash(:info, "Job saved")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :changeset, changeset)}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Error: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_event("toggle_job", %{"id" => id}, socket) do
    job = ScheduledJobs.get_job!(String.to_integer(id))
    ScheduledJobs.toggle_job(job)
    {:noreply, assign(socket, :jobs, ScheduledJobs.list_jobs())}
  end

  @impl true
  def handle_event("run_now", %{"id" => id}, socket) do
    job_id = String.to_integer(id)
    ScheduledJobs.run_now(job_id)
    {:noreply, put_flash(socket, :info, "Job triggered")}
  end

  @impl true
  def handle_event("delete_job", %{"id" => id}, socket) do
    job = ScheduledJobs.get_job!(String.to_integer(id))

    case ScheduledJobs.delete_job(job) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(:jobs, ScheduledJobs.list_jobs())
         |> put_flash(:info, "Job deleted")}

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

  defp job_helper_prompt(description), do: JobHelper.prompt(description)

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

  defp format_schedule(%{schedule_type: "interval", schedule_value: val}) do
    case Integer.parse(val) do
      {s, _} when s >= 3600 -> "Every #{div(s, 3600)}h"
      {s, _} when s >= 60 -> "Every #{div(s, 60)}m"
      {s, _} -> "Every #{s}s"
      _ -> val
    end
  end

  defp format_schedule(%{schedule_type: "cron", schedule_value: val}), do: describe_cron(val)
  defp format_schedule(_), do: "?"

  @days_of_week %{
    0 => "Sun",
    1 => "Mon",
    2 => "Tue",
    3 => "Wed",
    4 => "Thu",
    5 => "Fri",
    6 => "Sat",
    7 => "Sun"
  }

  defp describe_cron(expr) do
    case String.split(String.trim(expr), ~r/\s+/) do
      [min, hour, dom, mon, dow] ->
        time = format_cron_time(min, hour)
        day = format_cron_day(dow, dom, mon)

        case {time, day} do
          {nil, nil} -> expr
          {t, nil} -> t
          {nil, d} -> d
          {t, d} -> "#{d} at #{t}"
        end

      _ ->
        expr
    end
  end

  defp format_cron_time(min, hour) do
    case {parse_cron_num(min), parse_cron_num(hour)} do
      {{:ok, m}, {:ok, h}} ->
        period = if h >= 12, do: "PM", else: "AM"

        display_h =
          cond do
            h == 0 -> 12
            h > 12 -> h - 12
            true -> h
          end

        if m == 0,
          do: "#{display_h} #{period}",
          else: "#{display_h}:#{String.pad_leading("#{m}", 2, "0")} #{period}"

      {_, {:step, n}} ->
        "Every #{n}h"

      {{:step, n}, _} ->
        "Every #{n}m"

      _ ->
        nil
    end
  end

  defp format_cron_day(dow, dom, mon) do
    cond do
      dow != "*" and dom == "*" and mon == "*" ->
        format_dow(dow)

      dow == "*" and dom != "*" and mon == "*" ->
        "Day #{dom}"

      dow == "*" and dom != "*" and mon != "*" ->
        "#{month_name(mon)} #{dom}"

      dow == "*" and dom == "*" and mon == "*" ->
        "Daily"

      true ->
        nil
    end
  end

  defp format_dow(dow) do
    cond do
      dow == "1-5" ->
        "Weekdays"

      dow == "0,6" or dow == "6,0" ->
        "Weekends"

      String.contains?(dow, ",") ->
        dow |> String.split(",") |> Enum.map_join(", ", &day_name/1)

      String.contains?(dow, "-") ->
        [from, to] = String.split(dow, "-", parts: 2)
        "#{day_name(from)}-#{day_name(to)}"

      true ->
        day_name(dow)
    end
  end

  defp day_name(n) do
    case Integer.parse(to_string(n)) do
      {num, _} -> Map.get(@days_of_week, num, "?")
      _ -> "?"
    end
  end

  defp month_name("1"), do: "Jan"
  defp month_name("2"), do: "Feb"
  defp month_name("3"), do: "Mar"
  defp month_name("4"), do: "Apr"
  defp month_name("5"), do: "May"
  defp month_name("6"), do: "Jun"
  defp month_name("7"), do: "Jul"
  defp month_name("8"), do: "Aug"
  defp month_name("9"), do: "Sep"
  defp month_name("10"), do: "Oct"
  defp month_name("11"), do: "Nov"
  defp month_name("12"), do: "Dec"
  defp month_name(m), do: m

  defp parse_cron_num("*"), do: {:ok, :any}
  defp parse_cron_num("*/" <> step), do: {:step, String.to_integer(step)}

  defp parse_cron_num(s) do
    case Integer.parse(s) do
      {n, ""} -> {:ok, n}
      _ -> :error
    end
  end

  defp format_time(nil), do: "-"

  defp format_time(iso) when is_binary(iso) do
    case NaiveDateTime.from_iso8601(String.replace(iso, "Z", "")) do
      {:ok, dt} ->
        Calendar.strftime(dt, "%m/%d %H:%M")

      _ ->
        iso
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
      <div class="mb-4 flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
        <h1 class="text-xl font-semibold">Scheduled Jobs</h1>
        <div class="flex w-full flex-col gap-2 sm:w-auto sm:flex-row sm:items-center">
          <button class="btn btn-outline btn-sm w-full sm:w-auto" phx-click="toggle_claude_drawer">
            <svg class="w-4 h-4 mr-1" viewBox="0 0 24 24" fill="currentColor">
              <path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm-1 15v-4H7l5-7v4h4l-5 7z" />
            </svg>
            Create with Claude
          </button>
          <button class="btn btn-primary btn-sm w-full sm:w-auto" phx-click="new_job">
            + New Job
          </button>
        </div>
      </div>

      <%!-- Job Form Drawer --%>
      <div class={[
        "fixed inset-y-0 right-0 safe-inset-y z-50 w-full max-w-md bg-base-100 shadow-xl transform transition-transform duration-200 ease-in-out overflow-y-auto",
        if(@show_form, do: "translate-x-0", else: "translate-x-full")
      ]}>
        <div class="p-6">
          <div class="flex items-center justify-between mb-4">
            <h2 class="text-lg font-semibold">
              {if @editing_job, do: "Edit Job", else: "New Job"}
            </h2>
            <button class="btn btn-ghost btn-sm btn-square" phx-click="cancel_form">
              <span class="sr-only">Close job form</span>
              <svg class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  stroke-width="2"
                  d="M6 18L18 6M6 6l12 12"
                />
              </svg>
            </button>
          </div>
          <.form for={@changeset} phx-submit="save_job" phx-change="change_job_type" class="space-y-4">
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

            <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
              <div class="form-control">
                <label class="label"><span class="label-text">Job Type</span></label>
                <select name="job[job_type]" class="select select-bordered w-full">
                  <option value="shell_command" selected={@form_job_type == "shell_command"}>
                    Shell Command
                  </option>
                  <option value="spawn_agent" selected={@form_job_type == "spawn_agent"}>
                    Spawn Agent
                  </option>
                  <option value="mix_task" selected={@form_job_type == "mix_task"}>Mix Task</option>
                </select>
              </div>

              <div class="form-control">
                <label class="label"><span class="label-text">Schedule Type</span></label>
                <select
                  name="job[schedule_type]"
                  class="select select-bordered w-full"
                  phx-change="change_schedule_type"
                >
                  <option value="interval" selected={@form_schedule_type == "interval"}>
                    Interval
                  </option>
                  <option value="cron" selected={@form_schedule_type == "cron"}>Cron</option>
                </select>
              </div>
            </div>

            <div class="form-control">
              <label class="label">
                <span class="label-text">
                  {if @form_schedule_type == "interval",
                    do: "Interval (seconds)",
                    else: "Cron Expression"}
                </span>
              </label>
              <input
                type="text"
                name="job[schedule_value]"
                value={(@editing_job && @editing_job.schedule_value) || ""}
                placeholder={if @form_schedule_type == "interval", do: "60", else: "*/5 * * * *"}
                class="input input-bordered w-full"
                required
              />
            </div>

            <%!-- Conditional config fields --%>
            <%= if @form_job_type == "shell_command" do %>
              <div class="form-control">
                <label class="label"><span class="label-text">Command</span></label>
                <input
                  type="text"
                  name="job[config_command]"
                  value={cfg(@form_config, "command")}
                  placeholder="echo hello"
                  class="input input-bordered w-full"
                />
              </div>
              <div class="form-control">
                <label class="label"><span class="label-text">Working Directory</span></label>
                <input
                  type="text"
                  name="job[config_working_dir]"
                  value={cfg(@form_config, "working_dir")}
                  class="input input-bordered w-full"
                />
              </div>
            <% end %>

            <%= if @form_job_type == "spawn_agent" do %>
              <div class="form-control">
                <label class="label"><span class="label-text">Instructions</span></label>
                <textarea
                  name="job[config_instructions]"
                  class="textarea textarea-bordered w-full"
                  rows="3"
                ><%= cfg(@form_config, "instructions") %></textarea>
              </div>
              <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
                <div class="form-control">
                  <label class="label"><span class="label-text">Model</span></label>
                  <select name="job[config_model]" class="select select-bordered w-full">
                    <option value="haiku" selected={cfg(@form_config, "model") == "haiku"}>
                      Haiku
                    </option>
                    <option value="sonnet" selected={cfg(@form_config, "model") in ["sonnet", ""]}>
                      Sonnet
                    </option>
                    <option value="opus" selected={cfg(@form_config, "model") == "opus"}>
                      Opus
                    </option>
                  </select>
                </div>
                <div class="form-control">
                  <label class="label"><span class="label-text">Project Path</span></label>
                  <input
                    type="text"
                    name="job[config_project_path]"
                    value={cfg(@form_config, "project_path")}
                    class="input input-bordered w-full"
                  />
                </div>
              </div>
              <div class="form-control">
                <label class="label"><span class="label-text">Agent Description</span></label>
                <input
                  type="text"
                  name="job[config_description]"
                  value={cfg(@form_config, "description")}
                  class="input input-bordered w-full"
                />
              </div>
            <% end %>

            <%= if @form_job_type == "mix_task" do %>
              <div class="form-control">
                <label class="label"><span class="label-text">Task Name</span></label>
                <input
                  type="text"
                  name="job[config_task]"
                  value={cfg(@form_config, "task")}
                  placeholder="help"
                  class="input input-bordered w-full"
                />
              </div>
              <div class="form-control">
                <label class="label">
                  <span class="label-text">Arguments (comma-separated)</span>
                </label>
                <input
                  type="text"
                  name="job[config_args]"
                  value={cfg(@form_config, "args")}
                  class="input input-bordered w-full"
                />
              </div>
              <div class="form-control">
                <label class="label"><span class="label-text">Project Path</span></label>
                <input
                  type="text"
                  name="job[config_project_path]"
                  value={cfg(@form_config, "project_path")}
                  class="input input-bordered w-full"
                />
              </div>
            <% end %>

            <div class="sticky bottom-0 bg-base-100 pt-4 pb-1 flex justify-end gap-2">
              <button type="button" class="btn btn-ghost btn-sm" phx-click="cancel_form">
                Cancel
              </button>
              <button type="submit" class="btn btn-primary btn-sm">Save</button>
            </div>
          </.form>
        </div>
      </div>
      <%= if @show_form do %>
        <div class="fixed inset-0 z-40 bg-black/30" phx-click="cancel_form"></div>
      <% end %>

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
              <svg class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  stroke-width="2"
                  d="M6 18L18 6M6 6l12 12"
                />
              </svg>
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

      <%!-- Jobs Table --%>
      <%= if length(@jobs) > 0 do %>
        <div class="md:hidden space-y-3">
          <%= for job <- @jobs do %>
            <article class="rounded-xl border border-base-content/10 bg-base-100 p-3 shadow-sm">
              <button
                class="w-full text-left"
                phx-click="expand_job"
                phx-value-id={job.id}
              >
                <div class="flex items-start justify-between gap-2">
                  <div class="min-w-0">
                    <h3 class="font-medium text-sm truncate">{job.name}</h3>
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
                <tr class={"hover #{if @expanded_job_id == job.id, do: "bg-base-200"}"}>
                  <td
                    class="font-medium cursor-pointer"
                    phx-click="expand_job"
                    phx-value-id={job.id}
                  >
                    {job.name}
                  </td>
                  <td>
                    <%= if job.origin == "system" do %>
                      <span class="badge badge-sm badge-neutral">System</span>
                    <% else %>
                      <span class="badge badge-sm badge-ghost">User</span>
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
                        <svg class="w-3.5 h-3.5" fill="currentColor" viewBox="0 0 20 20">
                          <path d="M6.3 2.841A1.5 1.5 0 004 4.11V15.89a1.5 1.5 0 002.3 1.269l9.344-5.89a1.5 1.5 0 000-2.538L6.3 2.84z" />
                        </svg>
                      </button>
                      <button
                        class="btn btn-ghost btn-xs"
                        phx-click="edit_job"
                        phx-value-id={job.id}
                        title="Edit"
                        aria-label="Edit job"
                      >
                        <svg class="w-3.5 h-3.5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                          <path
                            stroke-linecap="round"
                            stroke-linejoin="round"
                            stroke-width="2"
                            d="M11 5H6a2 2 0 00-2 2v11a2 2 0 002 2h11a2 2 0 002-2v-5m-1.414-9.414a2 2 0 112.828 2.828L11.828 15H9v-2.828l8.586-8.586z"
                          />
                        </svg>
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
                          <svg
                            class="w-3.5 h-3.5"
                            fill="none"
                            viewBox="0 0 24 24"
                            stroke="currentColor"
                          >
                            <path
                              stroke-linecap="round"
                              stroke-linejoin="round"
                              stroke-width="2"
                              d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16"
                            />
                          </svg>
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
            <svg
              class="w-12 h-12 text-base-content/40"
              fill="none"
              viewBox="0 0 24 24"
              stroke="currentColor"
            >
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                stroke-width="2"
                d="M8 7V3m8 4V3m-9 8h10M5 21h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v12a2 2 0 002 2z"
              />
            </svg>
          </div>
          <h3 class="text-lg font-semibold text-base-content mb-2">No scheduled jobs</h3>
          <p class="text-sm text-base-content/60">
            Create a job to schedule agent spawns, shell commands, or mix tasks
          </p>
        </div>
      <% end %>
    </div>
    """
  end
end
