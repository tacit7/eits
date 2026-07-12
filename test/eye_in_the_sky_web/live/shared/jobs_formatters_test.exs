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
end
