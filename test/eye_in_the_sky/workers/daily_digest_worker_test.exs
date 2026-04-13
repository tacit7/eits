defmodule EyeInTheSky.Workers.DailyDigestWorkerTest do
  use EyeInTheSky.DataCase, async: true
  use Oban.Testing, repo: EyeInTheSky.Repo

  alias EyeInTheSky.Events
  alias EyeInTheSky.ScheduledJobs
  alias EyeInTheSky.Workers.DailyDigestWorker

  defp create_digest_job do
    {:ok, job} =
      ScheduledJobs.create_job(%{
        "name" => "Daily Digest Test",
        "job_type" => "daily_digest",
        "schedule_type" => "cron",
        "schedule_value" => "0 8 * * *"
      })

    job
  end

  describe "perform/1 success path" do
    test "broadcasts :jobs_updated to scheduled_jobs subscribers" do
      Events.subscribe_scheduled_jobs()
      job = create_digest_job()

      assert :ok = perform_job(DailyDigestWorker, %{"job_id" => job.id})

      assert_receive :jobs_updated, 2000
    end

    test "records a completed run" do
      job = create_digest_job()

      assert :ok = perform_job(DailyDigestWorker, %{"job_id" => job.id})

      runs = ScheduledJobs.list_runs_for_job(job.id)
      assert Enum.any?(runs, &(&1.status == "completed"))
    end
  end

  # NOTE: Testing the failure-path broadcast (lines 35-37 of the worker) requires
  # mocking Notes.create_note/1 to return {:error, reason}. This project does not
  # have Mox configured, so the failure-path broadcast is verified by code inspection:
  # broadcast() is called immediately before {:error, reason} is returned.
  # Adding Mox would be the correct next step to close this gap.
end
