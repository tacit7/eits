defmodule EyeInTheSky.ScheduledJobs.CronParserTest do
  use ExUnit.Case, async: true

  alias EyeInTheSky.ScheduledJobs.CronParser

  describe "compute_next_run_at/4 — interval" do
    test "returns a future datetime for a valid positive interval" do
      from = ~N[2026-01-01 00:00:00]
      result = CronParser.compute_next_run_at("interval", "60", from)
      assert result == DateTime.from_naive!(~N[2026-01-01 00:01:00], "Etc/UTC")
    end

    test "returns nil for zero interval" do
      from = ~N[2026-01-01 00:00:00]
      assert CronParser.compute_next_run_at("interval", "0", from) == nil
    end

    test "returns nil for negative interval" do
      from = ~N[2026-01-01 00:00:00]
      assert CronParser.compute_next_run_at("interval", "-10", from) == nil
    end

    test "returns nil for non-numeric interval string" do
      from = ~N[2026-01-01 00:00:00]
      assert CronParser.compute_next_run_at("interval", "bad", from) == nil
    end

    test "returns nil for empty interval string" do
      from = ~N[2026-01-01 00:00:00]
      assert CronParser.compute_next_run_at("interval", "", from) == nil
    end
  end

  describe "compute_next_run_at/4 — cron" do
    test "returns next run for valid cron expression" do
      from = ~N[2026-01-01 00:00:00]
      result = CronParser.compute_next_run_at("cron", "* * * * *", from)
      assert %DateTime{} = result
      # cron scheduler returns current or next matching time; result is >= from
      assert DateTime.compare(result, DateTime.from_naive!(from, "Etc/UTC")) in [:gt, :eq]
    end

    test "returns nil for invalid cron expression" do
      from = ~N[2026-01-01 00:00:00]
      assert CronParser.compute_next_run_at("cron", "not a cron", from) == nil
    end

    test "returns nil for invalid timezone without raising" do
      from = ~N[2026-01-01 00:00:00]
      assert CronParser.compute_next_run_at("cron", "* * * * *", from, "Not/AZone") == nil
    end

    test "handles valid non-UTC timezone" do
      from = ~N[2026-01-01 00:00:00]
      result = CronParser.compute_next_run_at("cron", "* * * * *", from, "America/New_York")
      assert %DateTime{} = result
    end
  end
end
