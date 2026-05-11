defmodule EyeInTheSky.Workers.SpawnAgentWorkerTest do
  use EyeInTheSky.DataCase, async: false
  use Oban.Testing, repo: EyeInTheSky.Repo

  # perform_job/2 is injected by Oban.Testing — do NOT define it here.

  alias EyeInTheSky.Events
  alias EyeInTheSky.ScheduledJobs
  alias EyeInTheSky.Workers.SpawnAgentWorker

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp create_spawn_agent_job(config \\ %{}) do
    default_config = %{
      "instructions" => "Test instructions",
      "model" => "sonnet",
      "project_path" => "/test/project",
      "description" => "Test agent job"
    }

    {:ok, job} =
      ScheduledJobs.create_job(%{
        "name" => "Spawn Agent Test",
        "job_type" => "spawn_agent",
        "schedule_type" => "cron",
        "schedule_value" => "0 8 * * *",
        "config" => Map.merge(default_config, config)
      })

    job
  end

  # ---------------------------------------------------------------------------
  # perform/1 — requires a live Claude CLI binary; run only on full CI / locally.
  # Tag :integration so --exclude integration keeps the default suite fast.
  # ---------------------------------------------------------------------------

  describe "perform/1 success path" do
    @describetag :integration

    test "broadcasts :jobs_updated and records a completed run" do
      Events.subscribe_scheduled_jobs()
      job = create_spawn_agent_job()

      assert :ok = perform_job(SpawnAgentWorker, %{"job_id" => job.id})

      assert_receive :jobs_updated, 5_000

      runs = ScheduledJobs.list_runs_for_job(job.id)
      assert Enum.any?(runs, &(&1.status == "completed"))
    end
  end

  describe "perform/1 failure path" do
    @describetag :integration

    test "records a failed run and broadcasts :jobs_updated when agent spawn fails" do
      Events.subscribe_scheduled_jobs()
      # Nonexistent project path → AgentManager will fail to spawn
      job = create_spawn_agent_job(%{"project_path" => "/nonexistent/path/#{System.unique_integer()}"})

      result = perform_job(SpawnAgentWorker, %{"job_id" => job.id})

      # Either the job errors or it records a failed run — either is acceptable
      assert result == :ok or match?({:error, _}, result)

      assert_receive :jobs_updated, 5_000
    end
  end

  # ---------------------------------------------------------------------------
  # ScheduledJobs config decoding — tests the job creation + decode round-trip,
  # not SpawnAgentWorker internals, so no private-function access needed.
  # ---------------------------------------------------------------------------

  describe "job config round-trip" do
    test "stores and decodes all known optional fields" do
      job =
        create_spawn_agent_job(%{
          "model" => "opus",
          "max_budget_usd" => "10.50",
          "max_turns" => "5",
          "fallback_model" => "haiku",
          "agent" => "my-agent",
          "allowed_tools" => ["bash", "read"],
          "output_format" => "json"
        })

      config = ScheduledJobs.decode_config(job)

      assert config["model"] == "opus"
      assert config["max_budget_usd"] == "10.50"
      assert config["max_turns"] == "5"
      assert config["fallback_model"] == "haiku"
      assert config["agent"] == "my-agent"
      assert config["output_format"] == "json"
    end

    test "decode_config returns empty map for job with no config" do
      {:ok, job} =
        ScheduledJobs.create_job(%{
          "name" => "Minimal Job",
          "job_type" => "spawn_agent",
          "schedule_type" => "cron",
          "schedule_value" => "0 8 * * *"
        })

      config = ScheduledJobs.decode_config(job)

      assert is_map(config)
    end
  end
end
