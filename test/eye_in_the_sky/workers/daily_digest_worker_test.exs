defmodule EyeInTheSky.Workers.DailyDigestWorkerTest do
  use EyeInTheSky.DataCase, async: false
  use Oban.Testing, repo: EyeInTheSky.Repo

  alias EyeInTheSky.Events
  alias EyeInTheSky.ScheduledJobs
  alias EyeInTheSky.Workers.DailyDigestWorker

  defmodule FailingNotes do
    def create_note(_attrs), do: {:error, :forced_test_failure}
  end

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

  describe "perform/1 failure path" do
    setup do
      Application.put_env(:eye_in_the_sky, :notes_module, FailingNotes)
      on_exit(fn -> Application.delete_env(:eye_in_the_sky, :notes_module) end)
    end

    test "broadcasts :jobs_updated even when generate_digest fails" do
      Events.subscribe_scheduled_jobs()
      job = create_digest_job()

      assert {:error, :forced_test_failure} =
               perform_job(DailyDigestWorker, %{"job_id" => job.id})

      assert_receive :jobs_updated, 2000
    end

    test "records a failed run when generate_digest fails" do
      job = create_digest_job()

      perform_job(DailyDigestWorker, %{"job_id" => job.id})

      runs = ScheduledJobs.list_runs_for_job(job.id)
      assert Enum.any?(runs, &(&1.status == "failed"))
    end
  end
end
