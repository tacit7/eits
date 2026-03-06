defmodule EyeInTheSkyWeb.MCP.Tools.MessagingToolsTest do
  use EyeInTheSkyWeb.DataCase, async: false

  alias EyeInTheSkyWeb.MCP.Tools.{Dm, ChatSend, ChatChannelList}
  alias EyeInTheSkyWeb.{Agents, Sessions, Channels, Projects}

  @frame :test_frame

  defp json_result({:reply, %Anubis.Server.Response{content: [%{"text" => json} | _]}, @frame}) do
    Jason.decode!(json, keys: :atoms)
  end

  defp uniq, do: System.unique_integer([:positive])

  defp new_session do
    {:ok, agent} = Agents.create_agent(%{name: "msg-agent-#{uniq()}", status: "active"})
    {:ok, session} = Sessions.create_session(%{
      uuid: "msg-#{uniq()}",
      agent_id: agent.id,
      started_at: DateTime.utc_now() |> DateTime.to_iso8601(),
      status: "active"
    })
    session
  end

  defp new_channel(session) do
    {:ok, project} = Projects.create_project(%{name: "proj #{uniq()}"})
    {:ok, channel} = Channels.create_channel(%{
      uuid: Ecto.UUID.generate(),
      name: "ch#{uniq()}",
      channel_type: "public",
      project_id: project.id,
      session_id: session.id
    })
    {project, channel}
  end

  # ---- Dm ----

  test "Dm: delivers message to existing session" do
    sender = new_session()
    target = new_session()
    r = Dm.execute(%{sender_id: sender.uuid, target_session_id: target.uuid, message: "hey"}, @frame) |> json_result()
    assert r.success == true
    assert String.contains?(r.message, "delivered")
  end

  test "Dm: error for nonexistent target" do
    r = Dm.execute(%{sender_id: "s1", target_session_id: "ghost", message: "hey"}, @frame) |> json_result()
    assert r.success == false
    assert String.contains?(r.message, "not found")
  end

  test "Dm: response_required flag accepted" do
    sender = new_session()
    target = new_session()
    r = Dm.execute(%{sender_id: sender.uuid, target_session_id: target.uuid, message: "reply pls", response_required: true}, @frame) |> json_result()
    assert r.success == true
  end

  # ---- ChatChannelList ----

  test "ChatChannelList: returns list (may be empty)" do
    r = ChatChannelList.execute(%{}, @frame) |> json_result()
    assert r.success == true
    assert is_list(r.channels)
  end

  test "ChatChannelList: returns channels when they exist" do
    s = new_session()
    new_channel(s)
    r = ChatChannelList.execute(%{}, @frame) |> json_result()
    assert r.success == true
    assert length(r.channels) >= 1
  end

  test "ChatChannelList: filters by project_id" do
    s = new_session()
    {project, _channel} = new_channel(s)
    r = ChatChannelList.execute(%{project_id: project.id}, @frame) |> json_result()
    assert r.success == true
    assert Enum.all?(r.channels, fn ch -> ch.project_id == project.id end)
  end

  test "ChatChannelList: result items have id, name, channel_type" do
    s = new_session()
    {project, _channel} = new_channel(s)
    r = ChatChannelList.execute(%{project_id: project.id}, @frame) |> json_result()
    assert length(r.channels) >= 1
    ch = hd(r.channels)
    assert Map.has_key?(ch, :id)
    assert Map.has_key?(ch, :name)
    assert Map.has_key?(ch, :channel_type)
  end

  # ---- ChatSend ----

  test "ChatSend: error when session not found" do
    r = ChatSend.execute(%{channel_id: "1", session_id: "ghost-uuid", body: "hello"}, @frame) |> json_result()
    assert r.success == false
    assert String.contains?(r.message, "not found")
  end

  test "ChatSend: sends message to channel" do
    s = new_session()
    {_project, channel} = new_channel(s)
    r = ChatSend.execute(%{channel_id: to_string(channel.id), session_id: s.uuid, body: "hello"}, @frame) |> json_result()
    assert r.success == true
    assert Map.has_key?(r, :message_id)
  end
end
