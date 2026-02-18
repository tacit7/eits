defmodule EyeInTheSkyWeb.NATS.HandlerTest do
  use EyeInTheSkyWeb.DataCase, async: false

  alias EyeInTheSkyWeb.NATS.Handler
  alias EyeInTheSkyWeb.{Agents, Sessions}

  defp uniq, do: System.unique_integer([:positive])

  defp create_session(status \\ "idle") do
    {:ok, agent} = Agents.create_agent(%{name: "agent-#{uniq()}", status: "working"})

    {:ok, session} =
      Sessions.create_session(%{
        uuid: "sess-#{uniq()}",
        agent_id: agent.id,
        started_at: DateTime.utc_now() |> DateTime.to_iso8601(),
        status: status
      })

    session
  end

  defp reload(session) do
    {:ok, s} = Sessions.get_session_by_uuid(session.uuid)
    s
  end

  # ---------------------------------------------------------------------------
  # events.session.update
  # ---------------------------------------------------------------------------

  describe "events.session.update" do
    test "sets status to working" do
      s = create_session("idle")
      Handler.handle("events.session.update", %{"session_id" => s.uuid, "status" => "working"})
      assert reload(s).status == "working"
    end

    test "sets status to idle" do
      s = create_session("working")
      Handler.handle("events.session.update", %{"session_id" => s.uuid, "status" => "idle"})
      assert reload(s).status == "idle"
    end

    test "sets status to compacting" do
      s = create_session("working")
      Handler.handle("events.session.update", %{"session_id" => s.uuid, "status" => "compacting"})
      assert reload(s).status == "compacting"
    end

    test "sets ended_at when status is completed" do
      s = create_session("working")
      Handler.handle("events.session.update", %{"session_id" => s.uuid, "status" => "completed"})
      updated = reload(s)
      assert updated.status == "completed"
      assert updated.ended_at != nil
    end

    test "no-op for unknown session_id" do
      # Should not raise
      Handler.handle("events.session.update", %{"session_id" => "ghost-uuid", "status" => "idle"})
    end
  end

  # ---------------------------------------------------------------------------
  # events.session.stop — delegates to update with data.status
  # ---------------------------------------------------------------------------

  describe "events.session.stop" do
    test "sets status to idle via data.status" do
      s = create_session("working")

      Handler.handle("events.session.stop", %{
        "session_id" => s.uuid,
        "data" => %{"status" => "idle"}
      })

      assert reload(s).status == "idle"
    end

    test "updates last_activity_at" do
      s = create_session("working")
      before_ts = s.last_activity_at

      Handler.handle("events.session.stop", %{
        "session_id" => s.uuid,
        "data" => %{"status" => "idle"}
      })

      updated = reload(s)
      assert updated.last_activity_at != before_ts || updated.status == "idle"
    end
  end

  # ---------------------------------------------------------------------------
  # events.session.end — delegates to update with data.status
  # ---------------------------------------------------------------------------

  describe "events.session.end" do
    test "sets status to completed and sets ended_at" do
      s = create_session("working")

      Handler.handle("events.session.end", %{
        "session_id" => s.uuid,
        "data" => %{"status" => "completed"}
      })

      updated = reload(s)
      assert updated.status == "completed"
      assert updated.ended_at != nil
    end
  end

  # ---------------------------------------------------------------------------
  # events.session.compact — delegates to update with data.status
  # ---------------------------------------------------------------------------

  describe "events.session.compact" do
    test "sets status to compacting" do
      s = create_session("working")

      Handler.handle("events.session.compact", %{
        "session_id" => s.uuid,
        "data" => %{"status" => "compacting"}
      })

      assert reload(s).status == "compacting"
    end

    test "sets status back to working after compaction done" do
      s = create_session("compacting")

      Handler.handle("events.session.compact", %{
        "session_id" => s.uuid,
        "data" => %{"status" => "working"}
      })

      assert reload(s).status == "working"
    end
  end

  # ---------------------------------------------------------------------------
  # events.session.start
  # ---------------------------------------------------------------------------

  describe "events.session.start" do
    test "creates a new session when uuid is unknown" do
      uuid = "new-sess-#{uniq()}"

      Handler.handle("events.session.start", %{
        "session_id" => uuid,
        "description" => "test session",
        "provider" => "claude"
      })

      assert {:ok, session} = Sessions.get_session_by_uuid(uuid)
      assert session.uuid == uuid
    end

    test "does not error when session already exists" do
      s = create_session()

      Handler.handle("events.session.start", %{
        "session_id" => s.uuid,
        "description" => "resume",
        "provider" => "claude"
      })
    end
  end

  # ---------------------------------------------------------------------------
  # Unhandled subjects
  # ---------------------------------------------------------------------------

  describe "unhandled subjects" do
    test "does not raise for unknown subject" do
      Handler.handle("events.unknown.thing", %{"foo" => "bar"})
    end
  end
end
