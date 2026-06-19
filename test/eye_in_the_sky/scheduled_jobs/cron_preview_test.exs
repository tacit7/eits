defmodule EyeInTheSky.ScheduledJobs.CronPreviewTest do
  use ExUnit.Case

  alias EyeInTheSky.ScheduledJobs.CronPreview

  describe "preview/1" do
    test "handles every 5 minutes" do
      assert CronPreview.preview("*/5 * * * *") == "Runs every 5 minutes"
    end

    test "handles every minute" do
      assert CronPreview.preview("* * * * *") == "Runs every minute"
    end

    test "handles specific daily time" do
      preview = CronPreview.preview("0 9 * * *")
      assert preview == "Runs daily at 09:00 AM"
    end

    test "handles weekday schedule" do
      preview = CronPreview.preview("0 9 * * 1-5")
      assert String.contains?(preview, "Monday-Friday") and String.contains?(preview, "09:00 AM")
    end

    test "handles monthly schedule" do
      preview = CronPreview.preview("0 0 1 * *")
      assert String.contains?(preview, "1st") and String.contains?(preview, "12:00 AM")
    end

    test "returns nil for invalid cron expression" do
      assert CronPreview.preview("invalid") == nil
    end

    test "returns nil for non-binary input" do
      assert CronPreview.preview(nil) == nil
      assert CronPreview.preview(123) == nil
    end
  end
end
