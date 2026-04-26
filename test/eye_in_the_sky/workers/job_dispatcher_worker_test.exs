defmodule EyeInTheSky.Workers.JobDispatcherWorkerTest do
  use EyeInTheSky.DataCase, async: true
  use Oban.Testing, repo: EyeInTheSky.Repo

  alias EyeInTheSky.ScheduledJobs
  alias EyeInTheSky.Workers.JobDispatcherWorker

  defp job_attrs(overrides \\ %{}) do
    Map.merge(
      %{
        "name" => "Dispatch Test Job",
        "job_type" => "mix_task",
        "schedule_type" => "interval",
        "schedule_value" => "60",
        "config" => Jason.encode!(%{"task" => "help", "args" => [], "project_path" => "/tmp"})
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
        worker: EyeInTheSky.Workers.MixTaskWorker,
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
        worker: EyeInTheSky.Workers.MixTaskWorker,
        args: %{"job_id" => job.id}
      )
    end

    test "does not enqueue jobs with future next_run_at" do
      {:ok, job} = ScheduledJobs.create_job(job_attrs())

      :ok = perform_job(JobDispatcherWorker, %{})

      refute_enqueued(
        worker: EyeInTheSky.Workers.MixTaskWorker,
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
        worker: EyeInTheSky.Workers.MixTaskWorker,
        args: %{"job_id" => job1.id}
      )

      assert_enqueued(
        worker: EyeInTheSky.Workers.MixTaskWorker,
        args: %{"job_id" => job2.id}
      )
    end

    test "returns :ok even when no due jobs exist" do
      assert :ok = perform_job(JobDispatcherWorker, %{})
    end
  end

  # ---------------------------------------------------------------------------
  # Atomic claim and enqueue-failure handling
  # ---------------------------------------------------------------------------

  defp workable_job_attrs(overrides \\ %{}) do
    Map.merge(
      %{
        "name" => "Workable Claim Test",
        "job_type" => "workable_task",
        "schedule_type" => "interval",
        "schedule_value" => "60"
      },
      overrides
    )
  end

  defp make_due_workable(job) do
    ScheduledJobs.update_job(job, %{"next_run_at" => "2000-01-01T00:00:00Z"})
  end

  describe "atomic claim — concurrent dispatch" do
    test "second perform call does not re-enqueue the same job" do
      {:ok, job} = ScheduledJobs.create_job(workable_job_attrs())
      {:ok, _} = make_due_workable(job)

      # First perform claims and enqueues
      assert :ok = perform_job(JobDispatcherWorker, %{})
      assert_enqueued(worker: EyeInTheSky.Workers.WorkableTaskWorker, args: %{"job_id" => job.id})

      # Second perform should not enqueue again (next_run_at was advanced)
      assert :ok = perform_job(JobDispatcherWorker, %{})

      all_enqueued =
        all_enqueued(worker: EyeInTheSky.Workers.WorkableTaskWorker, args: %{"job_id" => job.id})

      assert length(all_enqueued) == 1
    end

    test "claim prevents a stale due_jobs result from double-enqueueing" do
      {:ok, job} = ScheduledJobs.create_job(workable_job_attrs())
      {:ok, job} = make_due_workable(job)

      # Simulate two pollers fetching the same due job by calling claim_job twice
      # with the same stale struct
      assert {:ok, _sentinel} = ScheduledJobs.claim_job(job)
      assert {:error, :already_claimed} = ScheduledJobs.claim_job(job)
    end
  end

  describe "enqueue failure — claim release via perform" do
    # Stub module that returns an error for enqueue_job while delegating
    # everything else to the real ScheduledJobs.
    defmodule FailingEnqueueJobs do
      defdelegate due_jobs(), to: EyeInTheSky.ScheduledJobs
      defdelegate claim_job(job), to: EyeInTheSky.ScheduledJobs
      defdelegate release_claim(job, sentinel, original), to: EyeInTheSky.ScheduledJobs
      defdelegate mark_job_executed(job), to: EyeInTheSky.ScheduledJobs
      def enqueue_job(_job), do: {:error, :injected_failure}
    end

    test "perform releases the claim when enqueue_job fails, making job due again" do
      {:ok, job} = ScheduledJobs.create_job(workable_job_attrs())
      past = ~U[2000-01-01 00:00:00Z]
      {:ok, job} = ScheduledJobs.update_job(job, %{"next_run_at" => "2000-01-01T00:00:00Z"})

      Application.put_env(:eye_in_the_sky, :jobs_module, FailingEnqueueJobs)

      try do
        assert :ok = perform_job(JobDispatcherWorker, %{})
      after
        Application.delete_env(:eye_in_the_sky, :jobs_module)
      end

      # Job must be due again — claim sentinel should have been released
      {:ok, updated} = ScheduledJobs.get_job(job.id)
      assert DateTime.compare(updated.next_run_at, past) == :eq
    end
  end
end
