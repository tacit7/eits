defmodule EyeInTheSkyWeb.ChatLiveSubscriptionTest do
  @moduledoc """
  Tests for PubSub subscription lifecycle in ChatLive.

  Verifies that channel subscriptions are managed correctly on
  channel switch and same-channel patch, to prevent duplicate
  message delivery or stale subscriptions.
  """

  use EyeInTheSkyWeb.ConnCase

  import Phoenix.LiveViewTest

  alias EyeInTheSky.{Agents, Channels, Projects, Sessions}

  @agent_uuid "00000000-0000-0000-0000-000000000010"

  setup %{conn: conn} do
    {:ok, project} =
      Projects.create_project(%{
        name: "Sub Test Project",
        slug: "sub-test-project-#{System.unique_integer([:positive])}",
        active: true
      })

    {:ok, agent} =
      Agents.create_agent(%{
        uuid: @agent_uuid,
        description: "Test Agent",
        source: "web",
        project_id: project.id
      })

    {:ok, session} =
      Sessions.create_session(%{
        uuid: Ecto.UUID.generate(),
        agent_id: agent.id,
        name: "Test Session",
        started_at: DateTime.utc_now() |> DateTime.to_iso8601()
      })

    {:ok, channel_a} =
      Channels.create_channel(%{
        name: "Channel Alpha",
        project_id: project.id,
        session_id: session.id
      })

    {:ok, channel_b} =
      Channels.create_channel(%{
        name: "Channel Beta",
        project_id: project.id,
        session_id: session.id
      })

    %{conn: conn, project: project, channel_a: channel_a, channel_b: channel_b}
  end

  # Count how many times `pid` is subscribed to the channel topic.
  # Phoenix.PubSub uses Registry internally; duplicate subscribes appear as
  # multiple entries for the same pid.
  defp sub_count(pid, channel_id) do
    topic = "channel:#{channel_id}:messages"

    Registry.lookup(EyeInTheSky.PubSub, topic)
    |> Enum.count(fn {p, _} -> p == pid end)
  end

  describe "channel subscription lifecycle" do
    test "subscribes to channel on mount", %{conn: conn, channel_a: channel_a} do
      {:ok, view, _html} = live(conn, ~p"/chat?channel_id=#{channel_a.id}")
      assert sub_count(view.pid, channel_a.id) == 1
    end

    test "switching channels unsubscribes from previous channel", %{
      conn: conn,
      channel_a: channel_a,
      channel_b: channel_b
    } do
      {:ok, view, _html} = live(conn, ~p"/chat?channel_id=#{channel_a.id}")

      assert sub_count(view.pid, channel_a.id) == 1

      render_patch(view, ~p"/chat?channel_id=#{channel_b.id}")

      assert sub_count(view.pid, channel_a.id) == 0,
             "should unsubscribe from channel_a after switching to channel_b"

      assert sub_count(view.pid, channel_b.id) == 1,
             "should be subscribed to channel_b after switching"
    end

    test "patching to same channel does not create duplicate subscription", %{
      conn: conn,
      channel_a: channel_a
    } do
      {:ok, view, _html} = live(conn, ~p"/chat?channel_id=#{channel_a.id}")

      assert sub_count(view.pid, channel_a.id) == 1

      # Patch back to the same channel (e.g., after a thread close or nav event)
      render_patch(view, ~p"/chat?channel_id=#{channel_a.id}")

      assert sub_count(view.pid, channel_a.id) == 1,
             "should not accumulate duplicate subscriptions on same-channel patch"
    end
  end
end
