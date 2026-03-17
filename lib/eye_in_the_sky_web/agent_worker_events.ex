defmodule EyeInTheSkyWeb.AgentWorkerEvents do
  @moduledoc """
  Handles all side effects triggered by AgentWorker state transitions.

  The worker decides WHAT happened (SDK started, completed, errored).
  This module decides HOW to react: DB writes, PubSub broadcasts,
  notifications, team member updates. All DB operations are fire-and-forget
  via Task.start to avoid blocking the worker GenServer.
  """

  require Logger

  alias EyeInTheSkyWeb.{Messages, Sessions}

  alias EyeInTheSkyWeb.Events

  # --- Lifecycle Events ---

  @doc "SDK started processing a job."
  def on_sdk_started(session_id, provider_conversation_id) do
    update_session_status(session_id, "working")
    Events.agent_working(provider_conversation_id, session_id)
  end

  @doc "SDK completed successfully."
  def on_sdk_completed(session_id, provider_conversation_id) do
    update_session_status(session_id, "idle")
    Events.agent_stopped(provider_conversation_id, session_id)
    notify_agent_complete(session_id, provider_conversation_id)
  end

  @doc "SDK errored (transient or systemic)."
  def on_sdk_errored(session_id, provider_conversation_id) do
    update_session_status(session_id, "idle")
    Events.agent_stopped(provider_conversation_id, session_id)
  end

  @doc "Max retries exceeded — worker giving up."
  def on_max_retries_exceeded(session_id, provider_conversation_id) do
    Events.stream_error(session_id, provider_conversation_id, "Max retries exceeded")
    update_session_status(session_id, "error")
    Events.agent_stopped(provider_conversation_id, session_id)
  end

  @doc "SDK spawn failed — record system error message."
  def on_spawn_error(session_id, reason) do
    reason_str = inspect(reason)

    Messages.record_incoming_reply(
      session_id,
      "system",
      "[spawn error] Failed to start Claude: #{reason_str}"
    )
  end

  @doc "Systemic error draining queued jobs."
  def on_queue_drained(session_id, provider_conversation_id, queue, reason) do
    reason_str = inspect(reason)

    Enum.each(queue, fn _job ->
      Events.stream_error(
        session_id,
        provider_conversation_id,
        "Queued job dropped due to systemic error: #{reason_str}"
      )
    end)
  end

  # --- Data Events ---

  @doc "Result received from SDK — save to DB."
  def on_result_received(session_id, provider, text, metadata, channel_id) when is_binary(text) do
    Task.start(fn ->
      if String.trim(text) in ["", "[NO_RESPONSE]"] do
        Logger.info("[#{session_id}] Skipping DB save — empty or suppressed response")
      else
        db_metadata = %{
          duration_ms: metadata[:duration_ms],
          total_cost_usd: metadata[:total_cost_usd],
          usage: metadata[:usage],
          model_usage: metadata[:model_usage],
          num_turns: metadata[:num_turns],
          is_error: metadata[:is_error]
        }

        opts = [metadata: db_metadata]
        opts = if channel_id, do: Keyword.put(opts, :channel_id, channel_id), else: opts

        case Messages.record_incoming_reply(session_id, provider, text, opts) do
          {:ok, _message} ->
            :ok

          {:error, reason} ->
            Logger.warning("[#{session_id}] DB save failed: #{inspect(reason)}")
        end
      end
    end)
  end

  def on_result_received(session_id, _provider, _text, _metadata, _channel_id) do
    Logger.warning("[#{session_id}] Result has no text content")
  end

  @doc "Provider conversation ID changed — sync to DB."
  def on_provider_conversation_id_changed(session_id, old_id, new_id) do
    Task.start(fn ->
      case Sessions.get_session(session_id) do
        {:ok, session} ->
          case Sessions.update_session(session, %{uuid: new_id}) do
            {:ok, _updated} ->
              Logger.info("[#{session_id}] Updated session uuid #{old_id} -> #{new_id}")

            {:error, reason} ->
              Logger.warning("[#{session_id}] Failed to update session uuid: #{inspect(reason)}")
          end

        {:error, reason} ->
          Logger.warning(
            "[#{session_id}] Failed to load session for uuid sync: #{inspect(reason)}"
          )
      end
    end)
  end

  # --- Broadcast Helpers ---

  @doc "Clear the stream display."
  def broadcast_stream_clear(session_id) do
    Events.stream_clear(session_id)
  end

  @doc "Broadcast queue state change."
  def broadcast_queue_update(session_id, queue) do
    Events.queue_updated(session_id, queue)
  end

  defp update_session_status(session_id, status) do
    Task.start(fn ->
      case Sessions.get_session(session_id) do
        {:ok, session} ->
          attrs = %{status: status}

          attrs =
            if status == "idle" do
              Map.put(attrs, :last_activity_at, DateTime.utc_now() |> DateTime.to_iso8601())
            else
              attrs
            end

          case Sessions.update_session(session, attrs) do
            {:ok, _} -> :ok

            {:error, reason} ->
              Logger.warning(
                "[#{session_id}] update_session_status failed: #{inspect(reason)}"
              )
          end

          if status == "idle" do
            Events.session_idle(session_id)
          end

        {:error, _} ->
          :ok
      end
    end)
  end

  defp notify_agent_complete(session_id, provider_conversation_id) do
    Task.start(fn ->
      title =
        case Sessions.get_session(session_id) do
          {:ok, session} when is_binary(session.name) and session.name != "" ->
            String.slice("Agent finished: #{session.name}", 0, 255)

          _ ->
            "Agent finished"
        end

      EyeInTheSkyWeb.Notifications.notify(title,
        category: :agent,
        resource: {"session", provider_conversation_id}
      )
    end)
  end
end
