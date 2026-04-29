defmodule EyeInTheSky.Messaging.DMDelivery do
  @moduledoc "Single entry point for delivering and persisting DMs."

  alias EyeInTheSky.Messages
  alias EyeInTheSky.Agents.AgentManager

  @doc """
  Send a DM to `to_session_id`, persist it, and broadcast a PubSub event.

  Returns `{:ok, message}` or `{:error, reason}`.
  """
  def deliver_and_persist(to_session_id, from_session_id, body, metadata \\ %{}) do
    # Pass metadata as context to the agent manager so the worker can use it
    opts = if metadata && metadata != %{}, do: [dm_metadata: metadata], else: []
    case agent_manager_mod().send_message(to_session_id, body, opts) do
      result when result == :ok or (is_tuple(result) and elem(result, 0) == :ok) ->
        attrs = %{
          uuid: Ecto.UUID.generate(),
          session_id: to_session_id,
          from_session_id: from_session_id,
          to_session_id: to_session_id,
          body: body,
          sender_role: "agent",
          recipient_role: "agent",
          direction: "inbound",
          status: "sent",
          provider: "claude",
          metadata: metadata
        }

        case Messages.create_message(attrs) do
          {:ok, msg} ->
            EyeInTheSky.Events.session_new_dm(to_session_id, msg)
            {:ok, msg}

          {:error, _} = err ->
            err
        end

      {:error, _} = err ->
        err
    end
  end

  defp agent_manager_mod do
    Application.get_env(:eye_in_the_sky, :agent_manager_module, AgentManager)
  end
end
