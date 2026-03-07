defmodule EyeInTheSkyWebWeb.Api.V1.AgentControllerTest do
  use EyeInTheSkyWebWeb.ConnCase, async: false

  alias EyeInTheSkyWeb.Agents

  defp uniq, do: System.unique_integer([:positive])

  defp create_agent(overrides \\ %{}) do
    {:ok, agent} =
      Agents.create_agent(
        Map.merge(
          %{
            uuid: Ecto.UUID.generate(),
            description: "Test agent #{uniq()}",
            source: "test"
          },
          overrides
        )
      )

    agent
  end

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

  describe "POST /api/v1/agents" do
    test "returns 400 when instructions are missing", %{conn: conn} do
      conn = post(conn, ~p"/api/v1/agents", %{"model" => "haiku"})
      assert json_response(conn, 400)["error"] == "instructions is required"
    end

    test "returns 400 when instructions are empty", %{conn: conn} do
      conn = post(conn, ~p"/api/v1/agents", %{"instructions" => ""})
      assert json_response(conn, 400)["error"] == "instructions is required"
    end

    # Skipping actual spawn test — requires AgentManager to start a Claude process
  end
end
