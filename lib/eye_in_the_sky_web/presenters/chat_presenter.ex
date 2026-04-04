defmodule EyeInTheSkyWeb.Presenters.ChatPresenter do
  @moduledoc """
  Presenter utilities for Chat views: serializers and counters.
  """

  @spec serialize_channels(list(map())) :: list(map())
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

  @spec serialize_messages(list(map())) :: list(map())
  def serialize_messages(messages) do
    Enum.map(messages, &serialize_message/1)
  end

  @spec serialize_message(map()) :: map()
  def serialize_message(message) do
    session_name =
      if Ecto.assoc_loaded?(message.session) && message.session do
        message.session.name
      else
        nil
      end

    %{
      id: message.id,
      session_id: message.session_id,
      session_name: session_name,
      sender_role: message.sender_role,
      direction: message.direction,
      body: message.body,
      provider: message.provider,
      status: message.status,
      inserted_at: message.inserted_at,
      thread_reply_count: message.thread_reply_count || 0,
      reactions: serialize_reactions(message)
    }
  end

  @spec serialize_reactions(map()) :: list(map())
  def serialize_reactions(message) do
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

end
