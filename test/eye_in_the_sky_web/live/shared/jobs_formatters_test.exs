defmodule EyeInTheSkyWeb.Live.Shared.JobsFormattersTest do
  use ExUnit.Case, async: true

  alias EyeInTheSkyWeb.Live.Shared.JobsFormatters

  # ---------------------------------------------------------------------------
  # format_schedule/1 — thin delegate to ScheduleDescription.describe/1.
  # Detailed schedule-wording coverage lives in ScheduleDescriptionTest; these
  # cases confirm the delegation is wired for both interval and cron.
  # ---------------------------------------------------------------------------

  describe "format_schedule/1" do
    test "interval in hours" do
      assert "Every 2h" ==
               JobsFormatters.format_schedule(%{
                 schedule_type: "interval",
                 schedule_value: "7200"
               })
    end

    test "interval in minutes" do
      assert "Every 15m" ==
               JobsFormatters.format_schedule(%{schedule_type: "interval", schedule_value: "900"})
    end

    test "interval in seconds" do
      assert "Every 30s" ==
               JobsFormatters.format_schedule(%{schedule_type: "interval", schedule_value: "30"})
    end

    test "interval with non-numeric value returns raw" do
      assert "bad" ==
               JobsFormatters.format_schedule(%{schedule_type: "interval", schedule_value: "bad"})
    end

    test "cron delegates to the shared describer" do
      assert "Daily at 3 AM" ==
               JobsFormatters.format_schedule(%{
                 schedule_type: "cron",
                 schedule_value: "0 3 * * *"
               })
    end

    test "unknown schedule type" do
      assert "?" ==
               JobsFormatters.format_schedule(%{schedule_type: "unknown", schedule_value: "x"})
    end

    test "nil input" do
      assert "?" == JobsFormatters.format_schedule(nil)
    end
  end

  # ---------------------------------------------------------------------------
  # job_row_state/3 — enabled is a real :boolean column (see ScheduledJob
  # schema), not 0/1. `job.enabled != 1` previously misclassified every
  # enabled job as :disabled because `true != 1` in Elixir (different types
  # never compare equal), regardless of the job's actual state.
  # ---------------------------------------------------------------------------

  describe "job_row_state/3" do
    test "enabled job with no activity is :healthy" do
      assert :healthy ==
               JobsFormatters.job_row_state(%{id: 1, enabled: true}, MapSet.new(), %{})
    end

    test "disabled job is :disabled regardless of other state" do
      assert :disabled ==
               JobsFormatters.job_row_state(%{id: 1, enabled: false}, MapSet.new(), %{})
    end

    test "enabled job currently running is :running" do
      assert :running ==
               JobsFormatters.job_row_state(%{id: 1, enabled: true}, MapSet.new([1]), %{})
    end

    test "enabled job whose last run failed is :failed" do
      assert :failed ==
               JobsFormatters.job_row_state(%{id: 1, enabled: true}, MapSet.new(), %{
                 1 => "failed"
               })
    end

    test "disabled takes priority over running/failed" do
      assert :disabled ==
               JobsFormatters.job_row_state(%{id: 1, enabled: false}, MapSet.new([1]), %{
                 1 => "failed"
               })
    end
  end
end
