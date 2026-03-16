defmodule EyeInTheSkyWebWeb.Api.V1.AgentControllerTest do
  use EyeInTheSkyWebWeb.ConnCase, async: false

  import EyeInTheSkyWeb.Factory

  # ---- GET /api/v1/agents ----

  describe "GET /api/v1/agents" do
    test "returns agent list", %{conn: conn} do
      create_agent()
      conn = get(conn, ~p"/api/v1/agents")
      resp = json_response(conn, 200)

      assert resp["success"] == true
      assert is_list(resp["agents"])
    end

    test "respects limit param", %{conn: conn} do
      for _ <- 1..5, do: create_agent()
      conn = get(conn, ~p"/api/v1/agents?limit=2")
      resp = json_response(conn, 200)

      assert length(resp["agents"]) <= 2
    end

    test "each agent has expected fields", %{conn: conn} do
      agent = create_agent()
      conn = get(conn, ~p"/api/v1/agents")
      resp = json_response(conn, 200)

      found = Enum.find(resp["agents"], &(&1["id"] == agent.id))
      assert found != nil
      assert Map.has_key?(found, "uuid")
      assert Map.has_key?(found, "description")
      assert Map.has_key?(found, "status")
    end
  end

  # ---- GET /api/v1/agents/:id ----

  describe "GET /api/v1/agents/:id" do
    test "fetches agent by integer id", %{conn: conn} do
      agent = create_agent()
      conn = get(conn, ~p"/api/v1/agents/#{agent.id}")
      resp = json_response(conn, 200)

      assert resp["success"] == true
      assert resp["agent"]["id"] == agent.id
      assert resp["agent"]["uuid"] == agent.uuid
    end

    test "fetches agent by uuid", %{conn: conn} do
      agent = create_agent()
      conn = get(conn, ~p"/api/v1/agents/#{agent.uuid}")
      resp = json_response(conn, 200)

      assert resp["success"] == true
      assert resp["agent"]["uuid"] == agent.uuid
    end

    test "returns 404 for unknown integer id", %{conn: conn} do
      conn = get(conn, ~p"/api/v1/agents/9999999")
      assert json_response(conn, 404)["error"] == "Agent not found"
    end

    test "returns 404 for unknown uuid", %{conn: conn} do
      conn = get(conn, ~p"/api/v1/agents/#{Ecto.UUID.generate()}")
      assert json_response(conn, 404)["error"] == "Agent not found"
    end
  end

  # ---- POST /api/v1/agents ----

  @valid_params %{
    "instructions" => "Do the thing",
    "model"        => "haiku",
    "project_path" => "/tmp"
  }

  defp post_spawn(conn, params) do
    post(conn, ~p"/api/v1/agents", params)
  end

  describe "POST /api/v1/agents validation" do
    test "returns missing_required when instructions absent", %{conn: conn} do
      conn = post_spawn(conn, Map.delete(@valid_params, "instructions"))
      resp = json_response(conn, 400)
      assert resp["error_code"] == "missing_required"
      assert resp["message"] =~ "instructions"
    end

    test "returns missing_required when instructions is empty string", %{conn: conn} do
      conn = post_spawn(conn, Map.put(@valid_params, "instructions", ""))
      resp = json_response(conn, 400)
      assert resp["error_code"] == "missing_required"
    end

    test "returns missing_required when instructions is whitespace-only", %{conn: conn} do
      conn = post_spawn(conn, Map.put(@valid_params, "instructions", "   "))
      resp = json_response(conn, 400)
      assert resp["error_code"] == "missing_required"
    end

    test "returns instructions_too_long when over 32000 chars", %{conn: conn} do
      conn = post_spawn(conn, Map.put(@valid_params, "instructions", String.duplicate("a", 32_001)))
      resp = json_response(conn, 400)
      assert resp["error_code"] == "instructions_too_long"
    end

    test "returns invalid_model for unknown model", %{conn: conn} do
      conn = post_spawn(conn, Map.put(@valid_params, "model", "gpt-4"))
      resp = json_response(conn, 400)
      assert resp["error_code"] == "invalid_model"
    end

    test "returns invalid_parameter when parent_agent_id is non-integer string", %{conn: conn} do
      conn = post_spawn(conn, Map.put(@valid_params, "parent_agent_id", "abc"))
      resp = json_response(conn, 400)
      assert resp["error_code"] == "invalid_parameter"
      assert resp["message"] =~ "parent_agent_id"
    end

    test "returns invalid_parameter when parent_session_id is a float string", %{conn: conn} do
      conn = post_spawn(conn, Map.put(@valid_params, "parent_session_id", "1.5"))
      resp = json_response(conn, 400)
      assert resp["error_code"] == "invalid_parameter"
      assert resp["message"] =~ "parent_session_id"
    end

    test "succeeds with baseline params (no parent IDs)", %{conn: conn} do
      conn = post_spawn(conn, @valid_params)
      assert json_response(conn, 201)["success"] == true
    end

    test "returns parent_not_found when parent_agent_id does not exist", %{conn: conn} do
      conn = post_spawn(conn, Map.put(@valid_params, "parent_agent_id", "999999"))
      resp = json_response(conn, 400)
      assert resp["error_code"] == "parent_not_found"
      assert resp["message"] =~ "parent_agent_id"
    end

    test "returns parent_not_found when parent_session_id does not exist", %{conn: conn} do
      conn = post_spawn(conn, Map.put(@valid_params, "parent_session_id", "999999"))
      resp = json_response(conn, 400)
      assert resp["error_code"] == "parent_not_found"
      assert resp["message"] =~ "parent_session_id"
    end

    test "accepts valid parent_agent_id that exists in DB", %{conn: conn} do
      agent = create_agent()
      conn = post_spawn(conn, Map.put(@valid_params, "parent_agent_id", to_string(agent.id)))
      assert json_response(conn, 201)["success"] == true
    end

    test "returns team_not_found when team_name does not exist", %{conn: conn} do
      conn = post_spawn(conn, Map.put(@valid_params, "team_name", "nonexistent-team"))
      resp = json_response(conn, 400)
      assert resp["error_code"] == "team_not_found"
      assert resp["message"] =~ "nonexistent-team"
    end
  end

  describe "POST /api/v1/agents success" do
    test "returns 201 with agent_id, session_id, session_uuid", %{conn: conn} do
      conn = post_spawn(conn, @valid_params)
      resp = json_response(conn, 201)

      assert resp["success"] == true
      assert resp["message"] == "Agent spawned"
      assert is_binary(resp["agent_id"])
      assert is_integer(resp["session_id"])
      assert is_binary(resp["session_uuid"])
    end

    test "defaults model to haiku when absent", %{conn: conn} do
      conn = post_spawn(conn, Map.delete(@valid_params, "model"))
      assert json_response(conn, 201)["success"] == true
    end
  end
end
