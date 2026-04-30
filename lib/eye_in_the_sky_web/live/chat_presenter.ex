defmodule EyeInTheSkyWeb.ChatPresenter do
  @moduledoc """
  Pure serialization helpers for ChatLive.
  Handles data shaping before assigns hit the template.
  No DB queries — only transforms already-loaded data.
  """

  def serialize_channels(channels) do
    Enum.map(channels, fn channel ->
      %{
        id: channel.id,
        name: channel.name,
        description: channel.description,
        channel_type: channel.channel_type
      }
    end)
  end

  def serialize_messages(messages), do: Enum.map(messages, &serialize_message/1)

  def serialize_message(message) do
    session_name =
      if Ecto.assoc_loaded?(message.session) && message.session do
        message.session.name
      else
        nil
      end

    session_uuid =
      if Ecto.assoc_loaded?(message.session) && message.session do
        message.session.uuid
      else
        nil
      end

    %{
      id: message.id,
      number: message.channel_message_number,
      session_id: message.session_id,
      session_uuid: session_uuid,
      session_name: session_name,
      sender_role: message.sender_role,
      direction: message.direction,
      body: message.body,
      provider: message.provider,
      status: message.status,
      inserted_at: message.inserted_at,
      thread_reply_count: message.thread_reply_count || 0,
      reactions: serialize_reactions(message),
      metadata: message.metadata || %{}
    }
  end

  defp serialize_reactions(message) do
    if Ecto.assoc_loaded?(message.reactions) do
      message.reactions
      |> Enum.group_by(& &1.emoji)
      |> Enum.map(fn {emoji, reactions} ->
        %{
          emoji: emoji,
          count: length(reactions),
          session_ids: Enum.map(reactions, & &1.session_id)
        }
      end)
    else
      []
    end
  end

  def serialize_prompts(prompts) do
    Enum.map(prompts, fn prompt ->
      %{
        id: prompt.id,
        name: prompt.name,
        slug: prompt.slug,
        description: prompt.description,
        prompt_text: prompt.prompt_text
      }
    end)
  end
end
