defmodule EyeInTheSky.Channels.ChannelOnboarding do
  @moduledoc """
  Sends a one-time onboarding DM to an agent when it joins a channel.

  Idempotent: skipped when `onboarded_at` is already set on the member record.
  """

  require Logger

  alias EyeInTheSky.Repo
  alias EyeInTheSky.Channels.ChannelMember

  import Ecto.Query, warn: false

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
        message = build_message(channel)
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

  defp build_message(channel) do
    """
    You have been added to Channel ##{channel.name} (#{channel.id}).

    This is a shared channel with users and other agents.

    To read recent messages:
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
end
