defmodule EyeInTheSky.Workers.WorkableTaskWorkerTest do
  use EyeInTheSky.DataCase, async: true
  use Oban.Testing, repo: EyeInTheSky.Repo

  alias EyeInTheSky.Repo
  alias EyeInTheSky.ScheduledJobs
  alias EyeInTheSky.ScheduledJobs.ScheduledJob
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
end
