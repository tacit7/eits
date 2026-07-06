defmodule EyeInTheSky.Sessions.EventsTest do
  use ExUnit.Case, async: true

  alias EyeInTheSky.Sessions.Events

  describe "desktop_alert_spec/2" do
    setup do
      %{session: %{name: "deploy-agent", uuid: "abc-123", status_reason: nil}}
    end

    test "failed escalates with a Session failed alert and nav path", %{session: s} do
      assert {"Session failed", "deploy-agent", "/dm/abc-123"} =
               Events.desktop_alert_spec(s, "failed")
    end

    test "waiting escalates with a Waiting for input alert", %{session: s} do
      assert {"Waiting for input", "deploy-agent", "/dm/abc-123"} =
               Events.desktop_alert_spec(s, "waiting")
    end

    test "status_reason is appended to the body when present", %{session: s} do
      s = %{s | status_reason: "exit code 1"}
      assert {"Session failed", "deploy-agent — exit code 1", _} =
               Events.desktop_alert_spec(s, "failed")
    end

    test "missing name falls back to Agent" do
      s = %{name: nil, uuid: "u1", status_reason: nil}
      assert {"Session failed", "Agent", "/dm/u1"} = Events.desktop_alert_spec(s, "failed")
    end

    test "non-urgent statuses do not escalate", %{session: s} do
      assert nil == Events.desktop_alert_spec(s, "completed")
      assert nil == Events.desktop_alert_spec(s, "idle")
      assert nil == Events.desktop_alert_spec(s, "working")
    end

    test "no path when the session has no uuid" do
      s = %{name: "x", uuid: nil, status_reason: nil}
      assert {"Session failed", "x", nil} = Events.desktop_alert_spec(s, "failed")
    end
  end
end
