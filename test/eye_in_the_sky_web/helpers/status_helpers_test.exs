defmodule EyeInTheSkyWeb.Helpers.StatusHelpersTest do
  use ExUnit.Case, async: true

  alias EyeInTheSkyWeb.Helpers.StatusHelpers

  # ── derive_display_status/1 ────────────────────────────────────────────────

  describe "derive_display_status/1 — pass-through statuses" do
    test "working passes through unchanged" do
      assert StatusHelpers.derive_display_status(%{status: "working"}) == "working"
    end

    test "compacting passes through unchanged" do
      assert StatusHelpers.derive_display_status(%{status: "compacting"}) == "compacting"
    end

    test "completed passes through unchanged" do
      assert StatusHelpers.derive_display_status(%{status: "completed"}) == "completed"
    end

    test "nil status passes through as nil" do
      assert StatusHelpers.derive_display_status(%{status: nil}) == nil
    end

    test "unknown status passes through unchanged" do
      assert StatusHelpers.derive_display_status(%{status: "some_future_status"}) ==
               "some_future_status"
    end
  end

  describe "derive_display_status/1 — idle tiers via status" do
    test "idle with nil last_activity_at returns idle" do
      assert StatusHelpers.derive_display_status(%{status: "idle", last_activity_at: nil}) ==
               "idle"
    end

    test "idle with recent activity (< 1h) returns idle" do
      recent = DateTime.add(DateTime.utc_now(), -30, :minute)

      assert StatusHelpers.derive_display_status(%{
               status: "idle",
               last_activity_at: recent
             }) == "idle"
    end

    test "idle with activity 2h ago returns idle_stale" do
      two_hours_ago = DateTime.add(DateTime.utc_now(), -7200, :second)

      assert StatusHelpers.derive_display_status(%{
               status: "idle",
               last_activity_at: two_hours_ago
             }) == "idle_stale"
    end

    test "idle with activity 25h ago returns idle_dead" do
      old = DateTime.add(DateTime.utc_now(), -25 * 3600, :second)

      assert StatusHelpers.derive_display_status(%{
               status: "idle",
               last_activity_at: old
             }) == "idle_dead"
    end
  end

  describe "derive_display_status/1 — failed tiers via status" do
    test "failed with nil status_reason returns failed" do
      assert StatusHelpers.derive_display_status(%{status: "failed", status_reason: nil}) ==
               "failed"
    end

    test "failed on agent map without status_reason key returns failed" do
      # Agent structs have no status_reason — Map.get must default, not raise
      assert StatusHelpers.derive_display_status(%{status: "failed"}) == "failed"
    end

    test "failed with billing_error returns failed_billing" do
      assert StatusHelpers.derive_display_status(%{
               status: "failed",
               status_reason: "billing_error"
             }) == "failed_billing"
    end

    test "failed with authentication_error returns failed_auth" do
      assert StatusHelpers.derive_display_status(%{
               status: "failed",
               status_reason: "authentication_error"
             }) == "failed_auth"
    end

    test "failed with rate_limit_error returns failed_rate_limit" do
      assert StatusHelpers.derive_display_status(%{
               status: "failed",
               status_reason: "rate_limit_error"
             }) == "failed_rate_limit"
    end

    test "failed with watchdog_timeout returns failed_timeout" do
      assert StatusHelpers.derive_display_status(%{
               status: "failed",
               status_reason: "watchdog_timeout"
             }) == "failed_timeout"
    end

    test "failed with retry_exhausted returns failed_retry_exhausted" do
      assert StatusHelpers.derive_display_status(%{
               status: "failed",
               status_reason: "retry_exhausted"
             }) == "failed_retry_exhausted"
    end

    test "failed with unknown reason falls back to generic failed" do
      assert StatusHelpers.derive_display_status(%{
               status: "failed",
               status_reason: "some_new_error"
             }) == "failed"
    end
  end

  # ── failed_tier/1 ─────────────────────────────────────────────────────────

  describe "failed_tier/1" do
    test "billing_error -> failed_billing" do
      assert StatusHelpers.failed_tier("billing_error") == "failed_billing"
    end

    test "authentication_error -> failed_auth" do
      assert StatusHelpers.failed_tier("authentication_error") == "failed_auth"
    end

    test "rate_limit_error -> failed_rate_limit" do
      assert StatusHelpers.failed_tier("rate_limit_error") == "failed_rate_limit"
    end

    test "watchdog_timeout -> failed_timeout" do
      assert StatusHelpers.failed_tier("watchdog_timeout") == "failed_timeout"
    end

    test "retry_exhausted -> failed_retry_exhausted" do
      assert StatusHelpers.failed_tier("retry_exhausted") == "failed_retry_exhausted"
    end

    test "nil reason -> failed" do
      assert StatusHelpers.failed_tier(nil) == "failed"
    end

    test "unknown string reason -> failed" do
      assert StatusHelpers.failed_tier("crash") == "failed"
      assert StatusHelpers.failed_tier("unknown") == "failed"
    end
  end

  # ── idle_tier/1 ───────────────────────────────────────────────────────────
  # Thresholds (from implementation):
  #   nil last_activity_at  → "idle"
  #   < 1h                  → "idle"
  #   >= 1h and < 24h       → "idle_stale"
  #   >= 24h                → "idle_dead"

  describe "idle_tier/1" do
    test "nil last_activity_at returns idle" do
      assert StatusHelpers.idle_tier(%{last_activity_at: nil}) == "idle"
    end

    test "activity 30 seconds ago returns idle" do
      recent = DateTime.add(DateTime.utc_now(), -30, :second)
      assert StatusHelpers.idle_tier(%{last_activity_at: recent}) == "idle"
    end

    test "activity 59 minutes ago returns idle" do
      # Just under the 1h threshold — should still be "idle"
      just_under = DateTime.add(DateTime.utc_now(), -59 * 60, :second)
      assert StatusHelpers.idle_tier(%{last_activity_at: just_under}) == "idle"
    end

    test "activity exactly 1h ago returns idle_stale" do
      one_hour_ago = DateTime.add(DateTime.utc_now(), -3600, :second)
      assert StatusHelpers.idle_tier(%{last_activity_at: one_hour_ago}) == "idle_stale"
    end

    test "activity 2h ago returns idle_stale" do
      two_hours_ago = DateTime.add(DateTime.utc_now(), -2 * 3600, :second)
      assert StatusHelpers.idle_tier(%{last_activity_at: two_hours_ago}) == "idle_stale"
    end

    test "activity 23h ago returns idle_stale" do
      # Just under 24h — still stale, not dead
      just_under_24h = DateTime.add(DateTime.utc_now(), -23 * 3600, :second)
      assert StatusHelpers.idle_tier(%{last_activity_at: just_under_24h}) == "idle_stale"
    end

    test "activity exactly 24h ago returns idle_dead" do
      twenty_four_hours_ago = DateTime.add(DateTime.utc_now(), -24 * 3600, :second)
      assert StatusHelpers.idle_tier(%{last_activity_at: twenty_four_hours_ago}) == "idle_dead"
    end

    test "activity 48h ago returns idle_dead" do
      old = DateTime.add(DateTime.utc_now(), -48 * 3600, :second)
      assert StatusHelpers.idle_tier(%{last_activity_at: old}) == "idle_dead"
    end
  end

  # ── stale?/1 ──────────────────────────────────────────────────────────────
  # Stale = idle_tier in ["idle_stale", "idle_dead"] (>= 1h inactive)

  describe "stale?/1" do
    test "nil last_activity_at is not stale" do
      refute StatusHelpers.stale?(%{last_activity_at: nil})
    end

    test "activity 30 seconds ago is not stale" do
      recent = DateTime.add(DateTime.utc_now(), -30, :second)
      refute StatusHelpers.stale?(%{last_activity_at: recent})
    end

    test "activity 59 minutes ago is not stale" do
      just_under = DateTime.add(DateTime.utc_now(), -59 * 60, :second)
      refute StatusHelpers.stale?(%{last_activity_at: just_under})
    end

    test "activity 1h ago is stale" do
      one_hour_ago = DateTime.add(DateTime.utc_now(), -3600, :second)
      assert StatusHelpers.stale?(%{last_activity_at: one_hour_ago})
    end

    test "activity 2h ago is stale" do
      two_hours_ago = DateTime.add(DateTime.utc_now(), -2 * 3600, :second)
      assert StatusHelpers.stale?(%{last_activity_at: two_hours_ago})
    end

    test "activity 24h+ ago is stale (idle_dead)" do
      old = DateTime.add(DateTime.utc_now(), -25 * 3600, :second)
      assert StatusHelpers.stale?(%{last_activity_at: old})
    end
  end
end
