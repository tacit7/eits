defmodule EyeInTheSky.ScheduledJobs.ScheduleDescriptionTest do
  use ExUnit.Case, async: true

  alias EyeInTheSky.ScheduledJobs.ScheduleDescription, as: SD

  describe "describe/1 — interval" do
    test "hours" do
      assert "Every 2h" == SD.describe(%{schedule_type: "interval", schedule_value: "7200"})
    end

    test "45 minutes" do
      assert "Every 45m" == SD.describe(%{schedule_type: "interval", schedule_value: "2700"})
    end

    test "minutes" do
      assert "Every 15m" == SD.describe(%{schedule_type: "interval", schedule_value: "900"})
    end

    test "seconds" do
      assert "Every 30s" == SD.describe(%{schedule_type: "interval", schedule_value: "30"})
    end

    test "non-numeric returns raw value" do
      assert "bad" == SD.describe(%{schedule_type: "interval", schedule_value: "bad"})
    end
  end

  describe "describe/1 — cron" do
    test "daily at specific time" do
      assert "Daily at 9 AM" == SD.describe(cron("0 9 * * *"))
    end

    test "daily at noon" do
      assert "Daily at 12 PM" == SD.describe(cron("0 12 * * *"))
    end

    test "daily at midnight" do
      assert "Daily at 12 AM" == SD.describe(cron("0 0 * * *"))
    end

    test "time with minutes" do
      assert "Daily at 2:30 PM" == SD.describe(cron("30 14 * * *"))
    end

    test "weekdays only" do
      assert "Weekdays at 8 AM" == SD.describe(cron("0 8 * * 1-5"))
    end

    test "weekends only" do
      assert "Weekends at 10 AM" == SD.describe(cron("0 10 * * 0,6"))
    end

    test "single day of week" do
      assert "Mon at 6 AM" == SD.describe(cron("0 6 * * 1"))
    end

    test "comma-separated days" do
      assert "Mon, Wed, Fri at 9 AM" == SD.describe(cron("0 9 * * 1,3,5"))
    end

    test "mixed list of ranges and singles" do
      assert "Mon, Wed-Fri at 9 AM" == SD.describe(cron("0 9 * * 1,3-5"))
    end

    test "specific day of month" do
      assert "Day 15 at 9 AM" == SD.describe(cron("0 9 15 * *"))
    end

    test "frequency restricted to specific weekdays combines instead of dropping" do
      assert "Weekdays, Every 4h" == SD.describe(cron("0 */4 * * 1-5"))
    end

    test "minute-step frequency restricted to specific weekdays combines instead of dropping" do
      assert "Weekends, Every 15m" == SD.describe(cron("*/15 * * * 0,6"))
    end

    test "out-of-range hour is rejected by the real parser, not mis-described" do
      assert "0 99 * * *" == SD.describe(cron("0 99 * * *"))
    end

    test "out-of-range minute is rejected by the real parser" do
      assert "99 9 * * *" == SD.describe(cron("99 9 * * *"))
    end

    test "day and month" do
      assert "Mar 25 at 9 AM" == SD.describe(cron("0 9 25 3 *"))
    end

    # Previously rendered the broken "Daily at Every 4h" / "Daily at Every 15m".
    test "every N hours stands alone" do
      assert "Every 4h" == SD.describe(cron("0 */4 * * *"))
    end

    test "every N minutes stands alone" do
      assert "Every 15m" == SD.describe(cron("*/15 * * * *"))
    end

    test "every minute" do
      assert "Every minute" == SD.describe(cron("* * * * *"))
    end

    test "hourly" do
      assert "Hourly" == SD.describe(cron("0 * * * *"))
    end

    test "unrecognized-but-structurally-cron falls back to raw expression" do
      assert "bad cron" == SD.describe(cron("bad cron"))
    end
  end

  describe "describe/1 — unknown type" do
    test "unknown schedule type" do
      assert "?" == SD.describe(%{schedule_type: "unknown", schedule_value: "x"})
    end

    test "nil" do
      assert "?" == SD.describe(nil)
    end
  end

  describe "preview/1 — cron form hint" do
    test "recognized expression" do
      assert "Every 15m" == SD.preview("*/15 * * * *")
      assert "Weekdays at 8 AM" == SD.preview("0 8 * * 1-5")
    end

    test "invalid expression returns nil" do
      assert nil == SD.preview("bad cron")
      assert nil == SD.preview("invalid")
    end

    test "out-of-range field returns nil, not a mis-described phrase" do
      assert nil == SD.preview("0 99 * * *")
    end

    test "non-binary returns nil" do
      assert nil == SD.preview(nil)
      assert nil == SD.preview(123)
    end
  end

  defp cron(value), do: %{schedule_type: "cron", schedule_value: value}
end
