defmodule EyeInTheSky.PromptsTest do
  use EyeInTheSky.DataCase, async: true

  alias EyeInTheSky.{Prompts, ScheduledJobs}

  defp create_prompt(name \\ "Test") do
    {:ok, p} =
      Prompts.create_prompt(%{
        name: name,
        slug: "test-#{System.unique_integer([:positive])}",
        prompt_text: "Do something",
        active: true
      })

    p
  end

  describe "delete_prompt/1" do
    test "succeeds when no schedule exists" do
      prompt = create_prompt()
      assert {:ok, _} = Prompts.delete_prompt(prompt)
    end

    test "returns {:error, :has_active_schedule} when a schedule exists" do
      prompt = create_prompt("Scheduled")

      {:ok, _} =
        ScheduledJobs.create_job(%{
          "name" => "Guard Test",
          "job_type" => "spawn_agent",
          "schedule_type" => "cron",
          "schedule_value" => "0 5 * * *",
          "prompt_id" => prompt.id
        })

      assert Prompts.delete_prompt(prompt) == {:error, :has_active_schedule}
    end
  end
end
