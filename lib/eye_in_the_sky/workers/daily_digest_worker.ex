defmodule EyeInTheSky.Workers.DailyDigestWorker do
  @moduledoc """
  Oban worker that generates a daily digest of the past 24 hours:
  sessions active, tasks completed, commits merged.
  Saves the result as a system note and broadcasts via PubSub.
  """

  use Oban.Worker, queue: :jobs, max_attempts: 3

  require Logger

  import Ecto.Query, warn: false

  alias EyeInTheSky.{Notifications, Repo, ScheduledJobs, Tasks}

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"job_id" => job_id}}) do
    job = ScheduledJobs.get_job!(job_id)
    {:ok, run} = ScheduledJobs.record_run_start(job)

    case generate_digest() do
      {:ok, note} ->
        ScheduledJobs.record_run_complete(run, "completed", result: "Note #{note.id} created")

        Notifications.notify("Daily Digest ready",
          category: :job,
          body: note.title,
          resource: {"note", note.id}
        )

        EyeInTheSky.Events.jobs_updated()
        :ok

      {:error, reason} ->
        ScheduledJobs.record_run_complete(run, "failed", result: inspect(reason))
        EyeInTheSky.Events.jobs_updated()
        {:error, reason}
    end
  end

  defp generate_digest do
    since = DateTime.add(DateTime.utc_now(), -86_400, :second)
    date_label = Date.utc_today() |> Date.to_string()

    sessions = fetch_sessions(since)
    tasks = fetch_completed_tasks(since)
    commits = fetch_commits(since)

    body = format_digest(date_label, sessions, tasks, commits)

    case Application.get_env(:eye_in_the_sky, :digest_desktop_path) do
      nil ->
        :ok

      dir ->
        path = Path.join(dir, "daily-digest-#{date_label}.md")

        case File.write(path, body) do
          :ok ->
            Logger.info("DailyDigestWorker: wrote #{path}")

          {:error, reason} ->
            Logger.error("DailyDigestWorker: failed to write digest: #{inspect(reason)}")
        end
    end

    notes_mod = Application.get_env(:eye_in_the_sky, :notes_module, EyeInTheSky.Notes)

    notes_mod.create_note(%{
      title: "Daily Digest — #{date_label}",
      body: body,
      parent_type: "system",
      parent_id: "digest"
    })
  end

  defp fetch_sessions(since) do
    Repo.all(
      from s in "sessions",
        left_join: p in "projects",
        on: p.id == s.project_id,
        where: s.started_at >= ^since,
        select: %{
          name: s.name,
          status: s.status,
          project: p.name,
          started_at: s.started_at,
          ended_at: s.ended_at
        },
        order_by: [desc: s.started_at],
        limit: 200
    )
  end

  defp fetch_completed_tasks(since) do
    state_done = Tasks.state_done()

    Repo.all(
      from t in "tasks",
        left_join: p in "projects",
        on: p.id == t.project_id,
        where: t.state_id == ^state_done and t.updated_at >= ^since,
        select: %{title: t.title, project: p.name},
        order_by: [asc: t.title],
        limit: 200
    )
  end

  defp fetch_commits(since) do
    Repo.all(
      from c in "commits",
        left_join: s in "sessions",
        on: s.id == c.session_id,
        where: c.created_at >= ^since,
        select: %{
          hash: c.commit_hash,
          message: c.commit_message,
          session: s.name
        },
        order_by: [desc: c.created_at],
        limit: 200
    )
  end

  defp format_digest(date, sessions, tasks, commits) do
    """
    # Daily Digest — #{date}

    ## Sessions (#{length(sessions)})
    #{format_sessions(sessions)}

    ## Tasks Completed (#{length(tasks)})
    #{format_tasks(tasks)}

    ## Commits (#{length(commits)})
    #{format_commits(commits)}
    """
    |> String.trim()
  end

  defp format_sessions([]), do: "_No sessions in the last 24 hours._"

  defp format_sessions(sessions) do
    Enum.map_join(sessions, "\n", fn s ->
      project = s.project || "—"
      status = s.status || "unknown"
      name = s.name || "Unnamed"
      "- **#{name}** (#{project}) — #{status}"
    end)
  end

  defp format_tasks([]), do: "_No tasks completed in the last 24 hours._"

  defp format_tasks(tasks) do
    Enum.map_join(tasks, "\n", fn t ->
      project = t.project || "—"
      "- #{t.title} _(#{project})_"
    end)
  end

  defp format_commits([]), do: "_No commits in the last 24 hours._"

  defp format_commits(commits) do
    Enum.map_join(commits, "\n", fn c ->
      hash = String.slice(c.hash || "", 0, 7)
      msg = c.message |> String.split("\n") |> List.first() || ""
      session = c.session || "—"
      "- `#{hash}` #{msg} _(#{session})_"
    end)
  end
end
