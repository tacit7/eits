defmodule EyeInTheSkyWeb.ChatLive.ChannelActionsTest do
  use EyeInTheSky.DataCase, async: false

  alias EyeInTheSky.{Agents, Channels, Projects, Sessions}
  alias EyeInTheSky.Channels.Channel
  alias EyeInTheSkyWeb.ChatLive.ChannelActions

  defp uniq, do: System.unique_integer([:positive])

  # Creates a project, a channel in it, and an agent/session pair.
  defp setup_channel_context do
    {:ok, project} =
      Projects.create_project(%{
        name: "ChannelActions project #{uniq()}",
        path: "/tmp/ca-test-#{uniq()}",
        slug: "ca-test-#{uniq()}"
      })

    channel_id = Channel.generate_id(project.id, "general")

    {:ok, channel} =
      Channels.create_channel(%{
        id: channel_id,
        uuid: Ecto.UUID.generate(),
        name: "general",
        channel_type: "public",
        project_id: project.id
      })

    {:ok, agent} =
      Agents.create_agent(%{
        uuid: Ecto.UUID.generate(),
        description: "Agent #{uniq()}",
        source: "test"
      })

    {:ok, session} =
      Sessions.create_session(%{
        uuid: Ecto.UUID.generate(),
        agent_id: agent.id,
        name: "Session #{uniq()}",
        status: "working",
        started_at: DateTime.utc_now() |> DateTime.to_iso8601()
      })

    %{project: project, channel: channel, agent: agent, session: session}
  end

  defp build_socket(assigns) do
    base = %{__changed__: %{}, flash: %{}}
    %Phoenix.LiveView.Socket{assigns: Map.merge(base, assigns)}
  end

  # ──────────────────────────────────────────────────────────────
  # handle_add_agent/2
  # ──────────────────────────────────────────────────────────────
  describe "handle_add_agent/2" do
    test "adds a valid session to the channel and refreshes member assigns" do
      %{channel: channel, session: session, project: project} = setup_channel_context()

      socket =
        build_socket(%{
          active_channel_id: channel.id,
          session_search: "",
          all_projects: [project]
        })

      {:noreply, result} =
        ChannelActions.handle_add_agent(socket, %{"session_id" => to_string(session.id)})

      assert is_list(result.assigns.channel_members)
      assert Enum.any?(result.assigns.channel_members, fn m -> m.session_id == session.id end)
    end

    test "returns error flash when session_id is not an integer string" do
      %{channel: channel, project: project} = setup_channel_context()

      socket =
        build_socket(%{
          active_channel_id: channel.id,
          session_search: "",
          all_projects: [project]
        })

      {:noreply, result} =
        ChannelActions.handle_add_agent(socket, %{"session_id" => "not-a-number"})

      assert result.assigns.flash["error"] == "Invalid session ID format"
    end

    test "returns error flash when session_id does not exist" do
      %{channel: channel, project: project} = setup_channel_context()

      socket =
        build_socket(%{
          active_channel_id: channel.id,
          session_search: "",
          all_projects: [project]
        })

      {:noreply, result} =
        ChannelActions.handle_add_agent(socket, %{"session_id" => "9999999"})

      assert result.assigns.flash["error"] == "Session not found"
    end

    test "returns error flash when agent is already in channel" do
      %{channel: channel, agent: agent, session: session, project: project} =
        setup_channel_context()

      {:ok, _} = Channels.add_member(channel.id, agent.id, session.id)

      socket =
        build_socket(%{
          active_channel_id: channel.id,
          session_search: "",
          all_projects: [project]
        })

      {:noreply, result} =
        ChannelActions.handle_add_agent(socket, %{"session_id" => to_string(session.id)})

      assert result.assigns.flash["error"] =~ "already in channel"
    end
  end

  # ──────────────────────────────────────────────────────────────
  # handle_remove_agent/2
  # ──────────────────────────────────────────────────────────────
  describe "handle_remove_agent/2" do
    test "removes a session that is a member of the channel" do
      %{channel: channel, agent: agent, session: session, project: project} =
        setup_channel_context()

      {:ok, _} = Channels.add_member(channel.id, agent.id, session.id)

      socket =
        build_socket(%{
          active_channel_id: channel.id,
          session_search: "",
          all_projects: [project]
        })

      {:noreply, result} =
        ChannelActions.handle_remove_agent(socket, %{"session_id" => to_string(session.id)})

      refute Enum.any?(result.assigns.channel_members, fn m -> m.session_id == session.id end)
    end

    test "returns error flash when session_id is not an integer string" do
      %{channel: channel, project: project} = setup_channel_context()

      socket =
        build_socket(%{
          active_channel_id: channel.id,
          session_search: "",
          all_projects: [project]
        })

      {:noreply, result} =
        ChannelActions.handle_remove_agent(socket, %{"session_id" => "bad-id"})

      assert result.assigns.flash["error"] == "Invalid session ID format"
    end

    test "returns error flash when session_id does not exist" do
      %{channel: channel, project: project} = setup_channel_context()

      socket =
        build_socket(%{
          active_channel_id: channel.id,
          session_search: "",
          all_projects: [project]
        })

      {:noreply, result} =
        ChannelActions.handle_remove_agent(socket, %{"session_id" => "9999999"})

      assert result.assigns.flash["error"] == "Session not found"
    end
  end

  # ──────────────────────────────────────────────────────────────
  # handle_create_channel/2
  # ──────────────────────────────────────────────────────────────
  describe "handle_create_channel/2" do
    test "creates a channel from params name and redirects" do
      %{project: project} = setup_channel_context()
      name = "my-test-channel-#{uniq()}"

      socket =
        build_socket(%{
          project_id: project.id,
          channels: []
        })

      {:noreply, result} =
        ChannelActions.handle_create_channel(socket, %{"name" => name})

      assert result.assigns.new_channel_name == nil
      assert is_list(result.assigns.channels)
      assert Enum.any?(result.assigns.channels, fn c -> c.name == name end)
    end

    test "falls back to new_channel_name assign when params name is blank" do
      %{project: project} = setup_channel_context()
      name = "assign-fallback-#{uniq()}"

      socket =
        build_socket(%{
          project_id: project.id,
          new_channel_name: name,
          channels: []
        })

      {:noreply, result} =
        ChannelActions.handle_create_channel(socket, %{"name" => ""})

      assert Enum.any?(result.assigns.channels, fn c -> c.name == name end)
    end

    test "clears new_channel_name and does not create when name is blank" do
      %{project: project} = setup_channel_context()

      socket =
        build_socket(%{
          project_id: project.id,
          new_channel_name: nil,
          channels: []
        })

      {:noreply, result} =
        ChannelActions.handle_create_channel(socket, %{"name" => "   "})

      assert result.assigns.new_channel_name == nil
    end

    test "gracefully handles duplicate channel name" do
      %{project: project, channel: existing} = setup_channel_context()

      socket =
        build_socket(%{
          project_id: project.id,
          channels: []
        })

      # second create with the same name should hit the unique constraint
      {:noreply, result} =
        ChannelActions.handle_create_channel(socket, %{"name" => existing.name})

      # On conflict the action clears new_channel_name (does not crash)
      assert result.assigns.new_channel_name == nil
    end
  end
end
