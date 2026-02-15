defmodule EyeInTheSkyWeb.Channels do
  @moduledoc """
  The Channels context for managing multi-agent chat channels.
  """

  import Ecto.Query, warn: false
  alias EyeInTheSkyWeb.Repo
  alias EyeInTheSkyWeb.Channels.{Channel, ChannelMember}

  @doc """
  Returns the list of channels for a specific project, including global channels (project_id is NULL).
  """
  def list_channels_for_project(project_id, opts \\ []) do
    include_archived = Keyword.get(opts, :include_archived, false)

    query =
      from c in Channel,
        where: c.project_id == ^project_id or is_nil(c.project_id),
        order_by: [asc: c.inserted_at]

    query =
      if include_archived do
        query
      else
        from c in query, where: is_nil(c.archived_at)
      end

    Repo.all(query)
  end

  @doc """
  Gets a single channel.

  Raises `Ecto.NoResultsError` if the Channel does not exist.
  """
  def get_channel!(id) do
    Repo.get!(Channel, id)
  end

  @doc """
  Gets a channel by ID, returns {:ok, channel} or {:error, :not_found}.
  """
  def get_channel(id) do
    case Repo.get(Channel, id) do
      nil -> {:error, :not_found}
      channel -> {:ok, channel}
    end
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
  Archives a channel (soft delete).
  """
  def archive_channel(%Channel{} = channel) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    update_channel(channel, %{archived_at: now})
  end

  @doc """
  Unarchives a channel.
  """
  def unarchive_channel(%Channel{} = channel) do
    update_channel(channel, %{archived_at: nil})
  end

  @doc """
  Deletes a channel (hard delete).
  """
  def delete_channel(%Channel{} = channel) do
    Repo.delete(channel)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking channel changes.
  """
  def change_channel(%Channel{} = channel, attrs \\ %{}) do
    Channel.changeset(channel, attrs)
  end

  # Channel Membership Functions

  @doc """
  Adds a member to a channel.
  """
  def add_member(channel_id, agent_id, session_id, role \\ "member") do
    alias EyeInTheSkyWeb.Agents
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    session_uuid =
      case Agents.get_execution_agent(session_id) do
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
    |> Repo.insert()
  end

  @doc """
  Removes a member from a channel.
  """
  def remove_member(channel_id, session_id) do
    from(m in ChannelMember,
      where: m.channel_id == ^channel_id and m.session_id == ^session_id
    )
    |> Repo.delete_all()
  end

  @doc """
  Lists all members of a channel.
  """
  def list_members(channel_id) do
    from(m in ChannelMember,
      where: m.channel_id == ^channel_id,
      order_by: [asc: m.joined_at]
    )
    |> Repo.all()
  end

  @doc """
  Checks if a session is a member of a channel.
  """
  def is_member?(channel_id, session_id) do
    from(m in ChannelMember,
      where: m.channel_id == ^channel_id and m.session_id == ^session_id
    )
    |> Repo.exists?()
  end

  @doc """
  Gets a channel member record.
  """
  def get_member(channel_id, session_id) do
    from(m in ChannelMember,
      where: m.channel_id == ^channel_id and m.session_id == ^session_id
    )
    |> Repo.one()
  end

  @doc """
  Updates a member's last_read_at timestamp.
  """
  def mark_as_read(channel_id, session_id) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    from(m in ChannelMember,
      where: m.channel_id == ^channel_id and m.session_id == ^session_id
    )
    |> Repo.update_all(set: [last_read_at: now])
  end

  @doc """
  Lists all channels that a session is a member of.
  """
  def list_channels_for_session(session_id) do
    from(c in Channel,
      join: m in ChannelMember,
      on: m.channel_id == c.id,
      where: m.session_id == ^session_id and is_nil(c.archived_at),
      order_by: [asc: c.inserted_at]
    )
    |> Repo.all()
  end

  @doc """
  Counts unread messages for a session in a channel.
  """
  def count_unread_messages(channel_id, session_id) do
    alias EyeInTheSkyWeb.Messages.Message

    member = get_member(channel_id, session_id)

    if member && member.last_read_at do
      from(m in Message,
        where: m.channel_id == ^channel_id and m.inserted_at > ^member.last_read_at
      )
      |> Repo.aggregate(:count)
    else
      # Never read, count all messages
      from(m in Message,
        where: m.channel_id == ^channel_id
      )
      |> Repo.aggregate(:count)
    end
  end
end
