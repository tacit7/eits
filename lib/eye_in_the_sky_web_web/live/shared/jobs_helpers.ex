defmodule EyeInTheSkyWebWeb.Live.Shared.JobsHelpers do
  import Phoenix.Component, only: [assign: 2, assign: 3]
  import Phoenix.LiveView, only: [put_flash: 3]
  import EyeInTheSkyWebWeb.ControllerHelpers, only: [parse_int: 2]

  alias EyeInTheSkyWeb.ScheduledJobs

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

  def handle_expand_job(%{"id" => id}, socket) do
    job_id = String.to_integer(id)

    if socket.assigns.expanded_job_id == job_id do
      {:noreply, assign(socket, expanded_job_id: nil, runs: [])}
    else
      runs = ScheduledJobs.list_runs_for_job(job_id)
      {:noreply, assign(socket, expanded_job_id: job_id, runs: runs)}
    end
  end

  def handle_run_now(%{"id" => id}, socket) do
    ScheduledJobs.run_now(String.to_integer(id))
    {:noreply, put_flash(socket, :info, "Job triggered")}
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

  def month_name("1"), do: "Jan"
  def month_name("2"), do: "Feb"
  def month_name("3"), do: "Mar"
  def month_name("4"), do: "Apr"
  def month_name("5"), do: "May"
  def month_name("6"), do: "Jun"
  def month_name("7"), do: "Jul"
  def month_name("8"), do: "Aug"
  def month_name("9"), do: "Sep"
  def month_name("10"), do: "Oct"
  def month_name("11"), do: "Nov"
  def month_name("12"), do: "Dec"
  def month_name(m), do: m

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

  # Returns relative time string: "in 12 minutes", "3 hours ago", etc.
  def format_relative_time(nil), do: "-"

  def format_relative_time(iso) when is_binary(iso) do
    with cleaned <- String.replace(iso, "Z", ""),
         {:ok, ndt} <- NaiveDateTime.from_iso8601(cleaned) do
      now = NaiveDateTime.utc_now()
      diff = NaiveDateTime.diff(ndt, now, :second)
      format_relative_diff(diff)
    else
      _ -> "-"
    end
  end

  defp format_relative_diff(secs) when secs > 0 do
    cond do
      secs < 60 -> "in #{secs}s"
      secs < 3600 -> "in #{div(secs, 60)}m"
      secs < 86_400 -> "in #{div(secs, 3600)}h"
      true -> "in #{div(secs, 86_400)}d"
    end
  end

  defp format_relative_diff(secs) do
    abs_secs = abs(secs)

    cond do
      abs_secs < 60 -> "#{abs_secs}s ago"
      abs_secs < 3600 -> "#{div(abs_secs, 60)}m ago"
      abs_secs < 86_400 -> "#{div(abs_secs, 3600)}h ago"
      true -> "#{div(abs_secs, 86_400)}d ago"
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
end
