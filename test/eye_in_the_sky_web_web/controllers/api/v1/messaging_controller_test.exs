defmodule EyeInTheSkyWebWeb.Api.V1.MessagingControllerTest do
  use EyeInTheSkyWebWeb.ConnCase, async: false

  alias EyeInTheSkyWeb.{Agents, Channels, Sessions}

  import EyeInTheSkyWeb.Factory

  defp create_channel do
    {:ok, channel} =
      Channels.create_channel(%{
        uuid: Ecto.UUID.generate(),
        name: "test-channel-#{uniq()}",
        channel_type: "public"
      })

    channel
  end

  # ---- POST /api/v1/dm ----

  describe "POST /api/v1/dm" do
    test "sends a DM to a valid session", %{conn: conn} do
      agent = create_agent()
      session = create_session(agent)

      conn =
        post(conn, ~p"/api/v1/dm", %{
          "sender_id" => Ecto.UUID.generate(),
          "target_session_id" => session.uuid,
          "message" => "Hello agent!"
        })

      resp = json_response(conn, 201)

      assert resp["success"] == true
      assert String.contains?(resp["message"], to_string(session.id))
    end

    test "returns 400 when sender_id is missing", %{conn: conn} do
      conn =
        post(conn, ~p"/api/v1/dm", %{
          "target_session_id" => Ecto.UUID.generate(),
          "message" => "hi"
        })

      assert json_response(conn, 400)["error"] == "sender_id is required"
    end

    test "returns 400 when target_session_id is missing", %{conn: conn} do
      conn =
        post(conn, ~p"/api/v1/dm", %{
          "sender_id" => Ecto.UUID.generate(),
          "message" => "hi"
        })

      assert json_response(conn, 400)["error"] == "target_session_id is required"
    end

    test "returns 400 when message is missing", %{conn: conn} do
      conn =
        post(conn, ~p"/api/v1/dm", %{
          "sender_id" => Ecto.UUID.generate(),
          "target_session_id" => Ecto.UUID.generate()
        })

      assert json_response(conn, 400)["error"] == "message is required"
    end

    test "returns 404 when target session is not found", %{conn: conn} do
      conn =
        post(conn, ~p"/api/v1/dm", %{
          "sender_id" => Ecto.UUID.generate(),
          "target_session_id" => Ecto.UUID.generate(),
          "message" => "Hello!"
        })

      assert json_response(conn, 404)["error"] == "Target session not found"
    end
  end

  # ---- GET /api/v1/channels ----

  describe "GET /api/v1/channels" do
    test "returns channel list", %{conn: conn} do
      conn = get(conn, ~p"/api/v1/channels")
      resp = json_response(conn, 200)

      assert resp["success"] == true
      assert is_list(resp["channels"])
    end

    test "returns channels with expected fields", %{conn: conn} do
      create_channel()
      conn = get(conn, ~p"/api/v1/channels")
      resp = json_response(conn, 200)

      assert length(resp["channels"]) >= 1

      ch = hd(resp["channels"])
      assert Map.has_key?(ch, "id")
      assert Map.has_key?(ch, "name")
      assert Map.has_key?(ch, "channel_type")
    end
  end

  # ---- POST /api/v1/channels/:channel_id/messages ----

  describe "POST /api/v1/channels/:channel_id/messages" do
    test "sends a message to a channel", %{conn: conn} do
      agent = create_agent()
      session = create_session(agent)
      channel = create_channel()

      conn =
        post(conn, ~p"/api/v1/channels/#{channel.id}/messages", %{
          "session_id" => session.uuid,
          "body" => "Hello channel!"
        })

      resp = json_response(conn, 201)

      assert resp["success"] == true
      assert resp["message_id"] != nil
    end

    test "accepts session_id as integer string", %{conn: conn} do
      agent = create_agent()
      session = create_session(agent)
      channel = create_channel()

      conn =
        post(conn, ~p"/api/v1/channels/#{channel.id}/messages", %{
          "session_id" => to_string(session.id),
          "body" => "Using int id"
        })

      assert json_response(conn, 201)["success"] == true
    end

    test "returns 400 when session_id is missing", %{conn: conn} do
      channel = create_channel()

      conn =
        post(conn, ~p"/api/v1/channels/#{channel.id}/messages", %{"body" => "no session"})

      assert json_response(conn, 400)["error"] == "session_id is required"
    end

    test "returns 400 when body is missing", %{conn: conn} do
      agent = create_agent()
      session = create_session(agent)
      channel = create_channel()

      conn =
        post(conn, ~p"/api/v1/channels/#{channel.id}/messages", %{
          "session_id" => session.uuid
        })

      assert json_response(conn, 400)["error"] == "body is required"
    end

    test "returns 404 when session not found by uuid", %{conn: conn} do
      channel = create_channel()

      conn =
        post(conn, ~p"/api/v1/channels/#{channel.id}/messages", %{
          "session_id" => Ecto.UUID.generate(),
          "body" => "hi"
        })

      assert json_response(conn, 404)["error"] != nil
    end
  end
end
