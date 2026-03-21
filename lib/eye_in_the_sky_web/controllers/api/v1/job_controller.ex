defmodule EyeInTheSkyWeb.Api.V1.JobController do
  use EyeInTheSkyWeb, :controller

  import EyeInTheSkyWeb.ControllerHelpers

  alias EyeInTheSky.ScheduledJobs

  @doc "GET /api/v1/jobs - List all scheduled jobs."
  def index(conn, params) do
    jobs =
      cond do
        params["project_id"] ->
          ScheduledJobs.list_jobs_for_project(parse_int(params["project_id"]))

        params["global"] == "true" ->
          ScheduledJobs.list_global_jobs()

        true ->
          ScheduledJobs.list_jobs()
      end

    json(conn, %{
      success: true,
      count: length(jobs),
      jobs: Enum.map(jobs, &serialize/1)
    })
  end

  @doc "GET /api/v1/jobs/:id - Get a single job."
  def show(conn, %{"id" => id}) do
    case ScheduledJobs.get_job(parse_int(id)) do
      {:ok, job} -> json(conn, serialize(job))
      {:error, :not_found} -> conn |> put_status(:not_found) |> json(%{error: "Job not found"})
    end
  end

  @doc "POST /api/v1/jobs - Create a scheduled job."
  def create(conn, params) do
    attrs = %{
      "name" => params["name"],
      "description" => params["description"],
      "job_type" => params["job_type"],
      "schedule_type" => params["schedule_type"],
      "schedule_value" => params["schedule_value"],
      "config" => encode_config(params["config"]),
      "enabled" => params["enabled"] || 1,
      "project_id" => params["project_id"]
    }

    case ScheduledJobs.create_job(attrs) do
      {:ok, job} ->
        conn |> put_status(:created) |> json(serialize(job))

      {:error, %Ecto.Changeset{} = cs} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "Validation failed", details: translate_errors(cs)})
    end
  end

  @doc "PATCH /api/v1/jobs/:id - Update a job."
  def update(conn, %{"id" => id} = params) do
    case ScheduledJobs.get_job(parse_int(id)) do
      {:ok, job} ->
        attrs =
          params
          |> Map.drop(["id"])
          |> maybe_encode_config()

        case ScheduledJobs.update_job(job, attrs) do
          {:ok, updated} ->
            json(conn, serialize(updated))

          {:error, cs} ->
            conn |> put_status(:unprocessable_entity) |> json(%{error: translate_errors(cs)})
        end

      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Job not found"})
    end
  end

  @doc "DELETE /api/v1/jobs/:id - Delete a job."
  def delete(conn, %{"id" => id}) do
    case ScheduledJobs.get_job(parse_int(id)) do
      {:ok, job} ->
        case ScheduledJobs.delete_job(job) do
          {:ok, _} ->
            json(conn, %{success: true})

          {:error, :system_job} ->
            conn |> put_status(:forbidden) |> json(%{error: "Cannot delete system jobs"})
        end

      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Job not found"})
    end
  end

  @doc "POST /api/v1/jobs/:id/run - Trigger a job immediately."
  def run(conn, %{"id" => id}) do
    case ScheduledJobs.run_now(parse_int(id)) do
      {:ok, _} ->
        json(conn, %{success: true, message: "Job enqueued"})

      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Job not found"})

      {:error, reason} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: inspect(reason)})
    end
  end

  defp serialize(job) do
    %{
      id: job.id,
      name: job.name,
      description: job.description,
      job_type: job.job_type,
      origin: job.origin,
      schedule_type: job.schedule_type,
      schedule_value: job.schedule_value,
      config: ScheduledJobs.decode_config(job),
      enabled: job.enabled,
      project_id: job.project_id,
      last_run_at: job.last_run_at,
      next_run_at: job.next_run_at,
      run_count: job.run_count || 0
    }
  end

  defp encode_config(nil), do: "{}"
  defp encode_config(cfg) when is_map(cfg), do: Jason.encode!(cfg)
  defp encode_config(cfg) when is_binary(cfg), do: cfg

  defp maybe_encode_config(params) do
    case params["config"] do
      cfg when is_map(cfg) -> Map.put(params, "config", Jason.encode!(cfg))
      _ -> params
    end
  end
end
