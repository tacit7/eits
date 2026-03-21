defmodule EyeInTheSkyWeb.Live.Shared.JobsHelpers do
  import Phoenix.Component, only: [assign: 2, assign: 3, to_form: 1, to_form: 2]
  import Phoenix.LiveView, only: [put_flash: 3, push_navigate: 2]
  import EyeInTheSkyWeb.ControllerHelpers, only: [parse_int: 2]
  import EyeInTheSkyWeb.Helpers.ViewHelpers, only: [month_name: 1]

  use Phoenix.VerifiedRoutes,
    endpoint: EyeInTheSkyWeb.Endpoint,
    router: EyeInTheSkyWeb.Router,
    statics: EyeInTheSkyWeb.static_paths()

  alias EyeInTheSky.ScheduledJobs
  alias EyeInTheSky.ScheduledJobs.JobHelper
  alias EyeInTheSky.Agents.AgentManager

  # ---------------------------------------------------------------------------
  # Event handler helpers — return {:noreply, socket}
  # Each LiveView delegates its handle_event/3 to these.
  # ---------------------------------------------------------------------------

  def handle_cancel_form(_params, socket) do
    {:noreply, assign(socket, :show_form, false)}
  end

  def handle_change_job_type(%{"job" => %{"job_type" => jt}}, socket) do
    {:noreply, assign(socket, :form_job_type, jt)}
  end

  def handle_change_schedule_type(%{"job" => %{"schedule_type" => st}}, socket) do
    {:noreply, assign(socket, :form_schedule_type, st)}
  end

  def handle_toggle_claude_drawer(_params, socket) do
    {:noreply, assign(socket, :show_claude_drawer, !socket.assigns.show_claude_drawer)}
  end

  def handle_claude_model_changed(%{"model" => model}, socket) do
    {:noreply, assign(socket, :claude_model, model)}
  end

  def parse_job_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {int_id, ""} -> {:ok, int_id}
      _ -> :error
    end
  end

  def parse_job_id(id) when is_integer(id), do: {:ok, id}
  def parse_job_id(_), do: :error

  def handle_expand_job(%{"id" => id}, socket) do
    case parse_job_id(id) do
      {:ok, job_id} ->
        if socket.assigns.expanded_job_id == job_id do
          {:noreply, assign(socket, expanded_job_id: nil, runs: [])}
        else
          runs = ScheduledJobs.list_runs_for_job(job_id)
          {:noreply, assign(socket, expanded_job_id: job_id, runs: runs)}
        end

      :error ->
        {:noreply, put_flash(socket, :error, "Invalid job ID")}
    end
  end

  def handle_run_now(%{"id" => id}, socket) do
    caller_project_id = Map.get(socket.assigns, :project_id)

    with {:ok, int_id} <- parse_job_id(id),
         result <- ScheduledJobs.run_now(int_id, caller_project_id) do
      case result do
        {:ok, _} -> {:noreply, put_flash(socket, :info, "Job triggered")}
        {:error, :unauthorized} -> {:noreply, put_flash(socket, :error, "Access denied")}
        {:error, reason} -> {:noreply, put_flash(socket, :error, "Failed to trigger job: #{inspect(reason)}")}
      end
    else
      :error -> {:noreply, put_flash(socket, :error, "Invalid job ID")}
    end
  end

  # ---------------------------------------------------------------------------
  # Pure helper functions — used in render templates and event handlers
  # ---------------------------------------------------------------------------

  def build_config(params) do
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

  # ---------------------------------------------------------------------------
  # Schedule formatting — shared across overview and project jobs pages
  # ---------------------------------------------------------------------------

  def format_schedule(%{schedule_type: "interval", schedule_value: val}) do
    case Integer.parse(val) do
      {s, _} when s >= 3600 -> "Every #{div(s, 3600)}h"
      {s, _} when s >= 60 -> "Every #{div(s, 60)}m"
      {s, _} -> "Every #{s}s"
      _ -> val
    end
  end

  def format_schedule(%{schedule_type: "cron", schedule_value: val}), do: describe_cron(val)
  def format_schedule(_), do: "?"

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

  def describe_cron(expr) do
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

  def format_cron_time(min, hour) do
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

  def format_cron_day(dow, dom, mon) do
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

  def format_dow(dow) do
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

  def day_name(n) do
    case Integer.parse(to_string(n)) do
      {num, _} -> Map.get(@days_of_week, num, "?")
      _ -> "?"
    end
  end

  def parse_cron_num("*"), do: {:ok, :any}

  def parse_cron_num("*/" <> step) do
    case Integer.parse(step) do
      {n, ""} -> {:step, n}
      _ -> :error
    end
  end

  def parse_cron_num(s) do
    case Integer.parse(s) do
      {n, ""} -> {:ok, n}
      _ -> :error
    end
  end

  # ---------------------------------------------------------------------------
  # Time formatting
  # ---------------------------------------------------------------------------

  def format_time(nil), do: "-"

  def format_time(iso) when is_binary(iso) do
    case NaiveDateTime.from_iso8601(String.replace(iso, "Z", "")) do
      {:ok, dt} -> Calendar.strftime(dt, "%m/%d %H:%M")
      _ -> iso
    end
  end

  # ---------------------------------------------------------------------------
  # Timezone
  # ---------------------------------------------------------------------------

  # Returns the system timezone for display next to schedule values.
  # Tries: TZ env var, then macOS `readlink /etc/localtime`, then "UTC".
  def system_timezone do
    System.get_env("TZ") || detect_macos_timezone() || "UTC"
  end

  defp detect_macos_timezone do
    case System.cmd("readlink", ["/etc/localtime"], stderr_to_stdout: true) do
      {path, 0} ->
        case Regex.run(~r"zoneinfo/(.+)$", String.trim(path)) do
          [_, tz] -> tz
          _ -> nil
        end

      _ ->
        nil
    end
  end

  # ---------------------------------------------------------------------------
  # Badge helpers
  # ---------------------------------------------------------------------------

  def type_badge_class("spawn_agent"), do: "badge-primary"
  def type_badge_class("shell_command"), do: "badge-warning"
  def type_badge_class("mix_task"), do: "badge-accent"
  def type_badge_class(_), do: "badge-ghost"

  def type_label("spawn_agent"), do: "Agent"
  def type_label("shell_command"), do: "Shell"
  def type_label("mix_task"), do: "Mix"
  def type_label(t), do: t

  def status_badge_class("running"), do: "badge-info"
  def status_badge_class("completed"), do: "badge-success"
  def status_badge_class("failed"), do: "badge-error"
  def status_badge_class(_), do: "badge-ghost"

  # Returns :disabled | :running | :failed | :healthy for a job row.
  # running_ids is a MapSet of job IDs currently executing.
  # last_run_map is %{job_id => "completed" | "failed"}.
  def job_row_state(job, running_ids, last_run_map) do
    cond do
      job.enabled != 1 -> :disabled
      MapSet.member?(running_ids, job.id) -> :running
      Map.get(last_run_map, job.id) == "failed" -> :failed
      true -> :healthy
    end
  end

  # Colored left border classes per row state.
  def row_border_class(:disabled), do: "border-l-4 border-base-content/20"
  def row_border_class(:running), do: "border-l-4 border-warning"
  def row_border_class(:failed), do: "border-l-4 border-error"
  def row_border_class(:healthy), do: "border-l-4 border-success"

  def cfg(config, key) do
    case config do
      %{^key => val} when is_binary(val) -> val
      %{^key => val} when is_list(val) -> Enum.join(val, ", ")
      %{^key => val} -> to_string(val)
      _ -> ""
    end
  end

  # ---------------------------------------------------------------------------
  # Last-failed-run helpers (Task 1408)
  # ---------------------------------------------------------------------------

  # Returns %{job_id => %JobRun{}} for jobs whose most recent run was a failure.
  def load_last_failed_runs(jobs) do
    ids = Enum.map(jobs, & &1.id)

    ids
    |> ScheduledJobs.last_run_per_job()
    |> Enum.filter(fn {_id, run} -> run.status == "failed" end)
    |> Map.new()
  end

  # ---------------------------------------------------------------------------
  # Job filtering (Task 1409)
  # ---------------------------------------------------------------------------

  def apply_job_filters(jobs, assigns) do
    q = String.trim(assigns[:search_query] || "")
    type = assigns[:filter_type] || "all"
    status = assigns[:filter_status] || "all"
    origin = assigns[:filter_origin] || "all"

    jobs
    |> filter_jobs_by_search(q)
    |> filter_jobs_by_type(type)
    |> filter_jobs_by_status(status)
    |> filter_jobs_by_origin(origin)
  end

  defp filter_jobs_by_search(jobs, ""), do: jobs

  defp filter_jobs_by_search(jobs, q) do
    lq = String.downcase(q)

    Enum.filter(jobs, fn j ->
      String.contains?(String.downcase(j.name || ""), lq) ||
        String.contains?(String.downcase(j.description || ""), lq)
    end)
  end

  defp filter_jobs_by_type(jobs, "all"), do: jobs
  defp filter_jobs_by_type(jobs, type), do: Enum.filter(jobs, &(&1.job_type == type))

  defp filter_jobs_by_status(jobs, "all"), do: jobs
  defp filter_jobs_by_status(jobs, "enabled"), do: Enum.filter(jobs, &(&1.enabled == 1))
  defp filter_jobs_by_status(jobs, "disabled"), do: Enum.filter(jobs, &(&1.enabled != 1))
  defp filter_jobs_by_status(jobs, _), do: jobs

  defp filter_jobs_by_origin(jobs, "all"), do: jobs
  defp filter_jobs_by_origin(jobs, origin), do: Enum.filter(jobs, &(&1.origin == origin))

  # ---------------------------------------------------------------------------
  # handle_edit_job — scoping_project_id is nil for overview, project_id for project view.
  # When scoped, checks job belongs to the project and sets form_scope.
  # ---------------------------------------------------------------------------

  def handle_edit_job(%{"id" => id}, socket, scoping_project_id \\ nil) do
    with {:ok, int_id} <- parse_job_id(id),
         {:ok, job} <- ScheduledJobs.get_job(int_id) do
      if scoping_project_id && job.project_id != scoping_project_id do
        {:noreply, put_flash(socket, :error, "Access denied")}
      else
        config = ScheduledJobs.decode_config(job)

        socket =
          socket
          |> assign(:show_form, true)
          |> assign(:editing_job, job)
          |> assign(:form, to_form(ScheduledJobs.change_job(job)))
          |> assign(:form_job_type, job.job_type)
          |> assign(:form_schedule_type, job.schedule_type)
          |> assign(:form_config, config)

        socket =
          if scoping_project_id do
            scope = if is_nil(job.project_id), do: "global", else: "project"
            assign(socket, :form_scope, scope)
          else
            socket
          end

        {:noreply, socket}
      end
    else
      :error -> {:noreply, put_flash(socket, :error, "Invalid job ID")}
      {:error, :not_found} -> {:noreply, put_flash(socket, :error, "Job not found")}
    end
  end

  # ---------------------------------------------------------------------------
  # handle_toggle_job — reload_fun is fn socket -> socket.
  # scoping_project_id is nil for overview, project_id for project view.
  # ---------------------------------------------------------------------------

  def handle_toggle_job(%{"id" => id}, socket, reload_fun, scoping_project_id \\ nil) do
    with {:ok, int_id} <- parse_job_id(id),
         {:ok, job} <- ScheduledJobs.get_job(int_id) do
      if scoping_project_id && job.project_id != scoping_project_id do
        {:noreply, put_flash(socket, :error, "Access denied")}
      else
        ScheduledJobs.toggle_job(job, scoping_project_id)
        {:noreply, reload_fun.(socket)}
      end
    else
      :error -> {:noreply, put_flash(socket, :error, "Invalid job ID")}
      {:error, :not_found} -> {:noreply, put_flash(socket, :error, "Job not found")}
    end
  end

  # ---------------------------------------------------------------------------
  # handle_delete_job — reload_fun is fn socket -> socket.
  # scoping_project_id is nil for overview, project_id for project view.
  # ---------------------------------------------------------------------------

  def handle_delete_job(%{"id" => id}, socket, reload_fun, scoping_project_id \\ nil) do
    with {:ok, int_id} <- parse_job_id(id),
         {:ok, job} <- ScheduledJobs.get_job(int_id) do
      if scoping_project_id && job.project_id != scoping_project_id do
        {:noreply, put_flash(socket, :error, "Access denied")}
      else
        case ScheduledJobs.delete_job(job, scoping_project_id) do
          {:ok, _} ->
            {:noreply, socket |> reload_fun.() |> put_flash(:info, "Job deleted")}

          {:error, :system_job} ->
            {:noreply, put_flash(socket, :error, "Cannot delete system jobs")}

          {:error, :unauthorized} ->
            {:noreply, put_flash(socket, :error, "Access denied")}
        end
      end
    else
      :error -> {:noreply, put_flash(socket, :error, "Invalid job ID")}
      {:error, :not_found} -> {:noreply, put_flash(socket, :error, "Job not found")}
    end
  end

  # ---------------------------------------------------------------------------
  # handle_filter_jobs — job_sets is a list of {all_key, filtered_key} tuples.
  # e.g. [{:all_jobs, :jobs}] for overview, or
  #      [{:all_project_jobs, :project_jobs}, {:all_global_jobs, :global_jobs}] for project.
  # ---------------------------------------------------------------------------

  def handle_filter_jobs(params, socket, job_sets) do
    socket =
      socket
      |> assign(:search_query, params["search"] || "")
      |> assign(:filter_type, params["type"] || "all")
      |> assign(:filter_status, params["status"] || "all")
      |> assign(:filter_origin, params["origin"] || "all")

    socket =
      Enum.reduce(job_sets, socket, fn {all_key, filtered_key}, acc ->
        assign(acc, filtered_key, apply_job_filters(acc.assigns[all_key], acc.assigns))
      end)

    {:noreply, socket}
  end

  # ---------------------------------------------------------------------------
  # create_with_claude — shared across overview and project jobs pages
  # opts:
  #   :error_msg       - flash message when project is nil (default: "Project not found")
  #   :prompt_project  - project struct to include in JobHelper.prompt/2 context (default: nil)
  # ---------------------------------------------------------------------------

  def handle_create_with_claude(params, socket, project, opts \\ []) do
    model = params["model"] || "sonnet"
    effort_level = params["effort_level"]
    description = params["description"]
    error_msg = Keyword.get(opts, :error_msg, "Project not found")
    prompt_project = Keyword.get(opts, :prompt_project)

    if is_nil(project) do
      {:noreply, put_flash(socket, :error, error_msg)}
    else
      case AgentManager.create_agent(
             model: model,
             effort_level: effort_level,
             project_id: project.id,
             project_path: project.path,
             description: "Job Helper",
             instructions: JobHelper.prompt(description, project: prompt_project)
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
  end

  # ---------------------------------------------------------------------------
  # save_job — shared across overview and project jobs pages
  # reload_fun: fn socket -> socket — called on success to refresh job lists
  # opts:
  #   :scoping_project_id - when set, adds project_id to attrs (respecting form_scope)
  #                         and passes it as 3rd arg to update_job for auth checks
  # ---------------------------------------------------------------------------

  def handle_save_job(%{"job" => params}, socket, reload_fun, opts \\ []) do
    config = build_config(params)
    scoping_project_id = Keyword.get(opts, :scoping_project_id)

    attrs =
      if scoping_project_id do
        project_id =
          if socket.assigns.form_scope == "global", do: nil, else: scoping_project_id

        params
        |> Map.put("config", Jason.encode!(config))
        |> Map.put("project_id", project_id)
      else
        Map.put(params, "config", Jason.encode!(config))
      end

    result =
      if socket.assigns.editing_job do
        if scoping_project_id do
          ScheduledJobs.update_job(socket.assigns.editing_job, attrs, scoping_project_id)
        else
          ScheduledJobs.update_job(socket.assigns.editing_job, attrs)
        end
      else
        ScheduledJobs.create_job(attrs)
      end

    case result do
      {:ok, _job} ->
        {:noreply,
         socket
         |> assign(:show_form, false)
         |> reload_fun.()
         |> put_flash(:info, "Job saved")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, action: :validate))}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Error: #{inspect(reason)}")}
    end
  end
end
