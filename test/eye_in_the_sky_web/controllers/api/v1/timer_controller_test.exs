defmodule EyeInTheSkyWeb.Api.V1.TimerControllerTest do
  use EyeInTheSkyWeb.ConnCase, async: false

  import EyeInTheSky.Factory

  alias EyeInTheSky.Accounts.ApiKey
  alias EyeInTheSky.OrchestratorTimers

  defp api_conn do
    token = "test_api_key_#{System.unique_integer([:positive])}"
    {:ok, _} = ApiKey.create(token, "test")
    Phoenix.ConnTest.build_conn() |> Plug.Conn.put_req_header("authorization", "Bearer #{token}")
  end

  setup do
    agent = create_agent()
    session = create_session(agent)
    # Clean up any timer left from a previous test
    OrchestratorTimers.cancel(session.id)
    {:ok, conn: api_conn(), session: session}
  end

  # ---- GET /api/v1/sessions/:session_id/timer ----

  describe "GET /api/v1/sessions/:session_id/timer" do
    test "returns 404 when no active timer", %{conn: conn, session: session} do
      conn = get(conn, ~p"/api/v1/sessions/#{session.id}/timer")
      assert json_response(conn, 404)["error"] =~ "no active timer"
    end

    test "returns active timer when scheduled", %{conn: conn, session: session} do
      OrchestratorTimers.schedule_once(session.id, 60_000, "hello")
      conn = get(conn, ~p"/api/v1/sessions/#{session.id}/timer")
      resp = json_response(conn, 200)
      assert resp["success"] == true
      assert resp["timer"]["mode"] == "once"
      assert resp["timer"]["interval_ms"] == 60_000
      assert resp["timer"]["message"] == "hello"
    end

    test "accepts UUID as session_id", %{conn: conn, session: session} do
      conn = get(conn, ~p"/api/v1/sessions/#{session.uuid}/timer")
      assert json_response(conn, 404)["error"] =~ "no active timer"
    end

    test "returns 404 for unknown session", %{conn: conn} do
      conn = get(conn, ~p"/api/v1/sessions/9999999/timer")
      assert json_response(conn, 404)
    end
  end

  # ---- POST /api/v1/sessions/:session_id/timer ----

  describe "POST /api/v1/sessions/:session_id/timer" do
    test "schedules with preset", %{conn: conn, session: session} do
      conn = post(conn, ~p"/api/v1/sessions/#{session.id}/timer", %{preset: "5m"})
      resp = json_response(conn, 201)
      assert resp["success"] == true
      assert resp["action"] == "scheduled"
      assert resp["timer"]["interval_ms"] == 5 * 60 * 1_000
      assert resp["timer"]["mode"] == "once"
    end

    test "schedules with delay_ms", %{conn: conn, session: session} do
      conn = post(conn, ~p"/api/v1/sessions/#{session.id}/timer", %{delay_ms: 500})
      resp = json_response(conn, 201)
      assert resp["success"] == true
      assert resp["timer"]["interval_ms"] == 500
    end

    test "delay_ms takes precedence over preset", %{conn: conn, session: session} do
      conn =
        post(conn, ~p"/api/v1/sessions/#{session.id}/timer", %{delay_ms: 200, preset: "1h"})

      resp = json_response(conn, 201)
      assert resp["timer"]["interval_ms"] == 200
    end

    test "schedules repeating mode", %{conn: conn, session: session} do
      conn =
        post(conn, ~p"/api/v1/sessions/#{session.id}/timer", %{preset: "10m", mode: "repeating"})

      resp = json_response(conn, 201)
      assert resp["timer"]["mode"] == "repeating"
    end

    test "replaces existing timer", %{conn: conn, session: session} do
      OrchestratorTimers.schedule_once(session.id, 60_000, "first")

      conn = post(conn, ~p"/api/v1/sessions/#{session.id}/timer", %{preset: "5m"})
      resp = json_response(conn, 201)
      assert resp["action"] == "replaced"
    end

    test "uses default message when none provided", %{conn: conn, session: session} do
      conn = post(conn, ~p"/api/v1/sessions/#{session.id}/timer", %{preset: "5m"})
      resp = json_response(conn, 201)
      assert resp["timer"]["message"] == OrchestratorTimers.default_message()
    end

    test "whitespace-only message falls back to default", %{conn: conn, session: session} do
      conn =
        post(conn, ~p"/api/v1/sessions/#{session.id}/timer", %{preset: "5m", message: "   "})

      resp = json_response(conn, 201)
      assert resp["timer"]["message"] == OrchestratorTimers.default_message()
    end

    test "custom message is trimmed and used", %{conn: conn, session: session} do
      conn =
        post(conn, ~p"/api/v1/sessions/#{session.id}/timer", %{
          preset: "5m",
          message: "  wake up  "
        })

      resp = json_response(conn, 201)
      assert resp["timer"]["message"] == "wake up"
    end

    test "returns 400 for unknown preset", %{conn: conn, session: session} do
      conn = post(conn, ~p"/api/v1/sessions/#{session.id}/timer", %{preset: "2d"})
      resp = json_response(conn, 400)
      assert resp["error"] =~ "unknown preset"
    end

    test "returns 400 for invalid mode", %{conn: conn, session: session} do
      conn = post(conn, ~p"/api/v1/sessions/#{session.id}/timer", %{preset: "5m", mode: "daily"})
      resp = json_response(conn, 400)
      assert resp["error"] =~ "unknown mode"
    end

    test "returns 400 when neither delay_ms nor preset given", %{conn: conn, session: session} do
      conn = post(conn, ~p"/api/v1/sessions/#{session.id}/timer", %{mode: "once"})
      resp = json_response(conn, 400)
      assert resp["error"] =~ "delay_ms or preset is required"
    end

    test "returns 400 for delay_ms below minimum", %{conn: conn, session: session} do
      conn = post(conn, ~p"/api/v1/sessions/#{session.id}/timer", %{delay_ms: 50})
      resp = json_response(conn, 400)
      assert resp["error"] =~ "delay_ms must be >= 100"
    end

    test "returns 404 for unknown session", %{conn: conn} do
      conn = post(conn, ~p"/api/v1/sessions/9999999/timer", %{preset: "5m"})
      assert json_response(conn, 404)
    end
  end

  # ---- DELETE /api/v1/sessions/:session_id/timer ----

  describe "DELETE /api/v1/sessions/:session_id/timer" do
    test "cancels an active timer", %{conn: conn, session: session} do
      OrchestratorTimers.schedule_once(session.id, 60_000, "ping")
      conn = delete(conn, ~p"/api/v1/sessions/#{session.id}/timer")
      resp = json_response(conn, 200)
      assert resp["success"] == true
      assert resp["message"] == "timer cancelled"
      assert OrchestratorTimers.get_timer(session.id) == nil
    end

    test "no-op when no timer active", %{conn: conn, session: session} do
      conn = delete(conn, ~p"/api/v1/sessions/#{session.id}/timer")
      resp = json_response(conn, 200)
      assert resp["success"] == true
      assert resp["message"] == "no active timer"
    end

    test "returns 404 for unknown session", %{conn: conn} do
      conn = delete(conn, ~p"/api/v1/sessions/9999999/timer")
      assert json_response(conn, 404)
    end
  end
end
