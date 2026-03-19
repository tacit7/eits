defmodule EyeInTheSkyWeb.Workers.WorkableTaskWorker do
  @moduledoc """
  Oban worker for the `workable_task` job type.

  Queries tasks tagged with a configured tag name, moves each to In Progress,
  then spawns a Claude agent per task via AgentManager (SDK path).

  Config keys:
    - "tag"   — tag name to query (e.g. "workable" or "workable-sonnet")
    - "model" — Claude model to use (e.g. "haiku" or "sonnet")
  """

  use Oban.Worker, queue: :jobs, max_attempts: 3

  require Logger

  alias EyeInTheSkyWeb.{Repo, ScheduledJobs, Tasks}
  alias EyeInTheSkyWeb.Agents.AgentManager
  alias EyeInTheSkyWeb.Notifications
  alias EyeInTheSkyWeb.Workers.SpeakWorker

  import Ecto.Query

  # Max tasks to spawn per run (prevents API concurrency overload)
  @batch_limit 3
  # Skip spawning if this many agents are already active
  @max_active_agents 8

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"job_id" => job_id}}) do
    job = ScheduledJobs.get_job!(job_id)
    {:ok, run} = ScheduledJobs.record_run_start(job)

    case execute(job) do
      {:ok, :no_work} ->
        ScheduledJobs.record_run_complete(run, "completed", result: "No workable tasks")
        broadcast()
        :ok

      {:ok, output} ->
        ScheduledJobs.record_run_complete(run, "completed", result: output)
        broadcast()
        notify(output)
        :ok

      {:error, reason} ->
        ScheduledJobs.record_run_complete(run, "failed", result: reason)
        broadcast()
        notify_error(reason)
        {:error, reason}
    end
  end

  defp execute(job) do
    config = ScheduledJobs.decode_config(job)
    tag_name = config["tag"] || "workable"
    model = config["model"] || "haiku"

    active_count = count_active_agents()

    if active_count >= @max_active_agents do
      {:ok, :no_work}
    else
      available_slots = @max_active_agents - active_count
      limit = min(@batch_limit, available_slots)

      tasks = fetch_workable_tasks(tag_name, limit, job.project_id)

      if tasks == [] do
        {:ok, :no_work}
      else
        results =
          Enum.map(tasks, fn task ->
            mark_in_progress(task.id)
            result = spawn_agent(task, model, job.project_id)

            if match?({:error, _}, result) do
              Logger.warning(
                "WorkableTaskWorker: spawn failed for task ##{task.id}, rolling back to To Do"
              )

              reset_to_todo(task.id)
            end

            result
          end)

        spawned = Enum.count(results, &match?({:ok, _}, &1))
        failed = Enum.count(results, &match?({:error, _}, &1))

        {:ok, "Spawned #{spawned} agents for tag=#{tag_name} (#{failed} failed)"}
      end
    end
  rescue
    e -> {:error, Exception.message(e)}
  end

  defp count_active_agents do
    Repo.one(
      from s in "sessions",
        join: a in "agents",
        on: a.id == s.agent_id,
        where: a.status == "working",
        select: count(s.id)
    ) || 0
  end

  defp fetch_workable_tasks(tag_name, limit, project_id) do
    state_todo = Tasks.state_todo()

    base_query =
      from t in "tasks",
        join: tt in "task_tags",
        on: tt.task_id == t.id,
        join: tg in "tags",
        on: tg.id == tt.tag_id,
        where: tg.name == ^tag_name and t.state_id == ^state_todo,
        order_by: [desc: t.priority, asc: t.id],
        limit: ^limit,
        select: %{
          id: t.id,
          title: t.title,
          description: t.description,
          project_id: t.project_id
        }

    query =
      if project_id do
        from t in base_query, where: t.project_id == ^project_id
      else
        base_query
      end

    Repo.all(query)
  end

  defp mark_in_progress(task_id) do
    Repo.update_all(
      from(t in "tasks", where: t.id == ^task_id),
      set: [state_id: Tasks.state_in_progress()]
    )
  end

  defp reset_to_todo(task_id) do
    Repo.update_all(
      from(t in "tasks", where: t.id == ^task_id),
      set: [state_id: Tasks.state_todo()]
    )
  end

  defp spawn_agent(task, model, job_project_id) do
    project_id = task.project_id || job_project_id

    project_path =
      case project_id && Repo.get(EyeInTheSkyWeb.Projects.Project, project_id) do
        %{path: path} when is_binary(path) -> path
        _ -> File.cwd!()
      end

    instructions = """
    You are working on task ##{task.id}: #{task.title}

    #{task.description}

    When done, move the task to In Review. Use the appropriate method for your entrypoint:
    - sdk-cli entrypoint: EITS-CMD: task annotate #{task.id} <summary>
                          EITS-CMD: task done #{task.id}
    - cli entrypoint:     eits tasks annotate #{task.id} --body "<summary>"
                          eits tasks update #{task.id} --state 4
    """

    opts = [
      model: model,
      project_id: project_id,
      project_path: project_path,
      description: "Task ##{task.id}: #{task.title}",
      instructions: instructions
    ]

    case AgentManager.create_agent(opts) do
      {:ok, %{session: session}} ->
        Logger.info(
          "WorkableTaskWorker: spawned agent for task ##{task.id} session=#{session.uuid} project_path=#{project_path}"
        )

        Tasks.link_session_to_task(task.id, session.id)

        {:ok, task.id}

      {:error, reason} ->
        Logger.error(
          "WorkableTaskWorker: failed to spawn agent for task ##{task.id} project_path=#{project_path} - #{inspect(reason)}"
        )

        {:error, reason}
    end
  end

  defp broadcast do
    EyeInTheSkyWeb.Events.jobs_updated()
  end

  defp notify(output) do
    Notifications.notify(output, category: :agent)

    %{"message" => output, "voice" => "Ava"}
    |> SpeakWorker.new()
    |> Oban.insert()
  end

  defp notify_error(reason) do
    message = "Workable task worker failed: #{reason}"

    %{"message" => message, "voice" => "Ava"}
    |> SpeakWorker.new()
    |> Oban.insert()
  end
end
