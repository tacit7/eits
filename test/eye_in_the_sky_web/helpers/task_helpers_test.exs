defmodule EyeInTheSkyWeb.Helpers.TaskHelpersTest do
  use ExUnit.Case, async: true

  alias EyeInTheSkyWeb.Helpers.TaskHelpers

  # ---------------------------------------------------------------------------
  # format_due_date/1
  # ---------------------------------------------------------------------------

  describe "format_due_date/1" do
    test "nil returns empty string" do
      assert TaskHelpers.format_due_date(nil) == ""
    end

    test "today returns 'Today'" do
      today = Date.to_iso8601(Date.utc_today())
      assert TaskHelpers.format_due_date(today) == "Today"
    end

    test "tomorrow returns 'Tomorrow'" do
      tomorrow = Date.utc_today() |> Date.add(1) |> Date.to_iso8601()
      assert TaskHelpers.format_due_date(tomorrow) == "Tomorrow"
    end

    test "yesterday returns 'Overdue'" do
      yesterday = Date.utc_today() |> Date.add(-1) |> Date.to_iso8601()
      assert TaskHelpers.format_due_date(yesterday) == "Overdue"
    end

    test "past date further back returns 'Overdue'" do
      past = Date.utc_today() |> Date.add(-30) |> Date.to_iso8601()
      assert TaskHelpers.format_due_date(past) == "Overdue"
    end

    test "future date beyond tomorrow returns month-day format" do
      future = Date.utc_today() |> Date.add(10)
      future_str = Date.to_iso8601(future)
      expected = Calendar.strftime(future, "%b %d")
      assert TaskHelpers.format_due_date(future_str) == expected
    end

    test "accepts datetime string with time component" do
      today_with_time = Date.to_iso8601(Date.utc_today()) <> " 10:30:00"
      assert TaskHelpers.format_due_date(today_with_time) == "Today"
    end

    test "unparseable binary returns the original string" do
      assert TaskHelpers.format_due_date("not-a-date") == "not-a-date"
    end

    test "non-string non-nil returns empty string" do
      assert TaskHelpers.format_due_date(12_345) == ""
      assert TaskHelpers.format_due_date(%{}) == ""
      assert TaskHelpers.format_due_date([:a]) == ""
    end
  end

  # ---------------------------------------------------------------------------
  # due_date_class/1
  # ---------------------------------------------------------------------------

  describe "due_date_class/1" do
    test "nil returns muted class" do
      assert TaskHelpers.due_date_class(nil) == "text-base-content/30"
    end

    test "overdue date returns error class" do
      yesterday = Date.utc_today() |> Date.add(-1) |> Date.to_iso8601()
      assert TaskHelpers.due_date_class(yesterday) == "text-error font-medium"
    end

    test "today returns warning class" do
      today = Date.to_iso8601(Date.utc_today())
      assert TaskHelpers.due_date_class(today) == "text-warning font-medium"
    end

    test "tomorrow returns muted class" do
      tomorrow = Date.utc_today() |> Date.add(1) |> Date.to_iso8601()
      assert TaskHelpers.due_date_class(tomorrow) == "text-base-content/30"
    end

    test "future date returns muted class" do
      future = Date.utc_today() |> Date.add(10) |> Date.to_iso8601()
      assert TaskHelpers.due_date_class(future) == "text-base-content/30"
    end

    test "unparseable binary returns muted class" do
      assert TaskHelpers.due_date_class("bad-date") == "text-base-content/30"
    end

    test "non-string non-nil returns muted class" do
      assert TaskHelpers.due_date_class(42) == "text-base-content/30"
      assert TaskHelpers.due_date_class(%{}) == "text-base-content/30"
    end
  end

  # ---------------------------------------------------------------------------
  # overdue?/1
  # ---------------------------------------------------------------------------

  describe "overdue?/1" do
    test "nil is not overdue" do
      refute TaskHelpers.overdue?(nil)
    end

    test "yesterday is overdue" do
      yesterday = Date.utc_today() |> Date.add(-1) |> Date.to_iso8601()
      assert TaskHelpers.overdue?(yesterday)
    end

    test "today is not overdue" do
      today = Date.to_iso8601(Date.utc_today())
      refute TaskHelpers.overdue?(today)
    end

    test "tomorrow is not overdue" do
      tomorrow = Date.utc_today() |> Date.add(1) |> Date.to_iso8601()
      refute TaskHelpers.overdue?(tomorrow)
    end

    test "far future is not overdue" do
      future = Date.utc_today() |> Date.add(90) |> Date.to_iso8601()
      refute TaskHelpers.overdue?(future)
    end

    test "unparseable binary is not overdue" do
      refute TaskHelpers.overdue?("not-a-date")
    end

    test "non-string non-nil is not overdue" do
      refute TaskHelpers.overdue?(42)
      refute TaskHelpers.overdue?(%{})
    end
  end

  # ---------------------------------------------------------------------------
  # due_today?/1
  # ---------------------------------------------------------------------------

  describe "due_today?/1" do
    test "nil is not due today" do
      refute TaskHelpers.due_today?(nil)
    end

    test "today is due today" do
      today = Date.to_iso8601(Date.utc_today())
      assert TaskHelpers.due_today?(today)
    end

    test "yesterday is not due today" do
      yesterday = Date.utc_today() |> Date.add(-1) |> Date.to_iso8601()
      refute TaskHelpers.due_today?(yesterday)
    end

    test "tomorrow is not due today" do
      tomorrow = Date.utc_today() |> Date.add(1) |> Date.to_iso8601()
      refute TaskHelpers.due_today?(tomorrow)
    end

    test "future date is not due today" do
      future = Date.utc_today() |> Date.add(5) |> Date.to_iso8601()
      refute TaskHelpers.due_today?(future)
    end

    test "unparseable binary is not due today" do
      refute TaskHelpers.due_today?("bad-date")
    end

    test "non-string non-nil is not due today" do
      refute TaskHelpers.due_today?(123)
    end
  end

  # ---------------------------------------------------------------------------
  # format_date_input/1
  # ---------------------------------------------------------------------------

  describe "format_date_input/1" do
    test "nil returns empty string" do
      assert TaskHelpers.format_date_input(nil) == ""
    end

    test "datetime string with time returns date portion only" do
      assert TaskHelpers.format_date_input("2025-01-15 10:30:00") == "2025-01-15"
    end

    test "date-only string is returned unchanged" do
      assert TaskHelpers.format_date_input("2025-06-20") == "2025-06-20"
    end

    test "ISO8601 datetime with T separator returns date portion" do
      assert TaskHelpers.format_date_input("2025-03-22T14:05:00Z") == "2025-03-22"
    end

    test "non-string non-nil returns empty string" do
      assert TaskHelpers.format_date_input(20_250_115) == ""
      assert TaskHelpers.format_date_input(%{date: "2025-01-15"}) == ""
    end
  end

  # ---------------------------------------------------------------------------
  # days_since_update/1
  # ---------------------------------------------------------------------------

  describe "days_since_update/1" do
    test "nil returns nil" do
      assert TaskHelpers.days_since_update(nil) == nil
    end

    test "DateTime struct from 5 days ago returns 5" do
      five_days_ago = DateTime.add(DateTime.utc_now(), -5 * 86_400, :second)
      assert TaskHelpers.days_since_update(five_days_ago) == 5
    end

    test "DateTime struct from 2 days ago returns 2" do
      two_days_ago = DateTime.add(DateTime.utc_now(), -2 * 86_400, :second)
      assert TaskHelpers.days_since_update(two_days_ago) == 2
    end

    test "DateTime struct from just now returns 0" do
      just_now = DateTime.add(DateTime.utc_now(), -30, :second)
      assert TaskHelpers.days_since_update(just_now) == 0
    end

    test "ISO8601 string from 2 days ago returns 2" do
      two_days_ago =
        DateTime.utc_now()
        |> DateTime.add(-2 * 86_400, :second)
        |> DateTime.to_iso8601()

      assert TaskHelpers.days_since_update(two_days_ago) == 2
    end

    test "ISO8601 string from 7 days ago returns 7" do
      seven_days_ago =
        DateTime.utc_now()
        |> DateTime.add(-7 * 86_400, :second)
        |> DateTime.to_iso8601()

      assert TaskHelpers.days_since_update(seven_days_ago) == 7
    end

    test "unparseable string returns nil" do
      assert TaskHelpers.days_since_update("not-a-datetime") == nil
    end

    test "non-string non-nil non-DateTime returns nil" do
      assert TaskHelpers.days_since_update(12_345) == nil
      assert TaskHelpers.days_since_update(%{}) == nil
    end
  end

  # ---------------------------------------------------------------------------
  # card_aging_indicator/1
  # ---------------------------------------------------------------------------

  describe "card_aging_indicator/1" do
    test "nil returns nil" do
      assert TaskHelpers.card_aging_indicator(nil) == nil
    end

    test "fresh card (3 days old) returns nil" do
      recent = DateTime.add(DateTime.utc_now(), -3 * 86_400, :second)
      assert TaskHelpers.card_aging_indicator(recent) == nil
    end

    test "just under threshold (6 days old) returns nil" do
      six_days = DateTime.add(DateTime.utc_now(), -6 * 86_400, :second)
      assert TaskHelpers.card_aging_indicator(six_days) == nil
    end

    test "7 days old returns warning idle indicator" do
      seven_days = DateTime.add(DateTime.utc_now(), -7 * 86_400, :second)
      {border_class, label} = TaskHelpers.card_aging_indicator(seven_days)
      assert border_class == "border-l-2 border-l-warning/60"
      assert String.ends_with?(label, "d idle")
    end

    test "10 days old returns warning idle indicator" do
      ten_days = DateTime.add(DateTime.utc_now(), -10 * 86_400, :second)
      {border_class, label} = TaskHelpers.card_aging_indicator(ten_days)
      assert border_class == "border-l-2 border-l-warning/60"
      assert label == "10d idle"
    end

    test "14 days old returns error stale indicator" do
      fourteen_days = DateTime.add(DateTime.utc_now(), -14 * 86_400, :second)
      {border_class, label} = TaskHelpers.card_aging_indicator(fourteen_days)
      assert border_class == "border-l-2 border-l-error/60"
      assert label == "14d stale"
    end

    test "20 days old returns error stale indicator" do
      twenty_days = DateTime.add(DateTime.utc_now(), -20 * 86_400, :second)
      {border_class, label} = TaskHelpers.card_aging_indicator(twenty_days)
      assert border_class == "border-l-2 border-l-error/60"
      assert label == "20d stale"
    end

    test "label includes the actual day count" do
      days = 9
      nine_days = DateTime.add(DateTime.utc_now(), -days * 86_400, :second)
      {_border, label} = TaskHelpers.card_aging_indicator(nine_days)
      assert String.starts_with?(label, "#{days}d")
    end

    test "accepts ISO8601 string input" do
      old_string =
        DateTime.utc_now()
        |> DateTime.add(-10 * 86_400, :second)
        |> DateTime.to_iso8601()

      assert {_border, _label} = TaskHelpers.card_aging_indicator(old_string)
    end
  end
end
