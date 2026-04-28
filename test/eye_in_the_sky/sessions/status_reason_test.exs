defmodule EyeInTheSky.Sessions.StatusReasonTest do
  @moduledoc """
  Integration test for the `sessions.status_reason` enum. Exercises the actual
  changeset + DB write path so a typo in the `validate_inclusion` list surfaces
  here instead of silently breaking at runtime.
  """
  use EyeInTheSky.DataCase, async: true

  import EyeInTheSky.Factory

  alias EyeInTheSky.Sessions

  for reason <- [
        "billing_error",
        "authentication_error",
        "rate_limit_error",
        "watchdog_timeout",
        "retry_exhausted",
        "session_ended",
        "sdk_completed",
        "zombie_swept"
      ] do
    test "accepts status_reason = #{inspect(reason)}" do
      session = new_session()

      assert {:ok, updated} =
               Sessions.update_session(session, %{
                 status: "failed",
                 status_reason: unquote(reason)
               })

      assert updated.status_reason == unquote(reason)
    end
  end

  test "accepts nil status_reason (no prior reason)" do
    session = new_session()

    assert {:ok, updated} =
             Sessions.update_session(session, %{status: "failed", status_reason: nil})

    assert updated.status_reason == nil
  end

  test "rejects unknown status_reason values" do
    session = new_session()

    assert {:error, changeset} =
             Sessions.update_session(session, %{
               status: "failed",
               status_reason: "not_a_real_reason"
             })

    assert %{status_reason: ["is invalid"]} = errors_on(changeset)
  end
end
