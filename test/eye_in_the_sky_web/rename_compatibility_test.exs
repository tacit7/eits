defmodule EyeInTheSkyWeb.RenameCompatibilityTest do
  use EyeInTheSkyWeb.DataCase

  alias EyeInTheSkyWeb.{Agents, Channels, ChatAgents, Messages}

  describe "updated liveview module usage" do
    test "chat live uses execution Agents and ChatAgents paths" do
      source =
        File.read!(Path.join(File.cwd!(), "lib/eye_in_the_sky_web_web/live/chat_live.ex"))

      assert source =~ "Agents.get_execution_agent_by_uuid"
      assert source =~ "ChatAgents.get_chat_agent_status_counts"
      refute source =~ "Sessions.get_session"
    end

    test "dm live uses execution Agents and ChatAgents paths" do
      source =
        File.read!(Path.join(File.cwd!(), "lib/eye_in_the_sky_web_web/live/dm_live.ex"))

      assert source =~ "Agents.get_execution_agent!"
      assert source =~ "ChatAgents.get_chat_agent!"
      refute source =~ "Sessions.get_session!"
    end

    test "agent index live uses new list function from execution Agents" do
      source =
        File.read!(Path.join(File.cwd!(), "lib/eye_in_the_sky_web_web/live/agent_live/index.ex"))

      assert source =~ "Agents.list_agents_with_chat_agent"
      refute source =~ "Sessions.list_sessions_with_agent"
    end
  end

  describe "message persistence compatibility" do
    setup do
      {:ok, chat_agent} =
        ChatAgents.create_chat_agent(%{
          uuid: Ecto.UUID.generate(),
          source: "test",
          description: "flow compatibility chat agent"
        })

      {:ok, execution_agent} =
        Agents.create_execution_agent(%{
          uuid: Ecto.UUID.generate(),
          agent_id: chat_agent.id,
          name: "flow compatibility execution agent",
          started_at: DateTime.utc_now() |> DateTime.to_iso8601()
        })

      {:ok, channel} =
        Channels.create_channel(%{
          uuid: Ecto.UUID.generate(),
          name: "compat-#{System.unique_integer([:positive])}",
          channel_type: "public"
        })

      %{execution_agent: execution_agent, channel: channel}
    end

    test "dm flow stores outbound message on execution agent session", %{
      execution_agent: execution_agent
    } do
      body = "compat dm #{System.unique_integer([:positive])}"

      assert {:ok, message} =
               Messages.send_message(%{
                 session_id: execution_agent.id,
                 sender_role: "user",
                 recipient_role: "agent",
                 provider: "claude",
                 body: body
               })

      assert message.direction == "outbound"
      assert message.session_id == execution_agent.id

      recent = Messages.list_recent_messages(execution_agent.id, 20)
      assert Enum.any?(recent, fn m -> m.id == message.id and m.body == body end)
    end

    test "chat flow stores outbound message on channel", %{
      execution_agent: execution_agent,
      channel: channel
    } do
      body = "compat channel #{System.unique_integer([:positive])}"

      assert {:ok, message} =
               Messages.send_channel_message(%{
                 channel_id: channel.id,
                 session_id: execution_agent.id,
                 sender_role: "user",
                 recipient_role: "agent",
                 provider: "claude",
                 body: body
               })

      assert message.direction == "outbound"
      assert message.channel_id == channel.id

      channel_messages = Messages.list_messages_for_channel(channel.id)
      assert Enum.any?(channel_messages, fn m -> m.id == message.id and m.body == body end)
    end
  end
end
