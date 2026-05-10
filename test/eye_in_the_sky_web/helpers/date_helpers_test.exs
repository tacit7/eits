defmodule EyeInTheSkyWeb.Helpers.DateHelpersTest do
  use ExUnit.Case, async: true

  alias EyeInTheSkyWeb.Helpers.DateHelpers

  # ---------------------------------------------------------------------------
  # coerce_datetime/1
  # ---------------------------------------------------------------------------
  describe "coerce_datetime/1" do
    test "nil returns epoch datetime" do
      assert DateHelpers.coerce_datetime(nil) == ~U[1970-01-01 00:00:00Z]
    end

    test "DateTime passthrough" do
      dt = ~U[2025-06-01 12:00:00Z]
      assert DateHelpers.coerce_datetime(dt) == dt
    end

    test "NaiveDateTime converted to UTC DateTime" do
      ndt = ~N[2025-06-01 12:00:00]
      result = DateHelpers.coerce_datetime(ndt)
      assert %DateTime{} = result
      assert result.year == 2025
      assert result.month == 6
      assert result.day == 1
      assert result.time_zone == "Etc/UTC"
    end

    test "valid Go-format string returns parsed DateTime" do
      result = DateHelpers.coerce_datetime("2025-01-15 10:30:45.123 +0000 UTC")
      assert %DateTime{} = result
      assert result.year == 2025
      assert result.month == 1
      assert result.day == 15
      assert result.hour == 10
      assert result.minute == 30
      assert result.second == 45
    end

    test "ISO8601-only string (no space) falls back to epoch because parse_datetime needs space-separated Go format" do
      # coerce_datetime delegates to parse_datetime, which splits on spaces.
      # ISO8601 strings like "2025-01-15T10:30:45Z" have no space-separated timezone
      # field, so parse_datetime returns :error and coerce_datetime returns epoch.
      result = DateHelpers.coerce_datetime("2025-01-15T10:30:45Z")
      assert result == ~U[1970-01-01 00:00:00Z]
    end

    test "unparseable string returns epoch datetime" do
      assert DateHelpers.coerce_datetime("not-a-date") == ~U[1970-01-01 00:00:00Z]
    end

    test "unknown type returns epoch datetime" do
      assert DateHelpers.coerce_datetime(42) == ~U[1970-01-01 00:00:00Z]
      assert DateHelpers.coerce_datetime(%{}) == ~U[1970-01-01 00:00:00Z]
      assert DateHelpers.coerce_datetime([]) == ~U[1970-01-01 00:00:00Z]
    end
  end

  # ---------------------------------------------------------------------------
  # parse_updated_at/1
  # ---------------------------------------------------------------------------
  describe "parse_updated_at/1" do
    test "struct with nil updated_at returns epoch datetime" do
      assert DateHelpers.parse_updated_at(%{updated_at: nil}) == ~U[1970-01-01 00:00:00Z]
    end

    test "struct with DateTime updated_at returns that DateTime" do
      dt = ~U[2025-03-10 08:00:00Z]
      assert DateHelpers.parse_updated_at(%{updated_at: dt}) == dt
    end

    test "struct with valid Go-format string updated_at returns parsed DateTime" do
      result = DateHelpers.parse_updated_at(%{updated_at: "2025-03-10 08:00:00.000 +0000 UTC"})
      assert %DateTime{} = result
      assert result.year == 2025
      assert result.month == 3
      assert result.day == 10
    end

    test "struct with unparseable string updated_at returns epoch datetime" do
      assert DateHelpers.parse_updated_at(%{updated_at: "garbage"}) == ~U[1970-01-01 00:00:00Z]
    end
  end

  # ---------------------------------------------------------------------------
  # parse_datetime/1
  # ---------------------------------------------------------------------------
  describe "parse_datetime/1" do
    test "valid Go format with UTC timezone" do
      assert {:ok, dt} = DateHelpers.parse_datetime("2025-01-15 10:30:45.123456789 +0000 UTC")
      assert dt.year == 2025
      assert dt.month == 1
      assert dt.day == 15
      assert dt.hour == 10
      assert dt.minute == 30
      assert dt.second == 45
    end

    test "valid Go format with offset timezone" do
      assert {:ok, dt} = DateHelpers.parse_datetime("2025-06-20 14:00:00.000 -0700 MST")
      assert dt.year == 2025
      assert dt.month == 6
      assert dt.day == 20
    end

    test "valid Go format minimal (no nanoseconds)" do
      assert {:ok, dt} = DateHelpers.parse_datetime("2025-01-15 10:30:45 +0000 UTC")
      assert dt.hour == 10
      assert dt.minute == 30
      assert dt.second == 45
    end

    test "invalid string returns :error" do
      assert :error = DateHelpers.parse_datetime("not-a-date")
    end

    test "empty string returns :error" do
      assert :error = DateHelpers.parse_datetime("")
    end

    test "nil returns :error" do
      assert :error = DateHelpers.parse_datetime(nil)
    end

    test "integer returns :error" do
      assert :error = DateHelpers.parse_datetime(12_345)
    end

    test "only date part (no space) returns :error" do
      assert :error = DateHelpers.parse_datetime("2025-01-15")
    end
  end

  # ---------------------------------------------------------------------------
  # relative_time/1
  # ---------------------------------------------------------------------------
  describe "relative_time/1" do
    test "nil returns em-dash" do
      assert DateHelpers.relative_time(nil) == "—"
    end

    test "30 seconds ago returns 'just now'" do
      dt = DateTime.add(DateTime.utc_now(), -30, :second)
      assert DateHelpers.relative_time(dt) == "just now"
    end

    test "90 seconds ago returns '1m ago'" do
      dt = DateTime.add(DateTime.utc_now(), -90, :second)
      assert DateHelpers.relative_time(dt) == "1m ago"
    end

    test "5 minutes ago returns '5m ago'" do
      dt = DateTime.add(DateTime.utc_now(), -(5 * 60), :second)
      assert DateHelpers.relative_time(dt) == "5m ago"
    end

    test "2 hours ago returns '2h ago'" do
      dt = DateTime.add(DateTime.utc_now(), -(2 * 3600), :second)
      assert DateHelpers.relative_time(dt) == "2h ago"
    end

    test "yesterday (25 hours ago) returns 'yesterday'" do
      dt = DateTime.add(DateTime.utc_now(), -(25 * 3600), :second)
      assert DateHelpers.relative_time(dt) == "yesterday"
    end

    test "3 days ago returns '3d ago'" do
      dt = DateTime.add(DateTime.utc_now(), -(3 * 86_400), :second)
      assert DateHelpers.relative_time(dt) == "3d ago"
    end

    test "10 days ago returns week-based result" do
      dt = DateTime.add(DateTime.utc_now(), -(10 * 86_400), :second)
      # 10 days = 1 week bucket
      assert DateHelpers.relative_time(dt) == "1w ago"
    end

    test "60 days ago returns formatted date (beyond weekly bucket)" do
      dt = DateTime.add(DateTime.utc_now(), -(60 * 86_400), :second)
      result = DateHelpers.relative_time(dt)
      # Over 30 days falls through to format_datetime_short which returns e.g. "Mar 11"
      assert is_binary(result)
      refute result == "—"
    end

    test "NaiveDateTime is handled" do
      ndt = NaiveDateTime.add(NaiveDateTime.utc_now(), -90, :second)
      assert DateHelpers.relative_time(ndt) == "1m ago"
    end

    test "unknown type returns em-dash" do
      assert DateHelpers.relative_time(42) == "—"
    end

    test "valid Go-format string returns relative time" do
      # 5 minutes ago as a Go-format string — build relative to now
      past = DateTime.add(DateTime.utc_now(), -(5 * 60), :second)
      str = Calendar.strftime(past, "%Y-%m-%d %H:%M:%S.000 +0000 UTC")
      assert DateHelpers.relative_time(str) == "5m ago"
    end
  end

  # ---------------------------------------------------------------------------
  # format_datetime_full/1
  # ---------------------------------------------------------------------------
  describe "format_datetime_full/1" do
    test "nil returns empty string" do
      assert DateHelpers.format_datetime_full(nil) == ""
    end

    test "DateTime returns formatted full timestamp" do
      dt = ~U[2025-01-15 10:30:45Z]
      assert DateHelpers.format_datetime_full(dt) == "2025-01-15 10:30:45 UTC"
    end

    test "Go-format binary string extracts date and time" do
      result = DateHelpers.format_datetime_full("2025-01-15 10:30:45.123 +0000 UTC")
      assert result == "2025-01-15 10:30:45"
    end

    test "binary with only two parts returns date + time slice" do
      result = DateHelpers.format_datetime_full("2025-01-15 10:30:45")
      assert result == "2025-01-15 10:30:45"
    end

    test "junk binary that cannot be split returns the raw string" do
      result = DateHelpers.format_datetime_full("nodatetime")
      assert result == "nodatetime"
    end

    test "unknown type returns empty string" do
      assert DateHelpers.format_datetime_full(42) == ""
    end
  end

  # ---------------------------------------------------------------------------
  # format_datetime_short/1
  # ---------------------------------------------------------------------------
  describe "format_datetime_short/1" do
    test "DateTime returns 'Mon DD' abbreviation" do
      dt = ~U[2025-01-15 10:30:00Z]
      assert DateHelpers.format_datetime_short(dt) == "Jan 15"
    end

    test "date string 'YYYY-MM-DD' returns abbreviated month and day" do
      assert DateHelpers.format_datetime_short("2025-01-15") == "Jan 15"
    end

    test "Go-format datetime string returns abbreviated month and day" do
      result = DateHelpers.format_datetime_short("2025-06-20 14:00:00.000 +0000 UTC")
      assert result == "Jun 20"
    end

    test "junk string with no dashes returns the raw string" do
      assert DateHelpers.format_datetime_short("junk") == "junk"
    end

    test "nil returns em-dash" do
      assert DateHelpers.format_datetime_short(nil) == "—"
    end

    test "integer returns em-dash" do
      assert DateHelpers.format_datetime_short(999) == "—"
    end
  end

  # ---------------------------------------------------------------------------
  # format_time/1
  # ---------------------------------------------------------------------------
  describe "format_time/1" do
    test "nil returns empty string" do
      assert DateHelpers.format_time(nil) == ""
    end

    test "DateTime returns HH:MM" do
      dt = ~U[2025-01-15 09:05:00Z]
      assert DateHelpers.format_time(dt) == "09:05"
    end

    test "NaiveDateTime returns HH:MM" do
      ndt = ~N[2025-01-15 14:30:00]
      assert DateHelpers.format_time(ndt) == "14:30"
    end

    test "ISO8601 binary string returns HH:MM" do
      assert DateHelpers.format_time("2025-01-15T09:05:00Z") == "09:05"
    end

    test "invalid binary returns empty string" do
      assert DateHelpers.format_time("not-a-time") == ""
    end

    test "unknown type returns empty string" do
      assert DateHelpers.format_time(42) == ""
    end
  end

  # ---------------------------------------------------------------------------
  # format_datetime_short_time/1
  # ---------------------------------------------------------------------------
  describe "format_datetime_short_time/1" do
    test "nil returns empty string" do
      assert DateHelpers.format_datetime_short_time(nil) == ""
    end

    test "DateTime returns 'Mon DD, HH:MM'" do
      dt = ~U[2025-01-15 09:05:00Z]
      assert DateHelpers.format_datetime_short_time(dt) == "Jan 15, 09:05"
    end

    test "NaiveDateTime returns 'Mon DD, HH:MM'" do
      ndt = ~N[2025-06-20 14:30:00]
      assert DateHelpers.format_datetime_short_time(ndt) == "Jun 20, 14:30"
    end

    test "ISO8601 binary string returns 'Mon DD, HH:MM'" do
      assert DateHelpers.format_datetime_short_time("2025-01-15T09:05:00Z") == "Jan 15, 09:05"
    end

    test "invalid binary returns empty string" do
      assert DateHelpers.format_datetime_short_time("garbage") == ""
    end

    test "unknown type returns empty string" do
      assert DateHelpers.format_datetime_short_time(%{}) == ""
    end
  end

  # ---------------------------------------------------------------------------
  # format_relative_time/1
  # ---------------------------------------------------------------------------
  describe "format_relative_time/1" do
    test "nil returns dash" do
      assert DateHelpers.format_relative_time(nil) == "-"
    end

    test "future DateTime 5 minutes out returns 'in 5m'" do
      dt = DateTime.add(DateTime.utc_now(), 5 * 60 + 30, :second)
      assert DateHelpers.format_relative_time(dt) == "in 5m"
    end

    test "future DateTime 2 hours out returns 'in 2h'" do
      dt = DateTime.add(DateTime.utc_now(), 2 * 3600 + 60, :second)
      assert DateHelpers.format_relative_time(dt) == "in 2h"
    end

    test "future DateTime 3 days out returns 'in 3d'" do
      dt = DateTime.add(DateTime.utc_now(), 3 * 86_400 + 60, :second)
      assert DateHelpers.format_relative_time(dt) == "in 3d"
    end

    test "future DateTime 30 seconds out returns 'in 30s' form" do
      dt = DateTime.add(DateTime.utc_now(), 30, :second)
      result = DateHelpers.format_relative_time(dt)
      assert String.starts_with?(result, "in ") and String.ends_with?(result, "s")
    end

    test "past DateTime 2 hours ago returns '2h ago'" do
      dt = DateTime.add(DateTime.utc_now(), -(2 * 3600 + 60), :second)
      assert DateHelpers.format_relative_time(dt) == "2h ago"
    end

    test "past DateTime 5 minutes ago returns '5m ago'" do
      dt = DateTime.add(DateTime.utc_now(), -(5 * 60 + 30), :second)
      assert DateHelpers.format_relative_time(dt) == "5m ago"
    end

    test "NaiveDateTime in the future returns 'in Nm' form" do
      ndt = NaiveDateTime.add(NaiveDateTime.utc_now(), 5 * 60 + 30, :second)
      assert DateHelpers.format_relative_time(ndt) == "in 5m"
    end

    test "NaiveDateTime in the past returns 'Nm ago' form" do
      ndt = NaiveDateTime.add(NaiveDateTime.utc_now(), -(5 * 60 + 30), :second)
      assert DateHelpers.format_relative_time(ndt) == "5m ago"
    end

    test "ISO8601 binary string in the future returns relative string" do
      future = DateTime.add(DateTime.utc_now(), 5 * 60 + 30, :second)
      iso = DateTime.to_iso8601(future)
      assert DateHelpers.format_relative_time(iso) == "in 5m"
    end

    test "ISO8601 binary string in the past returns relative string" do
      past = DateTime.add(DateTime.utc_now(), -(2 * 3600 + 60), :second)
      iso = DateTime.to_iso8601(past)
      assert DateHelpers.format_relative_time(iso) == "2h ago"
    end

    test "invalid binary returns dash" do
      assert DateHelpers.format_relative_time("not-a-date") == "-"
    end

    test "unknown type returns dash" do
      assert DateHelpers.format_relative_time(42) == "-"
    end
  end

  # ---------------------------------------------------------------------------
  # month_name/1
  # ---------------------------------------------------------------------------
  describe "month_name/1" do
    test "maps '1' through '12' to correct abbreviations" do
      expected = [
        {"1", "Jan"},
        {"2", "Feb"},
        {"3", "Mar"},
        {"4", "Apr"},
        {"5", "May"},
        {"6", "Jun"},
        {"7", "Jul"},
        {"8", "Aug"},
        {"9", "Sep"},
        {"10", "Oct"},
        {"11", "Nov"},
        {"12", "Dec"}
      ]

      for {input, abbrev} <- expected do
        assert DateHelpers.month_name(input) == abbrev,
               "expected month_name(#{inspect(input)}) == #{inspect(abbrev)}"
      end
    end

    test "unknown value passes through unchanged" do
      assert DateHelpers.month_name("*") == "*"
      assert DateHelpers.month_name("0") == "0"
      assert DateHelpers.month_name("13") == "13"
    end
  end

  # ---------------------------------------------------------------------------
  # format_date/1
  # ---------------------------------------------------------------------------
  describe "format_date/1" do
    test "nil returns em-dash" do
      assert DateHelpers.format_date(nil) == "—"
    end

    test "timestamp string returns only date portion" do
      assert DateHelpers.format_date("2025-01-15 10:30:00") == "2025-01-15"
    end

    test "date-only string returns the string unchanged" do
      assert DateHelpers.format_date("2025-01-15") == "2025-01-15"
    end

    test "Go-format timestamp returns date portion" do
      assert DateHelpers.format_date("2025-01-15 10:30:00.000 +0000 UTC") == "2025-01-15"
    end

    test "non-string returns em-dash" do
      assert DateHelpers.format_date(42) == "—"
      assert DateHelpers.format_date(%{}) == "—"
      assert DateHelpers.format_date([]) == "—"
    end
  end
end
