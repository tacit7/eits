defmodule EyeInTheSky.Workers.MixTaskWorkerTest do
  use EyeInTheSky.DataCase, async: true
  use Oban.Testing, repo: EyeInTheSky.Repo

  alias EyeInTheSky.ScheduledJobs
  alias EyeInTheSky.Workers.MixTaskWorker

  defp create_mix_job(task, args \\ []) do
    {:ok, job} =
      ScheduledJobs.create_job(%{
        "name" => "Test Mix Job",
        "job_type" => "mix_task",
        "schedule_type" => "interval",
        "schedule_value" => "60",
        "config" => Jason.encode!(%{"task" => task, "args" => args, "project_path" => "/tmp"})
      })

    job
  end

  describe "perform/1 allowlist" do
    test "allows whitelisted task: help" do
      job = create_mix_job("help")
      assert :ok = perform_job(MixTaskWorker, %{"job_id" => job.id})
    end

    test "rejects unknown task with error" do
      job = create_mix_job("cmd")
      assert {:error, _reason} = perform_job(MixTaskWorker, %{"job_id" => job.id})
    end

    test "records failed run on disallowed task" do
      job = create_mix_job("eval")
      perform_job(MixTaskWorker, %{"job_id" => job.id})

      runs = ScheduledJobs.list_runs_for_job(job.id)
      assert Enum.any?(runs, &(&1.status == "failed"))
    end
  end
end
