defmodule EyeInTheSkyWeb.MCP.Tools.HelpersTest do
  use EyeInTheSkyWeb.DataCase, async: false

  alias EyeInTheSkyWeb.MCP.Tools.Helpers
  alias EyeInTheSkyWeb.{Agents, Sessions}

  defp uniq, do: System.unique_integer([:positive])

  defp new_session do
    {:ok, agent} = Agents.create_agent(%{name: "helpers-agent-#{uniq()}", status: "idle"})

    {:ok, session} =
      Sessions.create_session(%{
        uuid: "helpers-#{uniq()}",
        agent_id: agent.id,
        started_at: DateTime.utc_now() |> DateTime.to_iso8601(),
        status: "working"
      })

    session
  end

  describe "resolve_session_int_id/1" do
    test "returns error for nil" do
      assert {:error, _} = Helpers.resolve_session_int_id(nil)
    end

    test "returns ok for integer" do
      assert {:ok, 42} = Helpers.resolve_session_int_id(42)
    end

    test "parses integer string" do
      assert {:ok, 99} = Helpers.resolve_session_int_id("99")
    end

    test "resolves valid session UUID" do
      s = new_session()
      assert {:ok, s.id} == Helpers.resolve_session_int_id(s.uuid)
    end

    test "returns error for unknown UUID" do
      assert {:error, msg} =
               Helpers.resolve_session_int_id("aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee")

      assert String.contains?(msg, "Session not found")
    end

    test "returns error for non-integer non-uuid string" do
      assert {:error, _} = Helpers.resolve_session_int_id("not-a-uuid-or-int")
    end

    test "integer string takes precedence over UUID lookup" do
      s = new_session()
      # If we pass the session's integer ID as a string, it should parse directly
      assert {:ok, s.id} == Helpers.resolve_session_int_id(to_string(s.id))
    end
  end
end
