defmodule EyeInTheSky.ScheduledJobsTest do
  use EyeInTheSky.DataCase, async: true

  alias EyeInTheSky.Projects
  alias EyeInTheSky.Prompts
  alias EyeInTheSky.ScheduledJobs
  alias EyeInTheSky.ScheduledJobs.ScheduledJob

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

  defp create_prompt(name \\ "Test Prompt") do
    slug =
      name
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9]+/, "-")
      |> String.trim("-")
      |> then(&"#{&1}-#{System.unique_integer([:positive])}")

    {:ok, p} =
      Prompts.create_prompt(%{
        name: name,
        slug: slug,
        prompt_text: "Do the thing",
        active: true
      })

    p
  end

  defp spawn_agent_attrs(overrides) do
    Map.merge(
      %{
        "name" => "Test Agent Job",
        "job_type" => "spawn_agent",
        "schedule_type" => "cron",
        "schedule_value" => "0 5 * * *"
      },
      overrides
    )
  end

  defp job_attrs(overrides \\ %{}) do
    Map.merge(
      %{
        "name" => "Test Job",
        "job_type" => "mix_task",
        "schedule_type" => "interval",
        "schedule_value" => "60",
        "config" => Jason.encode!(%{"task" => "ecto.migrate", "args" => []})
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

      {:ok, _} =
        ScheduledJobs.create_job(
          job_attrs(%{"name" => "Project Job", "project_id" => project.id})
        )

      jobs = ScheduledJobs.list_jobs()
      assert length(jobs) == 2
    end

    test "orders system jobs before user jobs" do
      {:ok, user_job} = ScheduledJobs.create_job(job_attrs(%{"name" => "User Job"}))

      {:ok, system_job} =
        ScheduledJobs.create_job(job_attrs(%{"name" => "System Job", "origin" => "system"}))

      jobs = ScheduledJobs.list_jobs()
      assert hd(jobs).id == system_job.id
      assert List.last(jobs).id == user_job.id
    end
  end

  # ---------------------------------------------------------------------------
  # list_jobs/1 with project_id filter
  # ---------------------------------------------------------------------------

  describe "list_jobs/1 with project_id filter" do
    test "returns only jobs scoped to the given project" do
      project_a = create_project("project-a")
      project_b = create_project("project-b")

      {:ok, job_a} =
        ScheduledJobs.create_job(job_attrs(%{"name" => "Job A", "project_id" => project_a.id}))

      {:ok, _job_b} =
        ScheduledJobs.create_job(job_attrs(%{"name" => "Job B", "project_id" => project_b.id}))

      {:ok, _global} = ScheduledJobs.create_job(job_attrs(%{"name" => "Global"}))

      jobs = ScheduledJobs.list_jobs(project_id: project_a.id)
      assert length(jobs) == 1
      assert hd(jobs).id == job_a.id
    end

    test "returns empty list when project has no jobs" do
      project = create_project()
      assert ScheduledJobs.list_jobs(project_id: project.id) == []
    end

    test "does not return global jobs (null project_id)" do
      project = create_project()
      {:ok, _global} = ScheduledJobs.create_job(job_attrs(%{"name" => "Global"}))

      assert ScheduledJobs.list_jobs(project_id: project.id) == []
    end
  end

  # ---------------------------------------------------------------------------
  # create_job/1
  # ---------------------------------------------------------------------------

  describe "create_job/1" do
    test "creates a job with required fields" do
      assert {:ok, %ScheduledJob{} = job} = ScheduledJobs.create_job(job_attrs())
      assert job.name == "Test Job"
      assert job.job_type == "mix_task"
      assert job.origin == "user"
      assert job.enabled == true
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
      assert {:error, changeset} =
               ScheduledJobs.create_job(job_attrs(%{"job_type" => "bad_type"}))

      assert changeset.errors[:job_type] != nil
    end

    test "accepts workable_task job_type" do
      attrs = %{
        "name" => "Workable Task Job",
        "job_type" => "workable_task",
        "schedule_type" => "interval",
        "schedule_value" => "300"
      }

      assert {:ok, job} = ScheduledJobs.create_job(attrs)
      assert job.job_type == "workable_task"
    end

    test "rejects invalid timezone on create" do
      attrs = %{
        "name" => "TZ Job",
        "job_type" => "workable_task",
        "schedule_type" => "interval",
        "schedule_value" => "300",
        "timezone" => "Not/AZone"
      }

      assert {:error, changeset} = ScheduledJobs.create_job(attrs)
      assert changeset.errors[:timezone] != nil
    end

    test "accepts valid non-UTC timezone on create" do
      attrs = %{
        "name" => "TZ Job",
        "job_type" => "workable_task",
        "schedule_type" => "interval",
        "schedule_value" => "300",
        "timezone" => "America/New_York"
      }

      assert {:ok, job} = ScheduledJobs.create_job(attrs)
      assert job.timezone == "America/New_York"
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

    test "updating non-timezone fields does not re-validate persisted timezone" do
      # Simulate a legacy row by inserting directly with an invalid timezone
      attrs = %{
        "name" => "TZ Job",
        "job_type" => "workable_task",
        "schedule_type" => "interval",
        "schedule_value" => "300",
        "timezone" => "America/Chicago"
      }

      {:ok, job} = ScheduledJobs.create_job(attrs)

      # Patch the DB row directly to simulate a legacy invalid timezone value
      EyeInTheSky.Repo.query!(
        "UPDATE scheduled_jobs SET timezone = 'Legacy/Invalid' WHERE id = $1",
        [job.id]
      )

      reloaded = EyeInTheSky.ScheduledJobs.get_job!(job.id)

      # Updating an unrelated field must not fail due to persisted invalid timezone
      assert {:ok, updated} = ScheduledJobs.update_job(reloaded, %{"name" => "Renamed"})
      assert updated.name == "Renamed"
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
      assert job.enabled == true
      {:ok, toggled} = ScheduledJobs.toggle_job(job)
      assert toggled.enabled == false
    end

    test "enables a disabled job" do
      {:ok, job} = ScheduledJobs.create_job(job_attrs())
      {:ok, disabled} = ScheduledJobs.toggle_job(job)
      {:ok, enabled} = ScheduledJobs.toggle_job(disabled)
      assert enabled.enabled == true
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
      assert result == ~U[2025-01-01 01:00:00Z]
    end

    test "computes correct cron next run" do
      from = ~N[2025-01-01 00:00:00]
      result = ScheduledJobs.compute_next_run_at("cron", "0 9 * * *", from)
      assert result == ~U[2025-01-01 09:00:00Z]
    end

    test "returns nil for invalid cron expression" do
      assert ScheduledJobs.compute_next_run_at("cron", "not-a-cron", nil) == nil
    end
  end

  # ---------------------------------------------------------------------------
  # claim_job/1
  # ---------------------------------------------------------------------------

  defp workable_attrs(overrides \\ %{}) do
    Map.merge(
      %{
        "name" => "Claim Test Job",
        "job_type" => "workable_task",
        "schedule_type" => "interval",
        "schedule_value" => "60"
      },
      overrides
    )
  end

  describe "claim_job/1" do
    test "returns {:ok, sentinel} on first claim" do
      {:ok, job} = ScheduledJobs.create_job(workable_attrs())
      {:ok, job} = ScheduledJobs.update_job(job, %{"next_run_at" => "2000-01-01T00:00:00Z"})
      assert {:ok, sentinel} = ScheduledJobs.claim_job(job)
      assert %DateTime{} = sentinel
    end

    test "returns {:error, :already_claimed} when same struct is claimed twice" do
      {:ok, job} = ScheduledJobs.create_job(workable_attrs())
      {:ok, job} = ScheduledJobs.update_job(job, %{"next_run_at" => "2000-01-01T00:00:00Z"})

      assert {:ok, _sentinel} = ScheduledJobs.claim_job(job)
      # Second call with the same struct (stale next_run_at) must be rejected
      assert {:error, :already_claimed} = ScheduledJobs.claim_job(job)
    end

    test "advances next_run_at into the future on successful claim" do
      {:ok, job} = ScheduledJobs.create_job(workable_attrs())
      {:ok, job} = ScheduledJobs.update_job(job, %{"next_run_at" => "2000-01-01T00:00:00Z"})
      {:ok, _sentinel} = ScheduledJobs.claim_job(job)

      {:ok, updated} = ScheduledJobs.get_job(job.id)
      assert DateTime.compare(updated.next_run_at, DateTime.utc_now()) == :gt
    end

    test "claimed job no longer appears in due_jobs" do
      {:ok, job} = ScheduledJobs.create_job(workable_attrs())
      {:ok, job} = ScheduledJobs.update_job(job, %{"next_run_at" => "2000-01-01T00:00:00Z"})
      {:ok, _sentinel} = ScheduledJobs.claim_job(job)

      due_ids = ScheduledJobs.due_jobs() |> Enum.map(& &1.id)
      refute job.id in due_ids
    end

    test "rejects claim for a disabled job" do
      {:ok, job} = ScheduledJobs.create_job(workable_attrs())
      {:ok, job} = ScheduledJobs.update_job(job, %{"next_run_at" => "2000-01-01T00:00:00Z"})
      {:ok, job} = ScheduledJobs.toggle_job(job)

      assert {:error, :already_claimed} = ScheduledJobs.claim_job(job)
    end
  end

  # ---------------------------------------------------------------------------
  # release_claim/3
  # ---------------------------------------------------------------------------

  describe "release_claim/3" do
    test "restores next_run_at so job reappears in due_jobs" do
      {:ok, job} = ScheduledJobs.create_job(workable_attrs())
      past = ~U[2000-01-01 00:00:00Z]
      {:ok, job} = ScheduledJobs.update_job(job, %{"next_run_at" => "2000-01-01T00:00:00Z"})

      {:ok, sentinel} = ScheduledJobs.claim_job(job)
      # Verify claimed (not due)
      refute job.id in (ScheduledJobs.due_jobs() |> Enum.map(& &1.id))

      :ok = ScheduledJobs.release_claim(job, sentinel, past)
      # Now due again
      assert job.id in (ScheduledJobs.due_jobs() |> Enum.map(& &1.id))
    end

    test "no-ops when sentinel no longer matches (mark_job_executed already ran)" do
      {:ok, job} = ScheduledJobs.create_job(workable_attrs())
      past = ~U[2000-01-01 00:00:00Z]
      {:ok, job} = ScheduledJobs.update_job(job, %{"next_run_at" => "2000-01-01T00:00:00Z"})

      {:ok, sentinel} = ScheduledJobs.claim_job(job)
      # Simulate mark_job_executed by advancing next_run_at beyond the sentinel
      {:ok, _} = ScheduledJobs.mark_job_executed(job)

      # release_claim should be a no-op: sentinel no longer matches
      :ok = ScheduledJobs.release_claim(job, sentinel, past)

      # Job should NOT be due again — mark_job_executed already set next_run_at
      refute job.id in (ScheduledJobs.due_jobs() |> Enum.map(& &1.id))
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

  # ---------------------------------------------------------------------------
  # ScheduledJob schema
  # ---------------------------------------------------------------------------

  describe "ScheduledJob schema" do
    test "cast includes prompt_id" do
      attrs = %{
        "name" => "Test",
        "job_type" => "spawn_agent",
        "schedule_type" => "cron",
        "schedule_value" => "0 5 * * *",
        "prompt_id" => 999
      }

      cs = ScheduledJob.changeset(%ScheduledJob{}, attrs)
      assert cs.changes.prompt_id == 999
    end

    test "prompt_id uniqueness constraint is registered" do
      cs = ScheduledJob.changeset(%ScheduledJob{}, %{})
      constraint_names = Enum.map(cs.constraints, & &1.constraint)
      assert "idx_scheduled_jobs_unique_prompt" in constraint_names
    end
  end

  # ---------------------------------------------------------------------------
  # list_spawn_agent_jobs_by_prompt_ids/1
  # ---------------------------------------------------------------------------

  describe "list_spawn_agent_jobs_by_prompt_ids/1" do
    test "returns jobs matching given prompt_ids" do
      prompt = create_prompt()
      {:ok, job} = ScheduledJobs.create_job(spawn_agent_attrs(%{"prompt_id" => prompt.id}))
      results = ScheduledJobs.list_spawn_agent_jobs_by_prompt_ids([prompt.id])
      assert Enum.any?(results, &(&1.id == job.id))
    end

    test "returns empty list for unknown ids" do
      assert ScheduledJobs.list_spawn_agent_jobs_by_prompt_ids([999_999]) == []
    end
  end

  # ---------------------------------------------------------------------------
  # list_orphaned_agent_jobs/0
  # ---------------------------------------------------------------------------

  describe "list_orphaned_agent_jobs/0" do
    test "returns spawn_agent jobs whose prompt is inactive" do
      prompt = create_prompt("Inactive")
      {:ok, job} = ScheduledJobs.create_job(spawn_agent_attrs(%{"prompt_id" => prompt.id}))
      {:ok, _} = Prompts.update_prompt(prompt, %{active: false})
      orphans = ScheduledJobs.list_orphaned_agent_jobs()
      assert Enum.any?(orphans, &(&1.id == job.id))
    end

    test "does not return jobs whose prompt is active" do
      prompt = create_prompt("Active")
      {:ok, job} = ScheduledJobs.create_job(spawn_agent_attrs(%{"prompt_id" => prompt.id}))
      orphans = ScheduledJobs.list_orphaned_agent_jobs()
      refute Enum.any?(orphans, &(&1.id == job.id))
    end
  end

  # ---------------------------------------------------------------------------
  # enqueue_job/1
  # ---------------------------------------------------------------------------

  describe "enqueue_job/1" do
    test "returns {:error, {:unknown_job_type, type}} for unrecognized job_type" do
      job = %EyeInTheSky.ScheduledJobs.ScheduledJob{
        id: 0,
        job_type: "nonexistent_type",
        name: "Fake",
        schedule_type: "interval",
        schedule_value: "60"
      }

      assert {:error, {:unknown_job_type, "nonexistent_type"}} = ScheduledJobs.enqueue_job(job)
    end

    test "enqueue_job/1 with workable_task job_type enqueues without error" do
      {:ok, job} = ScheduledJobs.create_job(workable_attrs())

      assert {:ok, _oban_job} = ScheduledJobs.enqueue_job(job)
    end
  end

  # ---------------------------------------------------------------------------
  # create_job/1 duplicate prompt_id
  # ---------------------------------------------------------------------------

  describe "create_job/1 duplicate prompt_id" do
    test "returns {:error, :already_scheduled}" do
      prompt = create_prompt("Dupe")

      {:ok, _} =
        ScheduledJobs.create_job(
          spawn_agent_attrs(%{"prompt_id" => prompt.id, "name" => "First"})
        )

      result =
        ScheduledJobs.create_job(
          spawn_agent_attrs(%{"prompt_id" => prompt.id, "name" => "Second"})
        )

      assert result == {:error, :already_scheduled}
    end
  end
end
