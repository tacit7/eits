defmodule EyeInTheSkyWeb.ScheduledJobsTest do
  use EyeInTheSkyWeb.DataCase, async: true

  alias EyeInTheSkyWeb.ScheduledJobs
  alias EyeInTheSkyWeb.ScheduledJobs.ScheduledJob
  alias EyeInTheSkyWeb.Projects

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp create_project(name \\ "test-project") do
    {:ok, project} =
      Projects.create_project(%{
        name: name,
        path: "/tmp/#{name}",
        slug: name
      })

    project
  end

  defp job_attrs(overrides \\ %{}) do
    Map.merge(
      %{
        "name" => "Test Job",
        "job_type" => "shell_command",
        "schedule_type" => "interval",
        "schedule_value" => "60",
        "config" => Jason.encode!(%{"command" => "echo hello", "working_dir" => "/tmp"})
      },
      overrides
    )
  end

  # ---------------------------------------------------------------------------
  # list_jobs/0
  # ---------------------------------------------------------------------------

  describe "list_jobs/0" do
    test "returns empty list when no jobs exist" do
      assert ScheduledJobs.list_jobs() == []
    end

    test "returns all jobs regardless of project" do
      project = create_project()
      {:ok, _} = ScheduledJobs.create_job(job_attrs(%{"name" => "Global Job"}))
      {:ok, _} = ScheduledJobs.create_job(job_attrs(%{"name" => "Project Job", "project_id" => project.id}))

      jobs = ScheduledJobs.list_jobs()
      assert length(jobs) == 2
    end

    test "orders system jobs before user jobs" do
      {:ok, user_job} = ScheduledJobs.create_job(job_attrs(%{"name" => "User Job"}))
      {:ok, system_job} = ScheduledJobs.create_job(job_attrs(%{"name" => "System Job", "origin" => "system"}))

      jobs = ScheduledJobs.list_jobs()
      assert hd(jobs).id == system_job.id
      assert List.last(jobs).id == user_job.id
    end
  end

  # ---------------------------------------------------------------------------
  # list_jobs_for_project/1
  # ---------------------------------------------------------------------------

  describe "list_jobs_for_project/1" do
    test "returns only jobs scoped to the given project" do
      project_a = create_project("project-a")
      project_b = create_project("project-b")

      {:ok, job_a} = ScheduledJobs.create_job(job_attrs(%{"name" => "Job A", "project_id" => project_a.id}))
      {:ok, _job_b} = ScheduledJobs.create_job(job_attrs(%{"name" => "Job B", "project_id" => project_b.id}))
      {:ok, _global} = ScheduledJobs.create_job(job_attrs(%{"name" => "Global"}))

      jobs = ScheduledJobs.list_jobs_for_project(project_a.id)
      assert length(jobs) == 1
      assert hd(jobs).id == job_a.id
    end

    test "returns empty list when project has no jobs" do
      project = create_project()
      assert ScheduledJobs.list_jobs_for_project(project.id) == []
    end

    test "does not return global jobs (null project_id)" do
      project = create_project()
      {:ok, _global} = ScheduledJobs.create_job(job_attrs(%{"name" => "Global"}))

      assert ScheduledJobs.list_jobs_for_project(project.id) == []
    end
  end

  # ---------------------------------------------------------------------------
  # create_job/1
  # ---------------------------------------------------------------------------

  describe "create_job/1" do
    test "creates a job with required fields" do
      assert {:ok, %ScheduledJob{} = job} = ScheduledJobs.create_job(job_attrs())
      assert job.name == "Test Job"
      assert job.job_type == "shell_command"
      assert job.origin == "user"
      assert job.enabled == 1
    end

    test "sets project_id when provided" do
      project = create_project()
      {:ok, job} = ScheduledJobs.create_job(job_attrs(%{"project_id" => project.id}))
      assert job.project_id == project.id
    end

    test "project_id is nil for global jobs" do
      {:ok, job} = ScheduledJobs.create_job(job_attrs())
      assert is_nil(job.project_id)
    end

    test "computes next_run_at for interval schedule" do
      {:ok, job} = ScheduledJobs.create_job(job_attrs(%{"schedule_value" => "300"}))
      assert job.next_run_at != nil
    end

    test "computes next_run_at for cron schedule" do
      {:ok, job} =
        ScheduledJobs.create_job(
          job_attrs(%{"schedule_type" => "cron", "schedule_value" => "*/5 * * * *"})
        )

      assert job.next_run_at != nil
    end

    test "returns error changeset when required fields missing" do
      assert {:error, changeset} = ScheduledJobs.create_job(%{})
      assert changeset.errors[:name] != nil
    end

    test "rejects invalid job_type" do
      assert {:error, changeset} = ScheduledJobs.create_job(job_attrs(%{"job_type" => "bad_type"}))
      assert changeset.errors[:job_type] != nil
    end
  end

  # ---------------------------------------------------------------------------
  # update_job/2
  # ---------------------------------------------------------------------------

  describe "update_job/2" do
    test "updates job fields" do
      {:ok, job} = ScheduledJobs.create_job(job_attrs())
      {:ok, updated} = ScheduledJobs.update_job(job, %{"name" => "Updated Name"})
      assert updated.name == "Updated Name"
    end

    test "cannot change origin via update" do
      {:ok, job} = ScheduledJobs.create_job(job_attrs())
      {:ok, updated} = ScheduledJobs.update_job(job, %{"origin" => "system"})
      assert updated.origin == "user"
    end

    test "recomputes next_run_at when schedule changes" do
      {:ok, job} = ScheduledJobs.create_job(job_attrs(%{"schedule_value" => "60"}))
      original_next = job.next_run_at
      # Force a different next by changing interval
      {:ok, updated} = ScheduledJobs.update_job(job, %{"schedule_value" => "3600"})
      assert updated.next_run_at != original_next
    end

    test "can update project_id" do
      project = create_project()
      {:ok, job} = ScheduledJobs.create_job(job_attrs())
      {:ok, updated} = ScheduledJobs.update_job(job, %{"project_id" => project.id})
      assert updated.project_id == project.id
    end
  end

  # ---------------------------------------------------------------------------
  # delete_job/1
  # ---------------------------------------------------------------------------

  describe "delete_job/1" do
    test "deletes a user job" do
      {:ok, job} = ScheduledJobs.create_job(job_attrs())
      assert {:ok, _} = ScheduledJobs.delete_job(job)
      assert ScheduledJobs.get_job(job.id) == {:error, :not_found}
    end

    test "rejects deletion of system jobs" do
      {:ok, job} = ScheduledJobs.create_job(job_attrs(%{"origin" => "system"}))
      assert {:error, :system_job} = ScheduledJobs.delete_job(job)
    end
  end

  # ---------------------------------------------------------------------------
  # toggle_job/1
  # ---------------------------------------------------------------------------

  describe "toggle_job/1" do
    test "disables an enabled job" do
      {:ok, job} = ScheduledJobs.create_job(job_attrs())
      assert job.enabled == 1
      {:ok, toggled} = ScheduledJobs.toggle_job(job)
      assert toggled.enabled == 0
    end

    test "enables a disabled job" do
      {:ok, job} = ScheduledJobs.create_job(job_attrs())
      {:ok, disabled} = ScheduledJobs.toggle_job(job)
      {:ok, enabled} = ScheduledJobs.toggle_job(disabled)
      assert enabled.enabled == 1
    end
  end

  # ---------------------------------------------------------------------------
  # due_jobs/0
  # ---------------------------------------------------------------------------

  describe "due_jobs/0" do
    test "returns enabled jobs with past next_run_at" do
      {:ok, job} = ScheduledJobs.create_job(job_attrs())
      # Force next_run_at into the past
      past = "2000-01-01T00:00:00Z"
      ScheduledJobs.update_job(job, %{"next_run_at" => past})

      due = ScheduledJobs.due_jobs()
      assert Enum.any?(due, &(&1.id == job.id))
    end

    test "excludes disabled jobs" do
      {:ok, job} = ScheduledJobs.create_job(job_attrs())
      past = "2000-01-01T00:00:00Z"
      ScheduledJobs.update_job(job, %{"next_run_at" => past})
      ScheduledJobs.toggle_job(job)

      due = ScheduledJobs.due_jobs()
      refute Enum.any?(due, &(&1.id == job.id))
    end

    test "excludes jobs with future next_run_at" do
      {:ok, job} = ScheduledJobs.create_job(job_attrs(%{"schedule_value" => "86400"}))

      due = ScheduledJobs.due_jobs()
      refute Enum.any?(due, &(&1.id == job.id))
    end
  end

  # ---------------------------------------------------------------------------
  # compute_next_run_at/2
  # ---------------------------------------------------------------------------

  describe "compute_next_run_at/2" do
    test "computes correct interval next run" do
      from = ~N[2025-01-01 00:00:00]
      result = ScheduledJobs.compute_next_run_at("interval", "3600", from)
      assert result == "2025-01-01T01:00:00Z"
    end

    test "computes correct cron next run" do
      from = ~N[2025-01-01 00:00:00]
      result = ScheduledJobs.compute_next_run_at("cron", "0 9 * * *", from)
      assert result == "2025-01-01T09:00:00Z"
    end

    test "returns nil for invalid cron expression" do
      assert ScheduledJobs.compute_next_run_at("cron", "not-a-cron", nil) == nil
    end
  end

  # ---------------------------------------------------------------------------
  # mark_job_executed/1
  # ---------------------------------------------------------------------------

  describe "mark_job_executed/1" do
    test "increments run_count" do
      {:ok, job} = ScheduledJobs.create_job(job_attrs())
      assert job.run_count == 0
      {:ok, updated} = ScheduledJobs.mark_job_executed(job)
      assert updated.run_count == 1
    end

    test "sets last_run_at" do
      {:ok, job} = ScheduledJobs.create_job(job_attrs())
      {:ok, updated} = ScheduledJobs.mark_job_executed(job)
      assert updated.last_run_at != nil
    end

    test "updates next_run_at" do
      {:ok, job} = ScheduledJobs.create_job(job_attrs())
      original = job.next_run_at
      {:ok, updated} = ScheduledJobs.mark_job_executed(job)
      assert updated.next_run_at != original
    end
  end
end
