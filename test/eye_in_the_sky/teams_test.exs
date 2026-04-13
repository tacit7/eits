defmodule EyeInTheSky.TeamsTest do
  use EyeInTheSky.DataCase, async: true

  alias EyeInTheSky.{Agents, Sessions, Teams}
  alias EyeInTheSky.Teams.TeamMember

  defp uniq, do: System.unique_integer([:positive])

  defp create_session do
    {:ok, agent} = Agents.create_agent(%{name: "teams-test-agent-#{uniq()}", status: "active"})

    {:ok, session} =
      Sessions.create_session(%{
        uuid: Ecto.UUID.generate(),
        agent_id: agent.id,
        started_at: DateTime.utc_now() |> DateTime.to_iso8601(),
        status: "idle"
      })

    session
  end

  defp create_team do
    {:ok, team} =
      Teams.create_team(%{
        name: "test-team-#{uniq()}",
        uuid: Ecto.UUID.generate(),
        status: "active"
      })

    team
  end

  defp join(team, session, name \\ nil) do
    {:ok, member} =
      Teams.join_team(%{
        team_id: team.id,
        session_id: session.id,
        agent_id: session.agent_id,
        name: name || "member-#{uniq()}",
        role: "worker"
      })

    member
  end

  describe "list_broadcast_targets/1" do
    test "returns empty list when session belongs to no teams" do
      session = create_session()
      assert Teams.list_broadcast_targets(session.id) == []
    end

    test "returns other members in the same team" do
      team = create_team()
      caller = create_session()
      peer1 = create_session()
      peer2 = create_session()

      join(team, caller)
      join(team, peer1)
      join(team, peer2)

      targets = Teams.list_broadcast_targets(caller.id)
      target_session_ids = Enum.map(targets, & &1.session_id)

      assert peer1.id in target_session_ids
      assert peer2.id in target_session_ids
      refute caller.id in target_session_ids
    end

    test "does not include the calling session" do
      team = create_team()
      caller = create_session()
      peer = create_session()

      join(team, caller)
      join(team, peer)

      targets = Teams.list_broadcast_targets(caller.id)
      refute Enum.any?(targets, &(&1.session_id == caller.id))
    end

    test "returns members across multiple teams" do
      team1 = create_team()
      team2 = create_team()
      caller = create_session()
      peer_in_team1 = create_session()
      peer_in_team2 = create_session()

      join(team1, caller)
      join(team1, peer_in_team1)
      join(team2, caller)
      join(team2, peer_in_team2)

      targets = Teams.list_broadcast_targets(caller.id)
      target_session_ids = Enum.map(targets, & &1.session_id)

      assert peer_in_team1.id in target_session_ids
      assert peer_in_team2.id in target_session_ids
    end

    test "deduplicates members who share multiple teams with caller" do
      team1 = create_team()
      team2 = create_team()
      caller = create_session()
      peer = create_session()

      join(team1, caller)
      join(team1, peer)
      join(team2, caller)
      join(team2, peer)

      targets = Teams.list_broadcast_targets(caller.id)
      peer_targets = Enum.filter(targets, &(&1.session_id == peer.id))

      assert length(peer_targets) == 1
    end

    test "excludes members with nil session_id" do
      team = create_team()
      caller = create_session()

      join(team, caller)

      # Insert a member directly with no session_id
      {:ok, _} =
        EyeInTheSky.Repo.insert(%TeamMember{
          team_id: team.id,
          agent_id: caller.agent_id,
          session_id: nil,
          name: "no-session-member",
          role: "worker",
          joined_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })

      assert Teams.list_broadcast_targets(caller.id) == []
    end
  end
end
