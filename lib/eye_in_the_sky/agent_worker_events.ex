defmodule EyeInTheSky.AgentWorkerEvents do
  @moduledoc """
  Handles all side effects triggered by AgentWorker state transitions.

  The worker decides WHAT happened (SDK started, completed, errored).
  This module decides HOW to react: DB writes, PubSub broadcasts,
  notifications, team member updates.

  ## Concurrency strategy

  - Status updates and UUID syncs are **synchronous** — they are fast DB writes
    where ordering matters. Running them in a Task risks race conditions (two
    concurrent read-then-write pairs) and stale PubSub broadcasts on DB failure.
  - Result saves and notifications are **supervised async** via
    `Task.Supervisor.start_child/2`. Crashes are visible in logs/telemetry;
    the worker is not blocked waiting for non-critical side effects.
  """

  require Logger

  alias EyeInTheSky.{Agents, Messages, Sessions}

  alias EyeInTheSky.Claude.AgentWorker.ErrorClassifier
  alias EyeInTheSky.Events

  # --- Lifecycle Events ---

  @doc "SDK started processing a job. Promotes agent to running if still pending."
  def on_sdk_started(session_id, _provider_conversation_id) do
    case update_session_status(session_id, "working") do
      {:ok, session} ->
        promote_agent_if_pending(session_id)
        Events.agent_working(session)

      :error ->
        :ok
    end
  end

  @doc """
  SDK completed successfully.

  Claude sessions transition to `idle` (ready for the next prompt). Codex
  sessions transition to `waiting` — the headless run ended and the thread
  is dormant until explicitly resumed. Both clear `status_reason`.
  """
  def on_sdk_completed(session_id, provider_conversation_id, provider \\ "claude") do
    status = completion_status_for(provider)

    case update_session_status(session_id, status, nil) do
      {:ok, session} ->
        Events.agent_stopped(session)
        notify_agent_complete(session_id, provider_conversation_id)

      :error ->
        :ok
    end
  end

  defp completion_status_for("codex"), do: "waiting"
  defp completion_status_for(_), do: "idle"

  @doc "Codex thread.started received — confirm session is working."
  def on_codex_thread_started(session_id) do
    update_session_status(session_id, "working")
    :ok
  end

  @doc "SDK errored (transient or systemic)."
  def on_sdk_errored(session_id, _provider_conversation_id) do
    case update_session_status(session_id, "idle") do
      {:ok, session} -> Events.agent_stopped(session)
      :error -> :ok
    end
  end

  @doc "Max retries exceeded — worker giving up."
  def on_max_retries_exceeded(session_id, provider_conversation_id, reason \\ :retry_exhausted) do
    Events.stream_error(session_id, provider_conversation_id, "Max retries exceeded")

    case update_session_status(session_id, "failed", ErrorClassifier.status_reason(reason)) do
      {:ok, session} -> Events.agent_stopped(session)
      :error -> :ok
    end
  end

  @doc """
  Worker hit a systemic error (billing/auth/watchdog) — overwrite idle DB status
  with failed and record the reason so the UI can render a distinct badge
  ('Billing', 'Auth', etc.) instead of generic 'Failed'. `reason` is required
  (no default) to prevent silent nil-writes from future callers.
  """
  def on_session_failed(session_id, provider_conversation_id, reason) do
    Events.stream_error(session_id, provider_conversation_id, "Systemic error — session failed")
    update_session_status(session_id, "failed", ErrorClassifier.status_reason(reason))
    :ok
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

  @doc "Systemic error draining queued jobs. Marks each as failed in DB before clearing."
  def on_queue_drained(
        %{session_id: session_id, provider_conversation_id: pcid, queue: queue},
        reason
      ) do
    reason_str = failure_message(reason)

    Enum.each(queue, fn job ->
      Messages.mark_failed(job.context[:message_id], reason_str)

      Events.stream_error(
        session_id,
        pcid,
        "Queued job dropped due to systemic error: #{reason_str}"
      )
    end)
  end

  @doc "Marks the current (active) job failed when a systemic error occurs."
  def on_current_job_failed(nil, _reason), do: :ok

  def on_current_job_failed(job, reason) do
    Messages.mark_failed(job.context[:message_id], failure_message(reason))
  end

  # Produces free-form strings persisted to `messages.last_error` (debug field,
  # no enum constraint). Different from `ErrorClassifier.status_reason/1` which
  # returns the enum-constrained category string for `sessions.status_reason`.
  defp failure_message({:billing_error, _}), do: "billing_error"
  defp failure_message({:authentication_error, _}), do: "authentication_error"

  defp failure_message({:unknown_error, msg}) when is_binary(msg),
    do: "unknown_error: #{String.slice(msg, 0, 120)}"

  defp failure_message(:retry_exhausted), do: "retry_exhausted"

  defp failure_message({:watchdog_timeout, timeout_ms}),
    do: "watchdog_timeout: #{timeout_ms}ms"

  defp failure_message(reason), do: inspect(reason) |> String.slice(0, 120)

  # --- Data Events ---

  @doc "Result received from SDK — save to DB synchronously so the message is committed before claude_complete fires."
  def on_result_received(session_id, %{
        provider: provider,
        text: text,
        metadata: metadata,
        channel_id: channel_id,
        source_uuid: source_uuid
      })
      when is_binary(text) do
    if String.trim(text) in ["", "[NO_RESPONSE]"] do
      Logger.info("[#{session_id}] Skipping DB save — empty or suppressed response")
    else
      save_result(session_id, provider, text, metadata, channel_id, source_uuid)
    end

    :ok
  end

  def on_result_received(session_id, _params) do
    Logger.warning("[#{session_id}] Result has no text content")
  end

  @doc "Provider conversation ID changed — sync to DB (synchronous: ordering is critical)."
  def on_provider_conversation_id_changed(session_id, old_id, new_id) do
    case Sessions.get_session(session_id) do
      {:ok, session} ->
        case Sessions.update_session(session, %{uuid: new_id}) do
          {:ok, _updated} ->
            Logger.info("[#{session_id}] Updated session uuid #{old_id} -> #{new_id}")

          {:error, reason} ->
            Logger.warning("[#{session_id}] Failed to update session uuid: #{inspect(reason)}")
        end

      {:error, reason} ->
        Logger.warning("[#{session_id}] Failed to load session for uuid sync: #{inspect(reason)}")
    end
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

  defp save_result(session_id, provider, text, metadata, channel_id, source_uuid) do
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
    opts = if source_uuid, do: Keyword.put(opts, :source_uuid, source_uuid), else: opts

    case Messages.record_incoming_reply(session_id, provider, text, opts) do
      {:ok, _message} -> :ok
      {:error, reason} -> Logger.warning("[#{session_id}] DB save failed: #{inspect(reason)}")
    end
  end

  # Synchronous — fast DB write where ordering matters. Running in a Task risks
  # two concurrent read-then-write pairs racing each other, and the session_idle
  # broadcast must only fire after a successful update.
  # Returns {:ok, updated_session} or :error.
  defp update_session_status(session_id, status, reason \\ nil) do
    idle_like? = status in ["idle", "waiting"]

    attrs =
      if idle_like?,
        do: %{status: status, last_activity_at: DateTime.utc_now()},
        else: %{status: status}

    attrs = Map.put(attrs, :status_reason, reason)

    case Sessions.get_session(session_id) do
      {:ok, session} -> apply_session_update(session, attrs, session_id, idle_like?)
      {:error, _} -> :error
    end
  end

  defp apply_session_update(session, attrs, session_id, idle_like?) do
    case Sessions.update_session(session, attrs) do
      {:ok, updated} ->
        if idle_like?, do: Events.session_idle(session_id)
        Events.session_status(session_id, updated.status)
        {:ok, updated}

      {:error, reason} ->
        Logger.warning("[#{session_id}] update_session_status failed: #{inspect(reason)}")
        :error
    end
  end

  # Synchronous — no Task.start. The promotion must complete before the next
  # event fires, and Task.start spawns a process outside the SQL sandbox in tests.
  defp promote_agent_if_pending(session_id) do
    with {:ok, session} when not is_nil(session.agent_id) <- Sessions.get_session(session_id),
         {:ok, %{status: "pending"} = agent} <- Agents.get_agent(session.agent_id),
         {:ok, _} <- Agents.update_agent(agent, %{status: "running"}) do
      Logger.info("[#{session_id}] Promoted agent #{agent.id} from pending to running")
    else
      {:error, reason} ->
        Logger.warning("[#{session_id}] Failed to promote agent: #{inspect(reason)}")

      {:ok, _} ->
        # agent_id is nil or agent status is not "pending" — nothing to do
        :ok
    end
  end

  defp notify_agent_complete(session_id, provider_conversation_id) do
    # Skip in test mode. Running Notifications.notify in a synchronous Task
    # (via AsyncTask in test mode) inside AgentWorker.handle_info races with
    # sandbox teardown: the handle_info may still be executing when the test
    # process exits, crashing the GenServer and eventually the AgentSupervisor.
    # Notifications are tested directly in notifications_test.exs.
    # Skip when the user has not opted in to agent completion notifications.
    if Application.get_env(:eye_in_the_sky, :async_tasks_sync, false) or
         not EyeInTheSky.Settings.get_boolean("agent_notifications") do
      :ok
    else
      meta = Logger.metadata()

      Task.Supervisor.start_child(EyeInTheSky.TaskSupervisor, fn ->
        Logger.metadata(meta)

        title =
          case Sessions.get_session(session_id) do
            {:ok, session} when is_binary(session.name) and session.name != "" ->
              String.slice("Agent finished: #{session.name}", 0, 255)

            _ ->
              "Agent finished"
          end

        EyeInTheSky.Notifications.notify(title,
          category: :agent,
          resource: {"session", provider_conversation_id}
        )
      end)

      :ok
    end
  end
end
