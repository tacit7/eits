defmodule EyeInTheSkyWeb.Components.AgentScheduleFormTest do
  use EyeInTheSkyWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  alias EyeInTheSkyWeb.Components.AgentScheduleForm

  defp base_prompt do
    %{id: 1, name: "Test Prompt", project_id: nil}
  end

  defp base_job(overrides) do
    Map.merge(
      %{
        id: 42,
        config: nil,
        schedule_type: "cron",
        schedule_value: "0 9 * * *",
        timezone: "Etc/UTC"
      },
      overrides
    )
  end

  defp base_assigns(overrides \\ %{}) do
    Map.merge(
      %{
        show: true,
        prompt: base_prompt(),
        job: nil,
        projects: [],
        context_project_id: nil
      },
      overrides
    )
  end

  describe "config decode guard" do
    test "renders when job is nil" do
      html = render_component(&AgentScheduleForm.agent_schedule_form/1, base_assigns())

      assert html =~ "Schedule Agent"
      assert html =~ "Save Schedule"
      assert html =~ "Test Prompt"
    end

    test "renders when job.config is nil" do
      html =
        render_component(
          &AgentScheduleForm.agent_schedule_form/1,
          base_assigns(%{job: base_job(%{config: nil})})
        )

      assert html =~ "Edit Schedule"
      assert html =~ "Save Schedule"
    end

    test "renders when job.config is a JSON binary string" do
      html =
        render_component(
          &AgentScheduleForm.agent_schedule_form/1,
          base_assigns(%{job: base_job(%{config: ~s({"model":"sonnet"})})})
        )

      assert html =~ "Edit Schedule"
      assert html =~ "Save Schedule"
    end

    test "renders when job.config is an already-decoded map" do
      html =
        render_component(
          &AgentScheduleForm.agent_schedule_form/1,
          base_assigns(%{job: base_job(%{config: %{"model" => "sonnet"}})})
        )

      assert html =~ "Edit Schedule"
      assert html =~ "Save Schedule"
    end
  end
end
