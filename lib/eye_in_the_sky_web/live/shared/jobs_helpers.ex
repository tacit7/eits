defmodule EyeInTheSkyWeb.Live.Shared.JobsHelpers do
  import Phoenix.Component, only: [assign: 2, assign: 3, to_form: 1, to_form: 2]
  import Phoenix.LiveView, only: [put_flash: 3, push_navigate: 2]
  import EyeInTheSkyWeb.ControllerHelpers, only: [parse_int: 2]

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
    if n = parse_int(id, nil), do: {:ok, n}, else: :error
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
  # Config builder
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
  # Last-failed-run helpers
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
    with_scoped_job(id, socket, scoping_project_id, fn job ->
      {:noreply, setup_edit_form(socket, job, scoping_project_id)}
    end)
  end

  defp setup_edit_form(socket, job, scoping_project_id) do
    config = ScheduledJobs.decode_config(job)

    socket =
      socket
      |> assign(:show_form, true)
      |> assign(:editing_job, job)
      |> assign(:form, to_form(ScheduledJobs.change_job(job)))
      |> assign(:form_job_type, job.job_type)
      |> assign(:form_schedule_type, job.schedule_type)
      |> assign(:form_config, config)

    if scoping_project_id do
      scope = if is_nil(job.project_id), do: "global", else: "project"
      assign(socket, :form_scope, scope)
    else
      socket
    end
  end

  # ---------------------------------------------------------------------------
  # handle_toggle_job — reload_fun is fn socket -> socket.
  # scoping_project_id is nil for overview, project_id for project view.
  # ---------------------------------------------------------------------------

  def handle_toggle_job(%{"id" => id}, socket, reload_fun, scoping_project_id \\ nil) do
    with_scoped_job(id, socket, scoping_project_id, fn job ->
      ScheduledJobs.toggle_job(job, scoping_project_id)
      {:noreply, reload_fun.(socket)}
    end)
  end

  # ---------------------------------------------------------------------------
  # handle_delete_job — reload_fun is fn socket -> socket.
  # scoping_project_id is nil for overview, project_id for project view.
  # ---------------------------------------------------------------------------

  def handle_delete_job(%{"id" => id}, socket, reload_fun, scoping_project_id \\ nil) do
    with_scoped_job(id, socket, scoping_project_id, fn job ->
      case ScheduledJobs.delete_job(job, scoping_project_id) do
        {:ok, _} ->
          {:noreply, socket |> reload_fun.() |> put_flash(:info, "Job deleted")}

        {:error, :system_job} ->
          {:noreply, put_flash(socket, :error, "Cannot delete system jobs")}

        {:error, :unauthorized} ->
          {:noreply, put_flash(socket, :error, "Access denied")}
      end
    end)
  end

  # Resolves a job by ID, enforces project scoping, then calls fun.(job).
  # Returns {:noreply, socket} with an error flash if the ID is invalid,
  # the job is not found, or the job belongs to a different project.
  defp with_scoped_job(id, socket, scoping_project_id, fun) do
    with {:ok, int_id} <- parse_job_id(id),
         {:ok, job} <- ScheduledJobs.get_job(int_id) do
      if scoping_project_id && job.project_id != scoping_project_id do
        {:noreply, put_flash(socket, :error, "Access denied")}
      else
        fun.(job)
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
             instructions: JobHelper.prompt(description, project: prompt_project),
             agent: "cron-job-builder"
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
