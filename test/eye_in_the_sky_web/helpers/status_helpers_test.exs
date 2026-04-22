defmodule EyeInTheSkyWeb.Helpers.StatusHelpersTest do
  use ExUnit.Case, async: true

  alias EyeInTheSkyWeb.Helpers.StatusHelpers

  describe "derive_display_status/2 — failed tiers" do
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

    test "failed with nil status_reason returns generic failed" do
      assert StatusHelpers.derive_display_status(%{status: "failed", status_reason: nil}) ==
               "failed"
    end

    test "failed on agent struct (no status_reason field) returns generic failed" do
      # Agent schema has no status_reason — Map.get must default to nil, not raise.
      assert StatusHelpers.derive_display_status(%{status: "failed"}) == "failed"
    end
  end

  describe "derive_display_status/2 — non-failed statuses unchanged" do
    test "working" do
      assert StatusHelpers.derive_display_status(%{status: "working"}) == "working"
    end

    test "completed" do
      assert StatusHelpers.derive_display_status(%{status: "completed"}) == "completed"
    end

    test "idle with no activity returns idle" do
      assert StatusHelpers.derive_display_status(%{status: "idle", last_activity_at: nil}) ==
               "idle"
    end
  end

  describe "failed_tier/1" do
    test "maps known reasons to display statuses" do
      assert StatusHelpers.failed_tier("billing_error") == "failed_billing"
      assert StatusHelpers.failed_tier("authentication_error") == "failed_auth"
      assert StatusHelpers.failed_tier("rate_limit_error") == "failed_rate_limit"
      assert StatusHelpers.failed_tier("watchdog_timeout") == "failed_timeout"
      assert StatusHelpers.failed_tier("retry_exhausted") == "failed_retry_exhausted"
    end

    test "unknown or nil reasons fall back to generic failed" do
      assert StatusHelpers.failed_tier(nil) == "failed"
      assert StatusHelpers.failed_tier("unknown_reason") == "failed"
    end
  end
end
