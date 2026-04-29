defmodule EyeInTheSkyWeb.Api.V1.AgentActivityControllerTest do
  use EyeInTheSkyWeb.ConnCase, async: false

  import EyeInTheSky.Factory

  alias EyeInTheSky.Accounts.ApiKey
  alias EyeInTheSky.{Repo, Tasks}
  alias EyeInTheSky.Tasks.WorkflowState

  defp api_conn do
    token = "test_api_key_#{System.unique_integer([:positive])}"
    {:ok, _} = ApiKey.create(token, "test")
    Phoenix.ConnTest.build_conn() |> Plug.Conn.put_req_header("authorization", "Bearer #{token}")
  end

  setup do
    {:ok, conn: api_conn()}
  end

  defp create_task_for_agent(agent, overrides) do
    {:ok, task} =
      Tasks.create_task(
        Map.merge(
          %{
            uuid: Ecto.UUID.generate(),
            title: "Task #{System.unique_integer([:positive])}",
            state_id: WorkflowState.in_progress_id(),
            agent_id: agent.id,
            created_at: DateTime.utc_now(),
            updated_at: DateTime.utc_now()
          },
          overrides
        )
      )

    task
  end

  defp create_commit_for_session(session) do
    Repo.insert_all(
      "commits",
      [
        %{
          commit_hash: "abc#{System.unique_integer([:positive])}",
          commit_message: "Test commit",
          session_id: session.id,
          created_at: DateTime.utc_now() |> DateTime.truncate(:second)
        }
      ]
    )
  end

  # ---- GET /api/v1/agents/activity ----

  describe "GET /api/v1/agents/activity" do
    test "returns 400 when agent_uuid is missing", %{conn: conn} do
      conn = get(conn, ~p"/api/v1/agents/activity?since=24h")
      resp = json_response(conn, 400)
      assert resp["error"] =~ "agent_uuid"
    end

    test "returns 400 when since is invalid", %{conn: conn} do
      agent = create_agent()
      conn = get(conn, ~p"/api/v1/agents/activity?agent_uuid=#{agent.uuid}&since=badformat")
      resp = json_response(conn, 400)
      assert resp["error"] =~ "Invalid duration"
    end

    test "returns 404 when agent does not exist", %{conn: conn} do
      conn =
        get(
          conn,
          ~p"/api/v1/agents/activity?agent_uuid=00000000-0000-0000-0000-000000000000&since=24h"
        )

      assert json_response(conn, 404)["error"] =~ "not found"
    end

    test "returns activity with required top-level fields", %{conn: conn} do
      agent = create_agent()

      conn = get(conn, ~p"/api/v1/agents/activity?agent_uuid=#{agent.uuid}&since=24h")
      resp = json_response(conn, 200)

      assert resp["success"] == true
      assert resp["agent_uuid"] == agent.uuid
      assert resp["since"] == "24h"
      assert is_binary(resp["window_start"])
      assert Map.has_key?(resp, "tasks")
      assert Map.has_key?(resp, "commits")
      assert Map.has_key?(resp, "sessions")
    end

    test "tasks bucket has all four keys", %{conn: conn} do
      agent = create_agent()
      conn = get(conn, ~p"/api/v1/agents/activity?agent_uuid=#{agent.uuid}&since=24h")
      tasks = json_response(conn, 200)["tasks"]

      assert Map.has_key?(tasks, "done")
      assert Map.has_key?(tasks, "in_review")
      assert Map.has_key?(tasks, "in_progress")
      assert Map.has_key?(tasks, "stale")
    end

    test "in_progress task within window appears in in_progress bucket", %{conn: conn} do
      agent = create_agent()
      task = create_task_for_agent(agent, %{state_id: WorkflowState.in_progress_id(), updated_at: DateTime.utc_now()})

      conn = get(conn, ~p"/api/v1/agents/activity?agent_uuid=#{agent.uuid}&since=24h")
      resp = json_response(conn, 200)

      in_progress_ids = Enum.map(resp["tasks"]["in_progress"], & &1["id"])
      assert task.id in in_progress_ids
    end

    test "done task updated within window appears in done bucket", %{conn: conn} do
      agent = create_agent()

      task =
        create_task_for_agent(agent, %{
          state_id: WorkflowState.done_id(),
          completed_at: DateTime.utc_now()
        })

      conn = get(conn, ~p"/api/v1/agents/activity?agent_uuid=#{agent.uuid}&since=24h")
      resp = json_response(conn, 200)

      done_ids = Enum.map(resp["tasks"]["done"], & &1["id"])
      assert task.id in done_ids
    end

    test "accepts Nd duration format", %{conn: conn} do
      agent = create_agent()
      conn = get(conn, ~p"/api/v1/agents/activity?agent_uuid=#{agent.uuid}&since=7d")
      resp = json_response(conn, 200)

      assert resp["success"] == true
      assert resp["since"] == "7d"
    end

    test "defaults to 24h when since is omitted", %{conn: conn} do
      agent = create_agent()
      conn = get(conn, ~p"/api/v1/agents/activity?agent_uuid=#{agent.uuid}")
      resp = json_response(conn, 200)

      assert resp["success"] == true
      assert resp["since"] == "24h"
    end

    test "commits within window are returned", %{conn: conn} do
      agent = create_agent()
      session = create_session(agent)
      create_commit_for_session(session)

      conn = get(conn, ~p"/api/v1/agents/activity?agent_uuid=#{agent.uuid}&since=24h")
      resp = json_response(conn, 200)

      assert length(resp["commits"]) >= 1
      commit = hd(resp["commits"])
      assert Map.has_key?(commit, "hash")
      assert Map.has_key?(commit, "message")
      assert Map.has_key?(commit, "session_id")
      assert Map.has_key?(commit, "inserted_at")
    end

    test "sessions active within window are returned", %{conn: conn} do
      agent = create_agent()
      _session = create_session(agent)

      conn = get(conn, ~p"/api/v1/agents/activity?agent_uuid=#{agent.uuid}&since=24h")
      resp = json_response(conn, 200)

      # Session was just created so it's within the 24h window
      assert length(resp["sessions"]) >= 1
      session = hd(resp["sessions"])
      assert Map.has_key?(session, "id")
      assert Map.has_key?(session, "uuid")
      assert Map.has_key?(session, "name")
      assert Map.has_key?(session, "status")
    end
  end
end
