defmodule EyeInTheSky.Channels do
  @moduledoc """
  The Channels context for managing multi-agent chat channels.
  """

  import Ecto.Query, warn: false
  alias EyeInTheSky.Channels.{Channel, ChannelMember}
  alias EyeInTheSky.Repo

  @doc """
  Gets a single channel by ID. Returns nil if not found.
  """
  def get_channel(id), do: Repo.get(Channel, id)

  @doc """
  Returns all channels (no project filter).
  """
  def list_channels(opts \\ []) do
    include_archived = Keyword.get(opts, :include_archived, false)

    query = from c in Channel, order_by: [asc: c.inserted_at], limit: 500

    query =
      if include_archived do
        query
      else
        from c in query, where: is_nil(c.archived_at)
      end

    Repo.all(query)
  end

  @doc """
  Returns the list of channels for a specific project, including global channels (project_id is NULL).
  Default limit: 500. Pass `limit: n` to override.
  """
  def list_channels_for_project(project_id, opts \\ []) do
    include_archived = Keyword.get(opts, :include_archived, false)
    limit = Keyword.get(opts, :limit, 500)

    query =
      if is_nil(project_id) do
        from c in Channel, order_by: [asc: c.inserted_at]
      else
        from c in Channel,
          where: c.project_id == ^project_id or is_nil(c.project_id),
          order_by: [asc: c.inserted_at]
      end

    query =
      if include_archived do
        query
      else
        from c in query, where: is_nil(c.archived_at)
      end

    query
    |> limit(^limit)
    |> Repo.all()
  end

  @doc """
  Creates a channel.
  """
  def create_channel(attrs \\ %{}) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    attrs =
      Map.merge(attrs, %{
        inserted_at: now,
        updated_at: now
      })

    %Channel{}
    |> Channel.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Creates a default "general" channel for a project.
  """
  def create_default_channel(project_id, session_id) do
    channel_id = Channel.generate_id(project_id, "general")

    create_channel(%{
      id: channel_id,
      uuid: Ecto.UUID.generate(),
      name: "general",
      description: "Default project channel",
      channel_type: "public",
      project_id: project_id,
      created_by_session_id: session_id
    })
  end

  @doc """
  Updates a channel.
  """
  def update_channel(%Channel{} = channel, attrs) do
    channel
    |> Channel.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking channel changes.
  """
  def change_channel(%Channel{} = channel, attrs \\ %{}) do
    Channel.changeset(channel, attrs)
  end

  # Channel Membership Functions

  defp channel_member_query(channel_id, session_id) when is_nil(session_id) do
    from(m in ChannelMember, where: m.channel_id == ^channel_id and is_nil(m.session_id))
  end

  defp channel_member_query(channel_id, session_id) do
    from(m in ChannelMember, where: m.channel_id == ^channel_id and m.session_id == ^session_id)
  end

  @doc """
  Adds a member to a channel.
  """
  def add_member(channel_id, agent_id, session_id, role \\ "member") do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    session_uuid =
      case EyeInTheSky.Sessions.get_session(session_id) do
        {:ok, s} -> s.uuid
        _ -> Ecto.UUID.generate()
      end

    attrs = %{
      uuid: session_uuid,
      channel_id: channel_id,
      agent_id: agent_id,
      session_id: session_id,
      role: role,
      joined_at: now,
      inserted_at: now,
      updated_at: now
    }

    %ChannelMember{}
    |> ChannelMember.changeset(attrs)
    |> Repo.insert(
      on_conflict: :nothing,
      conflict_target: [:channel_id, :session_id]
    )
  end

  @doc """
  Removes a member from a channel.
  """
  def remove_member(channel_id, session_id) do
    channel_member_query(channel_id, session_id)
    |> Repo.delete_all()
  end

  @doc """
  Returns channels that a session is a member of, ordered by join time.
  """
  def list_channels_for_session(session_id) do
    from(m in ChannelMember,
      join: c in Channel,
      on: c.id == m.channel_id,
      where: m.session_id == ^session_id and is_nil(c.archived_at),
      order_by: [asc: m.joined_at],
      limit: 200,
      select: %{
        id: c.id,
        uuid: c.uuid,
        name: c.name,
        description: c.description,
        channel_type: c.channel_type,
        project_id: c.project_id,
        role: m.role,
        joined_at: m.joined_at
      }
    )
    |> Repo.all()
  end

  @doc """
  Lists all members of a channel. Default limit: 500.
  Pass `limit: n` to override.
  """
  def list_members(channel_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 500)

    from(m in ChannelMember,
      where: m.channel_id == ^channel_id,
      order_by: [asc: m.joined_at],
      limit: ^limit
    )
    |> Repo.all()
  end

  def list_members_with_sessions(channel_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 500)

    from(m in ChannelMember,
      left_join: s in EyeInTheSky.Sessions.Session,
      on: s.id == m.session_id,
      left_join: a in EyeInTheSky.Agents.Agent,
      on: a.id == m.agent_id,
      where: m.channel_id == ^channel_id,
      order_by: [asc: m.joined_at],
      limit: ^limit,
      select: %{
        id: m.id,
        agent_id: m.agent_id,
        agent_uuid: a.uuid,
        session_id: m.session_id,
        session_uuid: s.uuid,
        session_name: s.name,
        role: m.role,
        joined_at: m.joined_at
      }
    )
    |> Repo.all()
  end

  @doc """
  Counts unread messages per channel for a session in a single grouped query.
  Returns a map of %{channel_id => count}. Channels with no unread messages are absent (default to 0).
  """
  def count_unread_for_channels([], _session_id), do: %{}
  def count_unread_for_channels(_channel_ids, nil), do: %{}

  def count_unread_for_channels(channel_ids, session_id) do
    alias EyeInTheSky.Messages.Message

    from(m in Message,
      left_join: cm in ChannelMember,
      on: cm.channel_id == m.channel_id and cm.session_id == ^session_id,
      where: m.channel_id in ^channel_ids,
      where: is_nil(cm.last_read_at) or m.inserted_at > cm.last_read_at,
      group_by: m.channel_id,
      select: {m.channel_id, count(m.id)}
    )
    |> Repo.all()
    |> Map.new()
  end

  @doc """
  Checks if a session is a member of a channel.
  """
  def member?(channel_id, session_id) do
    channel_member_query(channel_id, session_id)
    |> Repo.exists?()
  end

  @doc """
  Gets a channel member record.
  """
  def get_member(channel_id, session_id) do
    case channel_member_query(channel_id, session_id)
         |> Repo.one() do
      nil -> {:error, :not_found}
      member -> {:ok, member}
    end
  end

  @doc """
  Updates a member's last_read_at timestamp.
  """
  def mark_as_read(channel_id, session_id) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    channel_member_query(channel_id, session_id)
    |> Repo.update_all(set: [last_read_at: now])
  end

  @doc """
  Finds the global (#global) channel for a session, scoped to the session's project if set.

  Returns `{:ok, channel}` or `{:error, :not_found}`.
  """
  def find_global_channel(session) do
    # Direct query instead of loading all channels then Enum.find-ing #global.
    query =
      from c in Channel,
        where: c.name == "#global" and is_nil(c.archived_at),
        limit: 1

    query =
      if session.project_id do
        where(query, [c], c.project_id == ^session.project_id or is_nil(c.project_id))
      else
        query
      end

    case Repo.one(query) do
      nil -> {:error, :not_found}
      channel -> {:ok, channel}
    end
  end

  @doc """
  Returns channel members with notifications enabled, excluding a given sender session.

  Used to fan out DMs when a channel message is posted.
  Only returns members with `notifications = "all"` and a non-nil `session_id`.
  """
  def list_members_for_notification(channel_id, exclude_session_id) do
    terminated = ~w(completed failed)

    from(m in ChannelMember,
      join: s in EyeInTheSky.Sessions.Session,
      on: s.id == m.session_id,
      where:
        m.channel_id == ^channel_id and
          m.notifications == "all" and
          not is_nil(m.session_id) and
          m.session_id != ^exclude_session_id and
          s.status not in ^terminated,
      order_by: [asc: m.joined_at]
    )
    |> Repo.all()
  end

end
