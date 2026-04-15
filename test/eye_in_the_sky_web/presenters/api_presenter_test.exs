defmodule EyeInTheSkyWeb.Presenters.ApiPresenterTest do
  use ExUnit.Case, async: true

  alias EyeInTheSky.Agents.Agent
  alias EyeInTheSky.Sessions.Session
  alias EyeInTheSky.Teams.TeamMember
  alias EyeInTheSkyWeb.Presenters.ApiPresenter

  describe "present_member/1" do
    test "includes all required payload fields with loaded associations" do
      agent = struct(Agent, id: 42, uuid: "agent-uuid-abc")
      session = struct(Session, id: 7, uuid: "session-uuid-xyz", status: "working")

      member =
        struct(TeamMember,
          id: 1,
          name: "agent-alpha",
          role: "member",
          status: "active",
          agent_id: 42,
          agent: agent,
          session_id: 7,
          session: session,
          joined_at: ~N[2024-01-01 00:00:00],
          last_activity_at: ~N[2024-01-02 12:00:00]
        )

      result = ApiPresenter.present_member(member)

      assert result.id == 1
      assert result.name == "agent-alpha"
      assert result.role == "member"
      assert result.status == "active"
      assert result.agent_id == 42
      assert result.agent_uuid == "agent-uuid-abc"
      assert result.session_id == 7
      assert result.session_uuid == "session-uuid-xyz"
      assert result.session_status == "working"
      assert is_binary(result.joined_at)
      assert is_binary(result.last_activity_at)
    end

    test "handles nil agent and session" do
      member =
        struct(TeamMember,
          id: 2,
          name: "bare-member",
          role: "observer",
          status: nil,
          agent_id: nil,
          agent: nil,
          session_id: nil,
          session: nil,
          joined_at: nil,
          last_activity_at: nil
        )

      result = ApiPresenter.present_member(member)

      assert result.id == 2
      assert result.name == "bare-member"
      assert is_nil(result.agent_uuid)
      assert is_nil(result.session_uuid)
      assert is_nil(result.session_status)
      assert is_nil(result.joined_at)
      assert is_nil(result.last_activity_at)
    end

    test "handles unloaded Ecto associations" do
      not_loaded_agent = %Ecto.Association.NotLoaded{
        __field__: :agent,
        __owner__: TeamMember,
        __cardinality__: :one
      }

      not_loaded_session = %Ecto.Association.NotLoaded{
        __field__: :session,
        __owner__: TeamMember,
        __cardinality__: :one
      }

      member =
        struct(TeamMember,
          id: 3,
          name: "linked-member",
          role: "member",
          status: "idle",
          agent_id: 10,
          agent: not_loaded_agent,
          session_id: 5,
          session: not_loaded_session,
          joined_at: nil,
          last_activity_at: nil
        )

      result = ApiPresenter.present_member(member)

      assert result.agent_id == 10
      assert is_nil(result.agent_uuid)
      assert result.session_id == 5
      assert is_nil(result.session_uuid)
      assert is_nil(result.session_status)
    end
  end
end
