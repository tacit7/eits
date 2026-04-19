defmodule EyeInTheSkyWeb.Api.V1.MockFailingAgentManager do
  @moduledoc "Test double that always returns an error from send_message."
  def send_message(_session_id, _message, _opts \\ []), do: {:error, :worker_failed}
end

defmodule EyeInTheSkyWeb.Api.V1.MockSucceedingAgentManager do
  @moduledoc "Test double that always succeeds send_message."
  def send_message(_session_id, _message, _opts \\ []), do: :ok
end

defmodule EyeInTheSkyWeb.Api.V1.MessagingControllerTest do
  use EyeInTheSkyWeb.ConnCase, async: false

  alias EyeInTheSky.Accounts.ApiKey
  alias EyeInTheSky.Channels

  import EyeInTheSky.Factory

  defp api_conn do
    token = "test_api_key_#{System.unique_integer([:positive])}"
    {:ok, _} = ApiKey.create(token, "test")
    Phoenix.ConnTest.build_conn() |> Plug.Conn.put_req_header("authorization", "Bearer #{token}")
  end

  setup do
    {:ok, conn: api_conn()}
  end

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
      Application.put_env(
        :eye_in_the_sky,
        :agent_manager_module,
        EyeInTheSkyWeb.Api.V1.MockSucceedingAgentManager
      )

      on_exit(fn -> Application.delete_env(:eye_in_the_sky, :agent_manager_module) end)

      agent = create_agent()
      sender_agent = create_agent()
      session = create_session(agent)
      sender_session = create_session(sender_agent)

      conn =
        post(conn, ~p"/api/v1/dm", %{
          "from_session_id" => sender_session.uuid,
          "to_session_id" => session.uuid,
          "message" => "Hello agent!"
        })

      resp = json_response(conn, 201)

      assert resp["success"] == true
      assert String.contains?(resp["message"], to_string(session.id))
    end

    test "returns 400 when from_session_id is missing", %{conn: conn} do
      conn =
        post(conn, ~p"/api/v1/dm", %{
          "to_session_id" => Ecto.UUID.generate(),
          "message" => "hi"
        })

      assert json_response(conn, 400)["error"] == "from_session_id is required"
    end

    test "returns 400 when to_session_id is missing", %{conn: conn} do
      conn =
        post(conn, ~p"/api/v1/dm", %{
          "from_session_id" => Ecto.UUID.generate(),
          "message" => "hi"
        })

      assert json_response(conn, 400)["error"] == "to_session_id is required"
    end

    test "returns 400 when message is missing", %{conn: conn} do
      conn =
        post(conn, ~p"/api/v1/dm", %{
          "from_session_id" => Ecto.UUID.generate(),
          "to_session_id" => Ecto.UUID.generate()
        })

      assert json_response(conn, 400)["error"] == "message is required"
    end

    test "returns 404 when target session is not found", %{conn: conn} do
      sender_agent = create_agent()
      sender_session = create_session(sender_agent)

      conn =
        post(conn, ~p"/api/v1/dm", %{
          "from_session_id" => sender_session.uuid,
          "to_session_id" => Ecto.UUID.generate(),
          "message" => "Hello!"
        })

      assert json_response(conn, 404)["error"] == "Target session not found"
    end

    test "returns 500 when agent manager fails to route the message", %{conn: conn} do
      Application.put_env(
        :eye_in_the_sky,
        :agent_manager_module,
        EyeInTheSkyWeb.Api.V1.MockFailingAgentManager
      )

      on_exit(fn ->
        Application.delete_env(:eye_in_the_sky, :agent_manager_module)
      end)

      agent = create_agent()
      session = create_session(agent)

      conn =
        post(conn, ~p"/api/v1/dm", %{
          "sender_id" => agent.uuid,
          "target_session_id" => session.uuid,
          "message" => "Hello agent!"
        })

      resp = json_response(conn, 500)
      assert resp["error"] == "Failed to deliver message"
      refute Map.has_key?(resp, "reason")

      # Message must NOT be persisted when routing fails (no duplicates on retry)
      assert EyeInTheSky.Messages.list_messages_for_session(session.id) == []
    end
  end

  # ---- POST /api/v1/channels ----

  describe "POST /api/v1/channels" do
    test "creates a channel with name only", %{conn: conn} do
      name = "test-#{uniq()}"
      conn = post(conn, ~p"/api/v1/channels", %{"name" => name})
      resp = json_response(conn, 201)

      assert resp["success"] == true
      assert resp["channel"]["name"] == name
      assert resp["channel"]["channel_type"] == "public"
    end

    test "creates a channel with optional channel_type, description, and session_id", %{
      conn: conn
    } do
      agent = create_agent()
      session = create_session(agent)
      name = "full-#{uniq()}"

      conn =
        post(conn, ~p"/api/v1/channels", %{
          "name" => name,
          "channel_type" => "private",
          "description" => "A test channel",
          "session_id" => to_string(session.id)
        })

      resp = json_response(conn, 201)

      assert resp["success"] == true
      assert resp["channel"]["name"] == name
      assert resp["channel"]["channel_type"] == "private"
    end

    test "returns 400 when name is missing", %{conn: conn} do
      conn = post(conn, ~p"/api/v1/channels", %{})
      assert json_response(conn, 400)["error"] == "name is required"
    end

    test "returns 400 when name is blank", %{conn: conn} do
      conn = post(conn, ~p"/api/v1/channels", %{"name" => "   "})
      assert json_response(conn, 400)["error"] == "name is required"
    end

    test "returns 400 when project_id is not an integer", %{conn: conn} do
      conn = post(conn, ~p"/api/v1/channels", %{"name" => "x-#{uniq()}", "project_id" => "abc"})
      assert json_response(conn, 400)["error"] == "project_id must be an integer"
    end

    test "returns 404 when session_id is provided but not found", %{conn: conn} do
      conn =
        post(conn, ~p"/api/v1/channels", %{
          "name" => "x-#{uniq()}",
          "session_id" => Ecto.UUID.generate()
        })

      assert json_response(conn, 404)["error"] == "session_id not found"
    end

    test "returns 422 on invalid channel_type", %{conn: conn} do
      conn =
        post(conn, ~p"/api/v1/channels", %{
          "name" => "x-#{uniq()}",
          "channel_type" => "invalid_type"
        })

      assert json_response(conn, 422) != nil
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

      assert resp["channels"] != []

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
