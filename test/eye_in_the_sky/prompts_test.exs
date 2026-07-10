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

    test "returns {:error, changeset} when a schedule exists" do
      prompt = create_prompt("Scheduled")

      {:ok, _} =
        ScheduledJobs.create_job(%{
          "name" => "Guard Test",
          "job_type" => "spawn_agent",
          "schedule_type" => "cron",
          "schedule_value" => "0 5 * * *",
          "prompt_id" => prompt.id
        })

      assert {:error, %Ecto.Changeset{} = changeset} = Prompts.delete_prompt(prompt)
      assert {"has active schedules", _} = changeset.errors[:scheduled_jobs]
    end
  end

  describe "duplicate_prompt/1" do
    test "copies fields into a new row with a -copy slug suffix" do
      prompt = create_prompt("Reviewer")

      assert {:ok, copy} = Prompts.duplicate_prompt(prompt)

      assert copy.id != prompt.id
      assert copy.slug == "#{prompt.slug}-copy"
      assert copy.name == "Reviewer (copy)"
      assert copy.prompt_text == prompt.prompt_text
      assert copy.version == 1
    end

    test "increments the suffix when -copy is already taken" do
      prompt = create_prompt("Reviewer")
      {:ok, _first_copy} = Prompts.duplicate_prompt(prompt)

      assert {:ok, second_copy} = Prompts.duplicate_prompt(prompt)
      assert second_copy.slug == "#{prompt.slug}-copy-2"
    end

    test "carries over project_id" do
      prompt = create_prompt("Reviewer")
      {:ok, scoped} = Prompts.update_prompt(prompt, %{project_id: 999_001})

      assert {:ok, copy} = Prompts.duplicate_prompt(scoped)
      assert copy.project_id == 999_001
    end
  end
end
