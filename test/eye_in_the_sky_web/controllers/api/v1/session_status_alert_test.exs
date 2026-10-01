defmodule EyeInTheSkyWeb.Api.V1.SessionStatusAlertTest do
  use EyeInTheSkyWeb.ConnCase, async: false

  alias EyeInTheSky.Accounts.ApiKey
  alias EyeInTheSky.Events

  import EyeInTheSky.Factory

  setup do
    token = "status-alert-test-#{System.unique_integer([:positive])}"
    {:ok, _} = ApiKey.create(token, "status alert test")

    conn =
      Phoenix.ConnTest.build_conn()
      |> Plug.Conn.put_req_header("authorization", "Bearer #{token}")

    # Capture the desktop transport's casts without connecting to a native shell.
    # The registered name is released automatically when the test process exits.
    Process.register(self(), ElixirKit.PubSub)
    Events.subscribe_agents()

    {:ok, conn: conn}
  end

  for {status, title} <- [{"waiting", "Waiting for input"}, {"failed", "Session failed"}] do
    @status status
    @title title

    test "#{status} alerts on transitions but not repeated PATCH requests", %{conn: conn} do
      session = create_session(create_agent(), %{status: "working", name: "alert regression"})
      session_id = session.id
      path = ~p"/api/v1/sessions/#{session.uuid}"
      alert = "alert:#{@title}|alert regression|/dm/#{session.uuid}"

      assert json_response(patch(conn, path, %{"status" => @status}), 200)["status"] ==
               @status

      assert_receive {:"$gen_cast", {:broadcast, "messages", ^alert}}
      assert_receive {:agent_updated, %{id: ^session_id}}

      for _ <- 1..2 do
        assert json_response(patch(conn, path, %{"status" => @status}), 200)["status"] ==
                 @status

        assert_receive {:agent_updated, %{id: ^session_id}}
        refute_receive {:"$gen_cast", {:broadcast, "messages", _}}, 100
      end

      assert json_response(patch(conn, path, %{"name" => "renamed"}), 200)
      assert_receive {:agent_updated, %{id: ^session_id, name: "renamed"}}
      refute_receive {:"$gen_cast", {:broadcast, "messages", _}}, 100

      assert json_response(patch(conn, path, %{"status" => "working"}), 200)
      refute_receive {:"$gen_cast", {:broadcast, "messages", _}}, 100

      assert json_response(patch(conn, path, %{"status" => @status}), 200)
      next_alert = "alert:#{@title}|renamed|/dm/#{session.uuid}"
      assert_receive {:"$gen_cast", {:broadcast, "messages", ^next_alert}}
      refute_receive {:"$gen_cast", {:broadcast, "messages", _}}, 100
    end
  end
end
