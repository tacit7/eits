defmodule EyeInTheSky.MessageReactions do
  @moduledoc """
  Context for managing message reactions (emoji responses).
  """

  import Ecto.Query, warn: false
  alias EyeInTheSky.Repo
  alias EyeInTheSky.Messages.MessageReaction

  @doc """
  Adds a reaction to a message.
  """
  def add_reaction(message_id, session_id, emoji) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    attrs = %{
      message_id: message_id,
      session_id: session_id,
      emoji: emoji,
      inserted_at: now
    }

    %MessageReaction{}
    |> MessageReaction.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Removes a reaction from a message.
  """
  def remove_reaction(message_id, session_id, emoji) do
    from(r in MessageReaction,
      where: r.message_id == ^message_id and r.session_id == ^session_id and r.emoji == ^emoji
    )
    |> Repo.delete_all()
  end

  @doc """
  Lists all reactions for a message, grouped by emoji.
  """
  def list_reactions_for_message(message_id) do
    from(r in MessageReaction,
      where: r.message_id == ^message_id,
      order_by: [asc: r.inserted_at]
    )
    |> Repo.all()
    |> Enum.group_by(& &1.emoji)
    |> Enum.map(fn {emoji, reactions} ->
      %{
        emoji: emoji,
        count: length(reactions),
        session_ids: Enum.map(reactions, & &1.session_id)
      }
    end)
  end

  @doc """
  Toggles a reaction (adds if not present, removes if present).
  """
  def toggle_reaction(message_id, session_id, emoji) do
    existing =
      from(r in MessageReaction,
        where: r.message_id == ^message_id and r.session_id == ^session_id and r.emoji == ^emoji
      )
      |> Repo.one()

    if existing do
      remove_reaction(message_id, session_id, emoji)
      {:ok, :removed}
    else
      case add_reaction(message_id, session_id, emoji) do
        {:ok, _reaction} -> {:ok, :added}
        error -> error
      end
    end
  end
end
