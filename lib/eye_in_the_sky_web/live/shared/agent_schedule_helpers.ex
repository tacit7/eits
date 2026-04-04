defmodule EyeInTheSkyWeb.Live.Shared.AgentScheduleHelpers do
  @moduledoc """
  Shared event handlers for the Schedule Agents tab.
  Import in OverviewLive.Jobs and ProjectLive.Jobs.
  """

  import Phoenix.Component, only: [assign: 2, assign: 3]
  import Phoenix.LiveView, only: [put_flash: 3]
  import EyeInTheSkyWeb.Live.Shared.JobsHelpers, only: [parse_job_id: 1]
  import EyeInTheSkyWeb.ControllerHelpers, only: [parse_int: 1]

  alias EyeInTheSky.{Prompts, ScheduledJobs, Projects}
  alias EyeInTheSky.Claude.AgentFileScanner

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
    prompt = resolve_prompt(id, socket)
    {:noreply, socket |> assign(:scheduling_prompt, prompt) |> assign(:scheduling_job, nil)}
  end

  def handle_edit_schedule(%{"job_id" => job_id}, socket) do
    with {:ok, int_id} <- parse_job_id(job_id),
         {:ok, job} <- ScheduledJobs.get_job(int_id) do
      if not job_accessible?(job, socket) do
        {:noreply, put_flash(socket, :error, "Access denied")}
      else
        prompt =
          cond do
            job.prompt_id ->
              Prompts.get_prompt!(job.prompt_id)

            agent_file_id = get_config_field(job, "agent_file_id") ->
              AgentFileScanner.get_by_id(agent_file_id)

            true ->
              nil
          end

        {:noreply, socket |> assign(:scheduling_prompt, prompt) |> assign(:scheduling_job, job)}
      end
    else
      :error ->
        {:noreply, put_flash(socket, :error, "Invalid job ID")}

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "Job not found")}
    end
  end

  def handle_cancel_schedule(_params, socket) do
    {:noreply, socket |> assign(:scheduling_prompt, nil) |> assign(:scheduling_job, nil)}
  end

  def handle_save_schedule(%{"schedule" => params}, socket) do
    prompt_id_raw = params["prompt_id"]
    is_fs = AgentFileScanner.filesystem_id?(prompt_id_raw)
    prompt = resolve_prompt(prompt_id_raw, socket)

    unless prompt do
      {:noreply, put_flash(socket, :error, "Agent not found")}
    else
      case resolve_project_path(params, prompt, socket) do
        {:error, :no_project} ->
          {:noreply,
           put_flash(socket, :error, "Could not resolve project path. Select a project override.")}

        {:ok, path} ->
          config =
            %{
              "instructions" => prompt.prompt_text,
              "model" => params["model"] || "sonnet",
              "project_path" => path
            }
            |> then(fn c ->
              if is_fs do
                Map.put(c, "agent_file_id", prompt_id_raw)
              else
                case parse_int(prompt_id_raw) do
                  nil -> c
                  int_id -> Map.put(c, "prompt_id", int_id)
                end
              end
            end)
            |> put_if_present("max_budget_usd", params["max_budget_usd"])
            |> put_if_present("max_turns", params["max_turns"])
            |> put_if_present("fallback_model", params["fallback_model"])
            |> put_if_present("allowed_tools", params["allowed_tools"])
            |> put_if_present("output_format", params["output_format"])
            |> Map.put("skip_permissions", params["skip_permissions"] == "true")
            |> put_if_present("permission_mode", params["permission_mode"])
            |> put_if_present("add_dir", params["add_dir"])
            |> put_if_present("mcp_config", params["mcp_config"])
            |> put_if_present("plugin_dir", params["plugin_dir"])
            |> put_if_present("settings_file", params["settings_file"])
            |> put_bool_if_true("chrome", params["chrome"])
            |> put_bool_if_true("sandbox", params["sandbox"])
            |> Jason.encode!()

          job_attrs =
            %{
              "name" => prompt.name,
              "description" => prompt.description || "",
              "job_type" => "spawn_agent",
              "schedule_type" => params["schedule_type"],
              "schedule_value" => params["schedule_value"],
              "config" => config,
              "prompt_id" => if(is_fs, do: nil, else: parse_int(prompt_id_raw)),
              "enabled" => 1
            }
            |> put_if_present("timezone", params["timezone"])

          caller_project_id = Map.get(socket.assigns, :project_id)

          result =
            if params["job_id"] && params["job_id"] != "" do
              case parse_job_id(params["job_id"]) do
                :error ->
                  {:error, :invalid_id}

                {:ok, int_id} ->
                  case ScheduledJobs.get_job(int_id) do
                    {:error, :not_found} -> {:error, :not_found}
                    {:ok, job} ->
                      if not job_accessible?(job, socket) do
                        {:error, :access_denied}
                      else
                        ScheduledJobs.update_job(job, job_attrs, caller_project_id)
                      end
                  end
              end
            else
              attrs = if caller_project_id, do: Map.put(job_attrs, "project_id", caller_project_id), else: job_attrs
              ScheduledJobs.create_job(attrs)
            end

          case result do
            {:ok, _} ->
              {:noreply,
               socket
               |> assign(:scheduling_prompt, nil)
               |> assign(:scheduling_job, nil)
               |> load_agent_schedule_data()
               |> put_flash(:info, "Schedule saved")}

            {:error, :not_found} ->
              {:noreply, put_flash(socket, :error, "Job not found")}

            {:error, :invalid_id} ->
              {:noreply, put_flash(socket, :error, "Invalid job ID")}

            {:error, :access_denied} ->
              {:noreply, put_flash(socket, :error, "Access denied")}

            {:error, :already_scheduled} ->
              {:noreply, put_flash(socket, :error, "This agent already has a schedule")}

            {:error, _} ->
              {:noreply, put_flash(socket, :error, "Failed to save schedule")}
          end
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
    db_prompts = load_prompts_for_context(socket)
    fs_agents = load_filesystem_agents(socket)

    # Merge: DB prompts first, then filesystem agents (deduplicate by name)
    seen_names = MapSet.new(db_prompts, & &1.name)
    prompts = db_prompts ++ Enum.reject(fs_agents, &MapSet.member?(seen_names, &1.name))

    # Build prompt_job_map for DB prompts (keyed by integer prompt_id)
    db_prompt_ids = db_prompts |> Enum.map(& &1.id) |> Enum.filter(&is_integer/1)
    db_jobs = ScheduledJobs.list_spawn_agent_jobs_by_prompt_ids(db_prompt_ids)
    db_job_map = Map.new(db_jobs, fn j -> {j.prompt_id, j} end)

    # Build prompt_job_map for filesystem agents (keyed by "fs:..." string)
    fs_jobs = ScheduledJobs.list_filesystem_agent_jobs()

    fs_job_map =
      Map.new(fs_jobs, fn j ->
        agent_file_id = get_config_field(j, "agent_file_id")
        {agent_file_id, j}
      end)

    prompt_job_map = Map.merge(db_job_map, fs_job_map)
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

  defp load_filesystem_agents(socket) do
    project_path = resolve_context_project_path(socket)
    AgentFileScanner.scan(project_path)
  end

  defp resolve_context_project_path(socket) do
    case Map.get(socket.assigns, :project_id) do
      nil ->
        nil

      project_id ->
        case Projects.get_project(project_id) do
          nil -> nil
          project -> project.path
        end
    end
  end

  defp resolve_prompt(id, _socket) do
    cond do
      is_nil(id) || id == "" ->
        nil

      AgentFileScanner.filesystem_id?(id) ->
        AgentFileScanner.get_by_id(id)

      true ->
        case parse_int(id) do
          nil -> nil
          int_id -> Prompts.get_prompt(int_id)
        end
    end
  end

  # A job is accessible from a project-scoped page only if it belongs to that exact project.
  # Global jobs (project_id nil) are blocked from project pages. No restriction from the
  # overview page (no project_id in assigns).
  defp job_accessible?(job, socket) do
    case Map.get(socket.assigns, :project_id) do
      nil -> true
      project_id -> job.project_id == project_id
    end
  end

  defp get_config_field(job, field) do
    case Jason.decode(job.config || "{}") do
      {:ok, config} -> Map.get(config, field)
      _ -> nil
    end
  end

  defp put_if_present(map, _key, nil), do: map
  defp put_if_present(map, _key, ""), do: map
  defp put_if_present(map, key, val), do: Map.put(map, key, val)

  defp put_bool_if_true(map, key, "true"), do: Map.put(map, key, true)
  defp put_bool_if_true(map, _key, _), do: map

  # 4-step resolution: form override -> prompt default -> page context -> error
  defp resolve_project_path(params, prompt, socket) do
    override_id = params["project_override_id"]

    cond do
      override_id && override_id != "" ->
        case parse_int(override_id) do
          nil ->
            {:error, :no_project}

          int_id ->
            project = Projects.get_project(int_id)
            if project && project.path, do: {:ok, project.path}, else: {:error, :no_project}
        end

      prompt[:project_id] || Map.get(prompt, :project_id) ->
        pid = prompt[:project_id] || Map.get(prompt, :project_id)
        project = Projects.get_project(pid)
        if project && project.path, do: {:ok, project.path}, else: {:error, :no_project}

      project_id = Map.get(socket.assigns, :project_id) ->
        project = Projects.get_project(project_id)
        if project && project.path, do: {:ok, project.path}, else: {:error, :no_project}

      true ->
        {:error, :no_project}
    end
  end
end
