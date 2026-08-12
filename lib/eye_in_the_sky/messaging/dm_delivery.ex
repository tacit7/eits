defmodule EyeInTheSky.Messaging.DMDelivery do
  @moduledoc "Single entry point for delivering and persisting DMs."

  alias EyeInTheSky.Agents.AgentManager
  alias EyeInTheSky.Messages
  alias EyeInTheSky.Sessions

  @doc """
  Send a DM to `to_session_id`, persist it, and broadcast a PubSub event.

  Returns `{:ok, message}` or `{:error, reason}`.
  """
  def deliver_and_persist(to_session_id, from_session_id, body, metadata \\ %{}) do
    # Pass metadata as context to the agent manager so the worker can use it
    opts = if metadata && metadata != %{}, do: [dm_metadata: metadata], else: []

    case agent_manager_mod().send_message(to_session_id, body, opts) do
      result when result == :ok or (is_tuple(result) and elem(result, 0) == :ok) ->
        persist(to_session_id, from_session_id, body, metadata)

      {:error, _} = err ->
        err
    end
  end

  @doc """
  Deliver to a live worker when possible, but persist directly for terminal sessions.

  CLI/headless sessions read from the durable inbox. A completed or failed
  session has no live worker to accept the message, but it is still a valid DM
  recipient for later polling or inspection.
  """
  def deliver_or_persist(to_session_id, from_session_id, body, metadata \\ %{}) do
    case Sessions.get_session(to_session_id) do
      {:ok, session} ->
        if session.status in Sessions.terminated_statuses() do
          persist(to_session_id, from_session_id, body, metadata)
        else
          deliver_and_persist(to_session_id, from_session_id, body, metadata)
        end

      _ ->
        deliver_and_persist(to_session_id, from_session_id, body, metadata)
    end
  end

  @doc """
  Persist a DM without requiring a live session worker.

  CLI/headless sessions poll their durable inbox, so completed sessions still
  need to accept stored DMs even when no worker is running.
  """
  def persist(to_session_id, from_session_id, body, metadata \\ %{}) do
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
  end

  defp agent_manager_mod do
    Application.get_env(:eye_in_the_sky, :agent_manager_module, AgentManager)
  end
end
