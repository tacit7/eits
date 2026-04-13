defmodule EyeInTheSky.Workers.WorkableTaskWorkerTest do
  use EyeInTheSky.DataCase, async: true
  use Oban.Testing, repo: EyeInTheSky.Repo

  alias EyeInTheSky.Repo
  alias EyeInTheSky.ScheduledJobs
  alias EyeInTheSky.ScheduledJobs.ScheduledJob
  alias EyeInTheSky.Tasks
  alias EyeInTheSky.Workers.WorkableTaskWorker

  # workable_task is not in the job_type validation enum (it's dispatched via
  # ScheduledJobs.worker_for/1 but not creatable through create_job/1).
  # Insert directly to bypass the changeset validation.
  defp create_workable_job(overrides \\ %{}) do
    now = DateTime.utc_now()

    attrs =
      Map.merge(
        %{
          name: "Test Workable Job",
          job_type: "workable_task",
          schedule_type: "interval",
          schedule_value: "60",
          config: Jason.encode!(%{"tag" => "workable", "model" => "haiku"}),
          created_at: now,
          updated_at: now
        },
        overrides
      )

    Repo.insert!(%ScheduledJob{} |> Map.merge(attrs))
  end

  # Creates a task tagged with tag_name in To Do state (state_id: 1).
  # state_id defaults to nil in create_task/1, so must be explicit here.
  defp create_workable_task(tag_name \\ "workable") do
    {:ok, task} =
      Tasks.create_task(%{title: "Test workable task #{System.unique_integer()}", state_id: 1})

    {:ok, tag} = Tasks.get_or_create_tag(tag_name)
    Tasks.link_tag_to_task(task.id, tag.id)
    task
  end

  describe "perform/1 — no workable tasks" do
    test "returns :ok and records completed run when no tasks are tagged workable" do
      job = create_workable_job()

      assert :ok = perform_job(WorkableTaskWorker, %{"job_id" => job.id})

      runs = ScheduledJobs.list_runs_for_job(job.id)
      assert Enum.any?(runs, &(&1.status == "completed"))
    end

    test "records 'No workable tasks' result when queue is empty" do
      job = create_workable_job()

      :ok = perform_job(WorkableTaskWorker, %{"job_id" => job.id})

      runs = ScheduledJobs.list_runs_for_job(job.id)
      completed = Enum.find(runs, &(&1.status == "completed"))
      assert completed.result =~ "No workable tasks"
    end
  end

  describe "perform/1 — all spawns fail" do
    # MockAgentManager defaults to {:error, :spawn_failed} (configured in test.exs).
    # No Process.put needed — the default covers the all-fail path.

    test "returns {:error, reason} when all task spawns fail" do
      _task = create_workable_task()
      job = create_workable_job()

      assert {:error, _reason} = perform_job(WorkableTaskWorker, %{"job_id" => job.id})
    end

    test "records a failed run when all spawns fail" do
      _task = create_workable_task()
      job = create_workable_job()

      perform_job(WorkableTaskWorker, %{"job_id" => job.id})

      runs = ScheduledJobs.list_runs_for_job(job.id)
      assert Enum.any?(runs, &(&1.status == "failed"))
    end

    test "failed run result contains 'failed' description" do
      _task = create_workable_task()
      job = create_workable_job()

      perform_job(WorkableTaskWorker, %{"job_id" => job.id})

      runs = ScheduledJobs.list_runs_for_job(job.id)
      failed = Enum.find(runs, &(&1.status == "failed"))
      assert failed.result =~ "failed"
    end
  end
end
