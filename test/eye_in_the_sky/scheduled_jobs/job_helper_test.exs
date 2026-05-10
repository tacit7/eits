defmodule EyeInTheSky.ScheduledJobs.JobHelperTest do
  use ExUnit.Case, async: true

  alias EyeInTheSky.ScheduledJobs.JobHelper

  describe "prompt/0" do
    test "returns the base prompt with no description and no project" do
      result = JobHelper.prompt()

      assert is_binary(result)
      assert result =~ "You are Job Helper"
      refute result =~ "The user said:"
      refute result =~ "## Project Context"
    end
  end

  describe "prompt/1" do
    test "with nil description returns the base prompt without user context" do
      result = JobHelper.prompt(nil)

      assert is_binary(result)
      assert result =~ "You are Job Helper"
      refute result =~ "The user said:"
    end

    test "with empty string returns the base prompt without user context" do
      result = JobHelper.prompt("")

      refute result =~ "The user said:"
      assert result =~ "You are Job Helper"
    end

    test "with a description embeds it into the user context block" do
      result = JobHelper.prompt("backup the database every night")

      assert result =~ ~s(The user said: "backup the database every night")
      assert result =~ "Use this to guide the conversation."
    end
  end

  describe "prompt/2 with project option" do
    test "embeds project name and id when project is given" do
      project = %{id: 42, name: "Aurora"}

      result = JobHelper.prompt("ship it", project: project)

      assert result =~ "## Project Context"
      assert result =~ "**Aurora**"
      assert result =~ "(id: 42)"
      assert result =~ "Default `project_id` to `42`"
      assert result =~ ~s(The user said: "ship it")
    end

    test "omits project context when project option is nil" do
      result = JobHelper.prompt("hi", project: nil)

      refute result =~ "## Project Context"
    end

    test "omits project context when project key is absent from opts" do
      result = JobHelper.prompt("hi", [])

      refute result =~ "## Project Context"
    end

    test "supports project context with nil description" do
      project = %{id: 7, name: "Helios"}

      result = JobHelper.prompt(nil, project: project)

      refute result =~ "The user said:"
      assert result =~ "**Helios**"
      assert result =~ "(id: 7)"
    end

    test "supports project context with empty description" do
      project = %{id: 1, name: "Solo"}

      result = JobHelper.prompt("", project: project)

      refute result =~ "The user said:"
      assert result =~ "**Solo**"
    end
  end

  describe "prompt content invariants" do
    test "always includes the job types section" do
      result = JobHelper.prompt("anything")

      assert result =~ "## Job Types"
      assert result =~ "spawn_agent"
      assert result =~ "mix_task"
      assert result =~ "daily_digest"
    end

    test "always includes the schedule types section" do
      result = JobHelper.prompt()

      assert result =~ "## Schedule Types"
      assert result =~ "interval"
      assert result =~ "cron"
    end

    test "always includes the API creation section" do
      result = JobHelper.prompt()

      assert result =~ "## Creating a Job via API"
      assert result =~ "http://localhost:5001/api/v1/jobs"
    end

    test "always includes the conversation flow section" do
      result = JobHelper.prompt()

      assert result =~ "## Conversation Flow"
      assert result =~ "Step 0"
    end

    test "includes worker scaffolding instructions for new job types" do
      result = JobHelper.prompt()

      assert result =~ "Worker Required"
      assert result =~ "SpawnAgentWorker"
      assert result =~ "MixTaskWorker"
      assert result =~ "DailyDigestWorker"
    end
  end
end
