defmodule EyeInTheSkyWeb.MCP.Tools.AgentSendToolTest do
  use EyeInTheSkyWeb.DataCase, async: false

  alias EyeInTheSkyWeb.MCP.Tools.AgentSend
  alias EyeInTheSkyWeb.{Agents, Sessions}

  @frame :test_frame

  defp json_result({:reply, %Anubis.Server.Response{content: [%{"text" => json} | _]}, @frame}) do
    Jason.decode!(json, keys: :atoms)
  end

  defp uniq, do: System.unique_integer([:positive])

  defp new_session do
    {:ok, agent} = Agents.create_agent(%{name: "send-agent-#{uniq()}", status: "active"})

    {:ok, session} =
      Sessions.create_session(%{
        uuid: Ecto.UUID.generate(),
        agent_id: agent.id,
        started_at: DateTime.utc_now() |> DateTime.to_iso8601(),
        status: "idle"
      })

    session
  end

  test "returns error for nonexistent UUID" do
    r =
      AgentSend.execute(%{session_id: Ecto.UUID.generate(), message: "hello"}, @frame)
      |> json_result()

    assert r.success == false
    assert String.contains?(r.message, "not found")
  end

  test "returns error for nonexistent integer session ID" do
    r =
      AgentSend.execute(%{session_id: "99999999", message: "hello"}, @frame)
      |> json_result()

    assert r.success == false
  end

  test "queues message for valid session by UUID" do
    session = new_session()

    r =
      AgentSend.execute(%{session_id: session.uuid, message: "do the thing"}, @frame)
      |> json_result()

    assert r.success == true
    assert String.contains?(r.message, "queued")
  end

  test "queues message for valid session by integer ID" do
    session = new_session()

    r =
      AgentSend.execute(%{session_id: to_string(session.id), message: "do the thing"}, @frame)
      |> json_result()

    assert r.success == true
    assert String.contains?(r.message, "queued")
  end

  test "accepts optional model and effort_level" do
    session = new_session()

    r =
      AgentSend.execute(
        %{session_id: session.uuid, message: "work", model: "sonnet", effort_level: "high"},
        @frame
      )
      |> json_result()

    assert r.success == true
  end
end
