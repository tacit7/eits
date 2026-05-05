defmodule EyeInTheSky.Channels.ChannelOnboarding do
  @moduledoc """
  Sends a one-time onboarding DM to an agent when it joins a channel.

  Idempotent: skipped when `onboarded_at` is already set on the member record.
  """

  require Logger

  alias EyeInTheSky.ChannelMessages
  alias EyeInTheSky.Repo
  alias EyeInTheSky.Channels.ChannelMember

  import Ecto.Query, warn: false

  @snapshot_limit 8
  @body_max 120

  @doc """
  Delivers an onboarding DM to the session associated with `member`, then
  stamps `onboarded_at` on the member row.

  Skips silently when:
  - `member.onboarded_at` is already set (rejoin guard)
  - `member.session_id` is nil
  - AgentManager cannot find or start a worker for the session

  Returns `:ok` in all cases — callers should not branch on this result.
  """
  def deliver(member, channel) do
    cond do
      not is_nil(member.onboarded_at) ->
        :ok

      is_nil(member.session_id) ->
        :ok

      true ->
        recent = ChannelMessages.list_messages_for_channel(channel.id, limit: @snapshot_limit)
        message = build_message(channel, recent)
        agent_manager = Application.get_env(:eye_in_the_sky, :agent_manager_module, EyeInTheSky.Agents.AgentManager)

        case agent_manager.send_message(member.session_id, message) do
          {:ok, _} ->
            stamp_onboarded_at(member)

          {:error, reason} ->
            Logger.warning(
              "ChannelOnboarding: failed to send DM to session #{member.session_id} — #{inspect(reason)}"
            )

            :ok
        end
    end
  end

  defp stamp_onboarded_at(member) do
    now = DateTime.utc_now()

    from(m in ChannelMember,
      where: m.id == ^member.id,
      where: is_nil(m.onboarded_at)
    )
    |> Repo.update_all(set: [onboarded_at: now])

    :ok
  end

  defp build_message(channel, recent_messages) do
    snapshot = format_snapshot(recent_messages, channel.id)

    """
    You have been added to Channel ##{channel.name} (#{channel.id}).

    This is a shared channel with users and other agents.
    #{snapshot}
    To read more history:
      eits channels messages #{channel.id} --limit 20

    To send a message:
      eits channels send #{channel.id} --body "your reply"

    To mention a specific participant:
      Include @<session_id> in your message body.

    When a channel message is directed at you, it will arrive as a prompt
    starting with:

      MSG from Channel ##{channel.name} (#{channel.id})

    Important:
    Do not answer channel prompts directly in this DM unless you are
    explaining that you cannot respond. To respond to the channel, use:

      eits channels send #{channel.id} --body "your response"

    A normal DM response will NOT be posted to the channel.\
    """
  end

  defp format_snapshot([], _channel_id), do: "\n"

  defp format_snapshot(messages, _channel_id) do
    lines =
      messages
      |> Enum.map(fn msg ->
        sender = sender_name(msg)
        body = truncate(msg.body, @body_max)
        "  [#{sender}] #{body}"
      end)
      |> Enum.join("\n")

    "\nRecent activity:\n#{lines}\n\n"
  end

  defp sender_name(%{session: %{name: name}}) when is_binary(name) and name != "",
    do: name

  defp sender_name(%{session: %{id: id}}), do: "session:#{id}"
  defp sender_name(_), do: "unknown"

  defp truncate(body, max) when is_binary(body) do
    body = String.replace(body, "\n", " ")

    if String.length(body) > max do
      String.slice(body, 0, max) <> "…"
    else
      body
    end
  end

  defp truncate(_, _max), do: ""
end
