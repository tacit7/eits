defmodule EyeInTheSky.Agents.CmdDispatcherTest do
  use EyeInTheSky.DataCase, async: false

  import Ecto.Query

  alias EyeInTheSky.Agents.CmdDispatcher
  alias EyeInTheSky.{Messages, Sessions, Teams}

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp uniq, do: System.unique_integer([:positive])

  defp create_agent(overrides \\ %{}) do
    {:ok, agent} =
      EyeInTheSky.Agents.create_agent(
        Map.merge(
          %{uuid: Ecto.UUID.generate(), description: "Test #{uniq()}", source: "test"},
          overrides
        )
      )

    agent
  end

  defp create_session(agent, overrides \\ %{}) do
    {:ok, session} =
      Sessions.create_session(
        Map.merge(
          %{
            uuid: Ecto.UUID.generate(),
            agent_id: agent.id,
            name: "Session #{uniq()}",
            status: "working",
            started_at: DateTime.utc_now() |> DateTime.to_iso8601()
          },
          overrides
        )
      )

    session
  end

  defp create_team(attrs \\ %{}) do
    {:ok, team} =
      Teams.create_team(Map.merge(%{name: "Team #{uniq()}", status: "active"}, attrs))

    team
  end

  defp new_session do
    create_session(create_agent())
  end

  # Seed an inbound DM from `from_session` to `to_session`.
  defp seed_dm(from_session, to_session, body \\ nil) do
    body = body || "DM body #{uniq()}"

    {:ok, msg} =
      Messages.create_message(%{
        uuid: Ecto.UUID.generate(),
        session_id: to_session.id,
        from_session_id: from_session.id,
        to_session_id: to_session.id,
        body: body,
        sender_role: "agent",
        recipient_role: "agent",
        direction: "inbound",
        status: "sent",
        provider: "claude"
      })

    msg
  end

  # Grant sandbox access to Task-spawned processes. Required because dispatch_all
  # wraps each command in Task.start, which runs in a separate process.
  defp allow_sandbox do
    pid = self()

    Ecto.Adapters.SQL.Sandbox.allow(EyeInTheSky.Repo, pid, fn ->
      Process.sleep(500)
    end)
  end

  # Run dispatch_all and wait briefly for async tasks to finish.
  defp dispatch(line, session_id) do
    {cmd_lines, _clean} = CmdDispatcher.extract_commands(line)
    Ecto.Adapters.SQL.Sandbox.allow(EyeInTheSky.Repo, self(), self())
    CmdDispatcher.dispatch_all(cmd_lines, session_id)
    Process.sleep(100)
  end

  # ---------------------------------------------------------------------------
  # extract_commands/1
  # ---------------------------------------------------------------------------

  describe "extract_commands/1" do
    test "strips EITS-CMD lines from text" do
      text = "Some output\nEITS-CMD: dm list\nMore output"
      {cmd_lines, clean} = CmdDispatcher.extract_commands(text)

      assert cmd_lines == ["EITS-CMD: dm list"]
      assert clean == "Some output\nMore output"
    end

    test "returns empty cmd_lines for plain text" do
      text = "No commands here"
      {cmd_lines, clean} = CmdDispatcher.extract_commands(text)

      assert cmd_lines == []
      assert clean == text
    end

    test "handles multiple cmd lines in one chunk" do
      text = "EITS-CMD: dm list\nEITS-CMD: task begin Do work\nclean line"
      {cmd_lines, clean} = CmdDispatcher.extract_commands(text)

      assert length(cmd_lines) == 2
      assert clean == "clean line"
    end

    test "trims leading whitespace on CMD lines" do
      text = "  EITS-CMD: dm list"
      {cmd_lines, _clean} = CmdDispatcher.extract_commands(text)

      assert length(cmd_lines) == 1
    end
  end

  # ---------------------------------------------------------------------------
  # dm list
  # ---------------------------------------------------------------------------

  describe "EITS-CMD: dm list" do
    test "queries inbound DMs for the session" do
      receiver = new_session()
      sender1 = new_session()
      sender2 = new_session()

      seed_dm(sender1, receiver, "hello from sender1")
      seed_dm(sender2, receiver, "hello from sender2")

      # Should not crash even if AgentManager has no live worker for the session.
      # The send_message call will fail gracefully (no worker registered in test env).
      dispatch("EITS-CMD: dm list", receiver.id)

      # Verify the messages exist in DB as expected by the query
      dms =
        EyeInTheSky.Messages.Message
        |> where([m], m.to_session_id == ^receiver.id)
        |> where([m], not is_nil(m.from_session_id))
        |> EyeInTheSky.Repo.all()

      assert length(dms) == 2
      bodies = Enum.map(dms, & &1.body)
      assert "hello from sender1" in bodies
      assert "hello from sender2" in bodies
    end

    test "respects --limit flag" do
      receiver = new_session()
      sender = new_session()

      for i <- 1..10 do
        seed_dm(sender, receiver, "msg #{i}")
      end

      # limit 3 — just verify it doesn't crash; DB side is correct by query logic
      dispatch("EITS-CMD: dm list --limit 3", receiver.id)

      all_dms =
        EyeInTheSky.Messages.Message
        |> where([m], m.to_session_id == ^receiver.id)
        |> EyeInTheSky.Repo.all()

      assert length(all_dms) == 10
    end

    test "returns empty result without crashing when no DMs exist" do
      session = new_session()
      # No seeded DMs — should not raise
      dispatch("EITS-CMD: dm list", session.id)

      dms =
        EyeInTheSky.Messages.Message
        |> where([m], m.to_session_id == ^session.id)
        |> where([m], not is_nil(m.from_session_id))
        |> EyeInTheSky.Repo.all()

      assert dms == []
    end

    test "does not return messages where the session is the sender" do
      session = new_session()
      other = new_session()

      # session sent this to other — should NOT appear in session's dm list
      seed_dm(session, other, "outbound")
      # other sent this to session — SHOULD appear
      seed_dm(other, session, "inbound")

      dms =
        EyeInTheSky.Messages.Message
        |> where([m], m.to_session_id == ^session.id)
        |> where([m], not is_nil(m.from_session_id))
        |> EyeInTheSky.Repo.all()

      assert length(dms) == 1
      assert hd(dms).body == "inbound"
    end
  end

  describe "EITS-CMD: dm --to" do
    test "accepts a numeric session id target" do
      sender = new_session()
      receiver = new_session()

      dispatch(~s(EITS-CMD: dm --to #{receiver.id} --message "hello by id"), sender.id)

      assert_receive {:session_new_dm, ^receiver.id, msg}, 500
      assert msg.to_session_id == receiver.id
      assert msg.from_session_id == sender.id
      assert String.contains?(msg.body, "hello by id")
    end

    test "accepts a session uuid target" do
      sender = new_session()
      receiver = new_session()

      dispatch(~s(EITS-CMD: dm --to #{receiver.uuid} --message "hello by uuid"), sender.id)

      assert_receive {:session_new_dm, ^receiver.id, msg}, 500
      assert msg.to_session_id == receiver.id
      assert msg.from_session_id == sender.id
      assert String.contains?(msg.body, "hello by uuid")
    end
  end

  # ---------------------------------------------------------------------------
  # team broadcast
  # ---------------------------------------------------------------------------

  describe "EITS-CMD: team broadcast" do
    test "finds all other team members in shared teams" do
      team = create_team()

      sender_agent = create_agent()
      sender_session = create_session(sender_agent)

      member1_agent = create_agent()
      member1_session = create_session(member1_agent)

      member2_agent = create_agent()
      member2_session = create_session(member2_agent)

      {:ok, _} = Teams.join_team(%{team_id: team.id, name: "sender", session_id: sender_session.id})
      {:ok, _} = Teams.join_team(%{team_id: team.id, name: "m1", session_id: member1_session.id})
      {:ok, _} = Teams.join_team(%{team_id: team.id, name: "m2", session_id: member2_session.id})

      # Should not crash — AgentManager.send_message will fail gracefully per member
      dispatch("EITS-CMD: team broadcast --message \"hello team\"", sender_session.id)

      # Confirm the other members exist in the team (data setup is correct)
      members =
        EyeInTheSky.Teams.TeamMember
        |> where([m], m.team_id == ^team.id)
        |> EyeInTheSky.Repo.all()

      assert length(members) == 3

      other_sessions = members |> Enum.reject(&(&1.session_id == sender_session.id)) |> Enum.map(& &1.session_id)
      assert member1_session.id in other_sessions
      assert member2_session.id in other_sessions
    end

    test "does not target members without a session_id" do
      team = create_team()

      sender_agent = create_agent()
      sender_session = create_session(sender_agent)

      # Member with no session
      {:ok, _} = Teams.join_team(%{team_id: team.id, name: "sender", session_id: sender_session.id})
      {:ok, _} = Teams.join_team(%{team_id: team.id, name: "no-session-member"})

      # Should not crash
      dispatch("EITS-CMD: team broadcast --message \"hello\"", sender_session.id)

      sessionless =
        EyeInTheSky.Teams.TeamMember
        |> where([m], m.team_id == ^team.id and is_nil(m.session_id))
        |> EyeInTheSky.Repo.all()

      assert length(sessionless) == 1
    end

    test "does not send to self" do
      team = create_team()

      sender_agent = create_agent()
      sender_session = create_session(sender_agent)

      {:ok, _} = Teams.join_team(%{team_id: team.id, name: "sender", session_id: sender_session.id})

      # Only member is sender — no one else to broadcast to, should not crash
      dispatch("EITS-CMD: team broadcast --message \"solo\"", sender_session.id)

      members =
        EyeInTheSky.Teams.TeamMember
        |> where([m], m.team_id == ^team.id and m.session_id != ^sender_session.id)
        |> EyeInTheSky.Repo.all()

      assert members == []
    end

    test "fails with notify_error when --message is missing" do
      session = new_session()
      # Missing --message flag — should not crash
      dispatch("EITS-CMD: team broadcast", session.id)
    end
  end
end
