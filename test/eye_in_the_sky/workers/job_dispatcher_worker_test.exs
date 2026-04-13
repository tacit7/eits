defmodule EyeInTheSky.Workers.JobDispatcherWorkerTest do
  use EyeInTheSky.DataCase, async: true
  use Oban.Testing, repo: EyeInTheSky.Repo

  alias EyeInTheSky.ScheduledJobs
  alias EyeInTheSky.Workers.JobDispatcherWorker

  defp job_attrs(overrides \\ %{}) do
    Map.merge(
      %{
        "name" => "Dispatch Test Job",
        "job_type" => "shell_command",
        "schedule_type" => "interval",
        "schedule_value" => "60",
        "config" => Jason.encode!(%{"command" => "echo hi", "working_dir" => "/tmp"})
      },
      overrides
    )
  end

  defp make_due(job) do
    ScheduledJobs.update_job(job, %{"next_run_at" => "2000-01-01T00:00:00Z"})
  end

  describe "perform/1" do
    test "enqueues Oban jobs for all due jobs" do
      {:ok, job} = ScheduledJobs.create_job(job_attrs())
      {:ok, job} = make_due(job)

      assert :ok = perform_job(JobDispatcherWorker, %{})

      assert_enqueued(
        worker: EyeInTheSky.Workers.ShellCommandWorker,
        args: %{"job_id" => job.id}
      )
    end

    test "advances next_run_at after dispatching" do
      {:ok, job} = ScheduledJobs.create_job(job_attrs())
      {:ok, job} = make_due(job)
      original_next = job.next_run_at

      :ok = perform_job(JobDispatcherWorker, %{})

      {:ok, updated} = ScheduledJobs.get_job(job.id)
      assert updated.next_run_at != original_next
    end

    test "does not enqueue disabled jobs" do
      {:ok, job} = ScheduledJobs.create_job(job_attrs())
      {:ok, job} = make_due(job)
      ScheduledJobs.toggle_job(job)

      :ok = perform_job(JobDispatcherWorker, %{})

      refute_enqueued(
        worker: EyeInTheSky.Workers.ShellCommandWorker,
        args: %{"job_id" => job.id}
      )
    end

    test "does not enqueue jobs with future next_run_at" do
      {:ok, job} = ScheduledJobs.create_job(job_attrs())

      :ok = perform_job(JobDispatcherWorker, %{})

      refute_enqueued(
        worker: EyeInTheSky.Workers.ShellCommandWorker,
        args: %{"job_id" => job.id}
      )
    end

    test "enqueues correct worker for spawn_agent job type" do
      {:ok, job} =
        ScheduledJobs.create_job(
          job_attrs(%{
            "job_type" => "spawn_agent",
            "config" =>
              Jason.encode!(%{
                "instructions" => "do stuff",
                "model" => "sonnet",
                "project_path" => "/tmp",
                "description" => "test agent"
              })
          })
        )

      {:ok, _} = make_due(job)

      :ok = perform_job(JobDispatcherWorker, %{})

      assert_enqueued(
        worker: EyeInTheSky.Workers.SpawnAgentWorker,
        args: %{"job_id" => job.id}
      )
    end

    test "enqueues correct worker for mix_task job type" do
      {:ok, job} =
        ScheduledJobs.create_job(
          job_attrs(%{
            "job_type" => "mix_task",
            "config" =>
              Jason.encode!(%{
                "task" => "help",
                "args" => [],
                "project_path" => "/tmp"
              })
          })
        )

      {:ok, _} = make_due(job)

      :ok = perform_job(JobDispatcherWorker, %{})

      assert_enqueued(worker: EyeInTheSky.Workers.MixTaskWorker, args: %{"job_id" => job.id})
    end

    test "handles multiple due jobs in one pass" do
      {:ok, job1} = ScheduledJobs.create_job(job_attrs(%{"name" => "Job 1"}))
      {:ok, job2} = ScheduledJobs.create_job(job_attrs(%{"name" => "Job 2"}))
      {:ok, _} = make_due(job1)
      {:ok, _} = make_due(job2)

      :ok = perform_job(JobDispatcherWorker, %{})

      assert_enqueued(
        worker: EyeInTheSky.Workers.ShellCommandWorker,
        args: %{"job_id" => job1.id}
      )

      assert_enqueued(
        worker: EyeInTheSky.Workers.ShellCommandWorker,
        args: %{"job_id" => job2.id}
      )
    end

    test "returns :ok even when no due jobs exist" do
      assert :ok = perform_job(JobDispatcherWorker, %{})
    end
  end
end
