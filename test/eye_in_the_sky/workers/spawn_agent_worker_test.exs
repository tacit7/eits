defmodule EyeInTheSky.Workers.SpawnAgentWorkerTest do
  use EyeInTheSky.DataCase, async: false
  use Oban.Testing, repo: EyeInTheSky.Repo

  alias EyeInTheSky.Events
  alias EyeInTheSky.ScheduledJobs
  alias EyeInTheSky.Workers.SpawnAgentWorker

  defmodule SuccessfulAgentManager do
    def create_agent(_opts) do
      {:ok,
       %{
         session: %{id: 123}
       }}
    end
  end

  defmodule FailingAgentManager do
    def create_agent(_opts) do
      {:error, :agent_spawn_failed}
    end
  end

  defp create_spawn_agent_job(config \\ %{}) do
    default_config = %{
      "instructions" => "Test instructions",
      "model" => "sonnet",
      "project_path" => "/test/project",
      "description" => "Test agent job"
    }

    merged_config = Map.merge(default_config, config)

    {:ok, job} =
      ScheduledJobs.create_job(%{
        "name" => "Spawn Agent Test",
        "job_type" => "spawn_agent",
        "schedule_type" => "cron",
        "schedule_value" => "0 8 * * *",
        "config" => merged_config
      })

    job
  end

  describe "perform/1 success path" do
    setup do
      Application.put_env(:eye_in_the_sky, :agent_manager_module, SuccessfulAgentManager)
      on_exit(fn -> Application.delete_env(:eye_in_the_sky, :agent_manager_module) end)
    end

    test "broadcasts :jobs_updated on success" do
      Events.subscribe_scheduled_jobs()
      job = create_spawn_agent_job()

      assert :ok = perform_job(SpawnAgentWorker, %{"job_id" => job.id})

      assert_receive :jobs_updated, 2000
    end

    test "records a completed run with session_id in result" do
      job = create_spawn_agent_job()

      assert :ok = perform_job(SpawnAgentWorker, %{"job_id" => job.id})

      runs = ScheduledJobs.list_runs_for_job(job.id)
      completed_run = Enum.find(runs, &(&1.status == "completed"))

      assert completed_run
      assert completed_run.result =~ "Agent spawned"
    end

    test "appends DM link to instructions" do
      job = create_spawn_agent_job()

      # Mock to capture the opts passed to create_agent
      agent_opts = capture_agent_opts(job)

      assert agent_opts[:instructions] =~ "/dm/"
      assert agent_opts[:instructions] =~ "Your DM page link"
    end
  end

  describe "perform/1 failure path" do
    setup do
      Application.put_env(:eye_in_the_sky, :agent_manager_module, FailingAgentManager)
      on_exit(fn -> Application.delete_env(:eye_in_the_sky, :agent_manager_module) end)
    end

    test "broadcasts :jobs_updated even on failure" do
      Events.subscribe_scheduled_jobs()
      job = create_spawn_agent_job()

      assert {:error, _} = perform_job(SpawnAgentWorker, %{"job_id" => job.id})

      assert_receive :jobs_updated, 2000
    end

    test "records a failed run with error reason" do
      job = create_spawn_agent_job()

      assert {:error, _} = perform_job(SpawnAgentWorker, %{"job_id" => job.id})

      runs = ScheduledJobs.list_runs_for_job(job.id)
      failed_run = Enum.find(runs, &(&1.status == "failed"))

      assert failed_run
      assert failed_run.result =~ "Failed to spawn agent"
    end
  end

  describe "build_agent_opts/4" do
    test "includes required fields from config" do
      config = %{
        "instructions" => "Do something",
        "model" => "opus",
        "project_path" => "/path/to/proj",
        "description" => "My Agent"
      }

      job = %{
        id: 999,
        name: "Agent Job",
        project_id: 42
      }

      opts =
        SpawnAgentWorker.__handle_call__(
          :build_agent_opts,
          [config, Ecto.UUID.generate(), "Test", job]
        )

      assert opts[:instructions] =~ "Do something"
      assert opts[:model] == "opus"
      assert opts[:project_path] == "/path/to/proj"
      assert opts[:description] == "My Agent"
      assert opts[:project_id] == 42
      assert opts[:provider_conversation_id]
    end

    test "handles optional fields" do
      config = %{
        "instructions" => "Test",
        "model" => "sonnet",
        "project_path" => "/path",
        "max_budget_usd" => "10.50",
        "max_turns" => "20",
        "fallback_model" => "haiku",
        "agent" => "my-agent",
        "allowed_tools" => ["bash", "read"],
        "output_format" => "markdown"
      }

      job = %{
        id: 999,
        name: "Agent Job",
        project_id: 42
      }

      opts =
        SpawnAgentWorker.__handle_call__(
          :build_agent_opts,
          [config, Ecto.UUID.generate(), "Test", job]
        )

      assert opts[:max_budget_usd] == 10.5
      assert opts[:max_turns] == 20
      assert opts[:fallback_model] == "haiku"
      assert opts[:agent] == "my-agent"
      assert opts[:allowed_tools] == ["bash", "read"]
      assert opts[:output_format] == "markdown"
    end

    test "skips nil or empty string optional fields" do
      config = %{
        "instructions" => "Test",
        "model" => "sonnet",
        "project_path" => "/path",
        "max_budget_usd" => nil,
        "max_turns" => "",
        "fallback_model" => nil
      }

      job = %{
        id: 999,
        name: "Agent Job",
        project_id: 42
      }

      opts =
        SpawnAgentWorker.__handle_call__(
          :build_agent_opts,
          [config, Ecto.UUID.generate(), "Test", job]
        )

      refute Keyword.has_key?(opts, :max_budget_usd)
      refute Keyword.has_key?(opts, :max_turns)
      refute Keyword.has_key?(opts, :fallback_model)
    end
  end

  describe "parse_float/1" do
    test "parses valid float string" do
      assert SpawnAgentWorker.__handle_call__(:parse_float, ["10.5"]) == 10.5
      assert SpawnAgentWorker.__handle_call__(:parse_float, ["0.1"]) == 0.1
      assert SpawnAgentWorker.__handle_call__(:parse_float, ["100"]) == 100.0
    end

    test "returns nil for invalid float string" do
      assert SpawnAgentWorker.__handle_call__(:parse_float, ["not_a_number"]) == nil
      assert SpawnAgentWorker.__handle_call__(:parse_float, ["10.5.6"]) == nil
    end

    test "handles nil and empty string" do
      assert SpawnAgentWorker.__handle_call__(:parse_float, [nil]) == nil
      assert SpawnAgentWorker.__handle_call__(:parse_float, [""]) == nil
    end

    test "returns float as-is if already a number" do
      assert SpawnAgentWorker.__handle_call__(:parse_float, [10.5]) == 10.5
      assert SpawnAgentWorker.__handle_call__(:parse_float, [42]) == 42
    end
  end

  describe "server_base_url/0" do
    test "returns configured server_base_url" do
      Application.put_env(:eye_in_the_sky, :server_base_url, "http://example.com")
      on_exit(fn -> Application.delete_env(:eye_in_the_sky, :server_base_url) end)

      url = SpawnAgentWorker.__handle_call__(:server_base_url, [])

      assert url == "http://example.com"
    end

    test "defaults to http://localhost:5001 when not configured" do
      Application.delete_env(:eye_in_the_sky, :server_base_url)

      url = SpawnAgentWorker.__handle_call__(:server_base_url, [])

      assert url == "http://localhost:5001"
    end
  end

  # Helper to execute SpawnAgentWorker in tests by directly calling perform
  # Since Oban.Testing provides perform_job, we use that
  defp perform_job(worker, args) do
    worker.perform(%Oban.Job{args: args, id: 123, attempt: 1})
  end

  # Helper to capture the actual opts passed to AgentManager (for testing arg building)
  defp capture_agent_opts(job) do
    config = ScheduledJobs.decode_config(job)
    provider_conversation_id = Ecto.UUID.generate()
    base_url = "http://localhost:5001"
    dm_link = "#{base_url}/dm/#{provider_conversation_id}"
    base_instructions = config["instructions"] || "Scheduled agent task"

    instructions =
      base_instructions <>
        "\n\nYour DM page link (include this in any notifications): #{dm_link}"

    SpawnAgentWorker.__handle_call__(
      :build_agent_opts,
      [config, provider_conversation_id, instructions, job]
    )
  end
end
