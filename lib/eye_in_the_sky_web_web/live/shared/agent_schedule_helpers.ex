defmodule EyeInTheSkyWebWeb.Live.Shared.AgentScheduleHelpers do
  @moduledoc """
  Shared event handlers for the Agent Schedules tab.
  Import in OverviewLive.Jobs and ProjectLive.Jobs.
  """

  import Phoenix.Component, only: [assign: 2, assign: 3]
  import Phoenix.LiveView, only: [put_flash: 3]

  alias EyeInTheSkyWeb.{Prompts, ScheduledJobs, Projects}

  @doc "Initialize agent schedule assigns. Call from mount/3."
  def assign_agent_schedule_defaults(socket) do
    assign(socket,
      active_tab: :all_jobs,
      prompts: [],
      prompt_job_map: %{},
      scheduling_prompt: nil,
      scheduling_job: nil,
      orphaned_jobs: [],
      projects: Projects.list_projects()
    )
  end

  def handle_switch_tab(%{"tab" => "agent_schedules"}, socket) do
    {:noreply, socket |> assign(:active_tab, :agent_schedules) |> load_agent_schedule_data()}
  end

  def handle_switch_tab(%{"tab" => "all_jobs"}, socket) do
    {:noreply, assign(socket, :active_tab, :all_jobs)}
  end

  def handle_switch_tab(_, socket), do: {:noreply, socket}

  def handle_schedule_prompt(%{"id" => id}, socket) do
    prompt = Prompts.get_prompt!(String.to_integer(id))
    {:noreply, socket |> assign(:scheduling_prompt, prompt) |> assign(:scheduling_job, nil)}
  end

  def handle_edit_schedule(%{"job_id" => job_id}, socket) do
    job = ScheduledJobs.get_job!(String.to_integer(job_id))
    prompt = if job.prompt_id, do: Prompts.get_prompt!(job.prompt_id), else: nil
    {:noreply, socket |> assign(:scheduling_prompt, prompt) |> assign(:scheduling_job, job)}
  end

  def handle_cancel_schedule(_params, socket) do
    {:noreply, socket |> assign(:scheduling_prompt, nil) |> assign(:scheduling_job, nil)}
  end

  def handle_save_schedule(%{"schedule" => params}, socket) do
    prompt_id = String.to_integer(params["prompt_id"])
    prompt = Prompts.get_prompt!(prompt_id)

    case resolve_project_path(params, prompt, socket) do
      {:error, :no_project} ->
        {:noreply,
         put_flash(socket, :error, "Could not resolve project path. Select a project override.")}

      {:ok, path} ->
        config =
          Jason.encode!(%{
            "prompt_id" => prompt_id,
            "instructions" => prompt.prompt_text,
            "model" => params["model"] || "sonnet",
            "project_path" => path
          })

        job_attrs = %{
          "name" => prompt.name,
          "description" => prompt.description || "",
          "job_type" => "spawn_agent",
          "schedule_type" => params["schedule_type"],
          "schedule_value" => params["schedule_value"],
          "config" => config,
          "prompt_id" => prompt_id,
          "enabled" => 1
        }

        result =
          if params["job_id"] && params["job_id"] != "" do
            job = ScheduledJobs.get_job!(String.to_integer(params["job_id"]))
            ScheduledJobs.update_job(job, job_attrs)
          else
            ScheduledJobs.create_job(job_attrs)
          end

        case result do
          {:ok, _} ->
            {:noreply,
             socket
             |> assign(:scheduling_prompt, nil)
             |> assign(:scheduling_job, nil)
             |> load_agent_schedule_data()
             |> put_flash(:info, "Schedule saved")}

          {:error, :already_scheduled} ->
            {:noreply, put_flash(socket, :error, "This agent already has a schedule")}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, "Failed to save schedule")}
        end
    end
  end

  @doc "Call from handle_info(:jobs_updated) to refresh data when tab is active."
  def maybe_reload_agent_schedule_data(socket) do
    if socket.assigns.active_tab == :agent_schedules do
      load_agent_schedule_data(socket)
    else
      socket
    end
  end

  # ---------------------------------------------------------------------------
  # Private
  # ---------------------------------------------------------------------------

  defp load_agent_schedule_data(socket) do
    prompts = load_prompts_for_context(socket)
    prompt_ids = Enum.map(prompts, & &1.id)
    jobs = ScheduledJobs.list_spawn_agent_jobs_by_prompt_ids(prompt_ids)
    prompt_job_map = Map.new(jobs, fn j -> {j.prompt_id, j} end)
    orphaned_jobs = ScheduledJobs.list_orphaned_agent_jobs()

    assign(socket,
      prompts: prompts,
      prompt_job_map: prompt_job_map,
      orphaned_jobs: orphaned_jobs
    )
  end

  defp load_prompts_for_context(socket) do
    case Map.get(socket.assigns, :project_id) do
      nil -> Prompts.list_global_prompts()
      project_id -> Prompts.list_prompts(project_id: project_id)
    end
  end

  # 4-step resolution: form override -> prompt default -> page context -> error
  defp resolve_project_path(params, prompt, socket) do
    override_id = params["project_override_id"]

    cond do
      override_id && override_id != "" ->
        project = Projects.get_project(String.to_integer(override_id))
        if project && project.path, do: {:ok, project.path}, else: {:error, :no_project}

      prompt.project_id ->
        project = Projects.get_project(prompt.project_id)
        if project && project.path, do: {:ok, project.path}, else: {:error, :no_project}

      project_id = Map.get(socket.assigns, :project_id) ->
        project = Projects.get_project(project_id)
        if project && project.path, do: {:ok, project.path}, else: {:error, :no_project}

      true ->
        {:error, :no_project}
    end
  end
end
