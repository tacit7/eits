defmodule EyeInTheSkyWeb.Live.Shared.JobsFormattersTest do
  use ExUnit.Case, async: true

  alias EyeInTheSkyWeb.Live.Shared.JobsFormatters

  # ---------------------------------------------------------------------------
  # format_schedule/1
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

    test "cron delegates to describe_cron" do
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
  # describe_cron/1
  # ---------------------------------------------------------------------------

  describe "describe_cron/1" do
    test "daily at specific time" do
      assert "Daily at 9 AM" == JobsFormatters.describe_cron("0 9 * * *")
    end

    test "daily at noon" do
      assert "Daily at 12 PM" == JobsFormatters.describe_cron("0 12 * * *")
    end

    test "daily at midnight" do
      assert "Daily at 12 AM" == JobsFormatters.describe_cron("0 0 * * *")
    end

    test "time with minutes" do
      assert "Daily at 2:30 PM" == JobsFormatters.describe_cron("30 14 * * *")
    end

    test "weekdays only" do
      assert "Weekdays at 8 AM" == JobsFormatters.describe_cron("0 8 * * 1-5")
    end

    test "weekends only" do
      assert "Weekends at 10 AM" == JobsFormatters.describe_cron("0 10 * * 0,6")
    end

    test "specific day of week" do
      assert "Mon at 6 AM" == JobsFormatters.describe_cron("0 6 * * 1")
    end

    test "specific day of month" do
      assert "Day 15 at 9 AM" == JobsFormatters.describe_cron("0 9 15 * *")
    end

    test "every N hours" do
      assert "Daily at Every 4h" == JobsFormatters.describe_cron("0 */4 * * *")
    end

    test "every N minutes" do
      assert "Daily at Every 15m" == JobsFormatters.describe_cron("*/15 * * * *")
    end

    test "invalid cron returns raw expression" do
      assert "bad cron" == JobsFormatters.describe_cron("bad cron")
    end
  end

  # ---------------------------------------------------------------------------
  # format_cron_day/3
  # ---------------------------------------------------------------------------

  describe "format_cron_day/3" do
    test "all wildcards means daily" do
      assert "Daily" == JobsFormatters.format_cron_day("*", "*", "*")
    end

    test "specific day of week" do
      assert "Mon" == JobsFormatters.format_cron_day("1", "*", "*")
    end

    test "specific day of month" do
      assert "Day 15" == JobsFormatters.format_cron_day("*", "15", "*")
    end

    test "day and month" do
      assert "Mar 25" == JobsFormatters.format_cron_day("*", "25", "3")
    end

    test "weekday range" do
      assert "Weekdays" == JobsFormatters.format_cron_day("1-5", "*", "*")
    end

    test "comma-separated days" do
      assert "Mon, Wed, Fri" == JobsFormatters.format_cron_day("1,3,5", "*", "*")
    end
  end

  # ---------------------------------------------------------------------------
  # cfg/2
  # ---------------------------------------------------------------------------

  describe "cfg/2" do
    test "returns string value" do
      assert "hello" == JobsFormatters.cfg(%{"key" => "hello"}, "key")
    end

    test "joins list value" do
      assert "a, b, c" == JobsFormatters.cfg(%{"args" => ["a", "b", "c"]}, "args")
    end

    test "converts integer to string" do
      assert "42" == JobsFormatters.cfg(%{"timeout" => 42}, "timeout")
    end

    test "returns empty string for missing key" do
      assert "" == JobsFormatters.cfg(%{"other" => "val"}, "missing")
    end

    test "returns empty string for nil config" do
      assert "" == JobsFormatters.cfg(nil, "key")
    end
  end

  # ---------------------------------------------------------------------------
  # Badge helpers
  # ---------------------------------------------------------------------------

  describe "type_badge_class/1" do
    test "spawn_agent" do
      assert "badge-primary" == JobsFormatters.type_badge_class("spawn_agent")
    end

    test "shell_command" do
      assert "badge-warning" == JobsFormatters.type_badge_class("shell_command")
    end

    test "unknown type" do
      assert "badge-ghost" == JobsFormatters.type_badge_class("other")
    end
  end

  describe "type_label/1" do
    test "maps spawn_agent to Agent" do
      assert "Agent" == JobsFormatters.type_label("spawn_agent")
    end

    test "unknown type passes through" do
      assert "custom" == JobsFormatters.type_label("custom")
    end
  end

  describe "status_badge_class/1" do
    test "running" do
      assert "badge-info" == JobsFormatters.status_badge_class("running")
    end

    test "completed" do
      assert "badge-success" == JobsFormatters.status_badge_class("completed")
    end

    test "failed" do
      assert "badge-error" == JobsFormatters.status_badge_class("failed")
    end
  end

  # ---------------------------------------------------------------------------
  # job_row_state/3 and row_border_class/1
  # ---------------------------------------------------------------------------

  describe "job_row_state/3" do
    test "disabled job" do
      job = %{id: 1, enabled: 0}
      assert :disabled == JobsFormatters.job_row_state(job, MapSet.new(), %{})
    end

    test "running job" do
      job = %{id: 1, enabled: 1}
      assert :running == JobsFormatters.job_row_state(job, MapSet.new([1]), %{})
    end

    test "failed job" do
      job = %{id: 1, enabled: 1}
      assert :failed == JobsFormatters.job_row_state(job, MapSet.new(), %{1 => "failed"})
    end

    test "healthy job" do
      job = %{id: 1, enabled: 1}
      assert :healthy == JobsFormatters.job_row_state(job, MapSet.new(), %{1 => "completed"})
    end
  end

  describe "row_border_class/1" do
    test "disabled" do
      assert "border-l-4 border-base-content/20" == JobsFormatters.row_border_class(:disabled)
    end

    test "running" do
      assert "border-l-4 border-warning" == JobsFormatters.row_border_class(:running)
    end

    test "failed" do
      assert "border-l-4 border-error" == JobsFormatters.row_border_class(:failed)
    end

    test "healthy" do
      assert "border-l-4 border-success" == JobsFormatters.row_border_class(:healthy)
    end
  end

  # ---------------------------------------------------------------------------
  # system_timezone/0
  # ---------------------------------------------------------------------------

  describe "system_timezone/0" do
    test "returns a non-empty string" do
      tz = JobsFormatters.system_timezone()
      assert is_binary(tz)
      assert String.length(tz) > 0
    end
  end
end
