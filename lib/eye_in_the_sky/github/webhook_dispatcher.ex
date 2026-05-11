defmodule EyeInTheSky.Github.WebhookDispatcher do
  use GenServer

  require Logger

  alias EyeInTheSky.Events
  alias EyeInTheSky.Github.WebhookDeliveries
  alias EyeInTheSky.Github.EventContext
  alias EyeInTheSky.Github.PullRequestHandler
  alias EyeInTheSky.Github.PushHandler
  alias EyeInTheSky.Github.CheckRunHandler
  alias EyeInTheSky.Github.WebhookRulesExecutor

  @stale_minutes 5
  @recovery_interval_ms 60_000

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl GenServer
  def init(_opts) do
    Events.subscribe_github_webhook()
    send(self(), :recover)
    {:ok, %{}}
  end

  @impl GenServer
  def handle_info({:github_webhook_received, delivery_id}, state) do
    process(delivery_id)
    {:noreply, state}
  end

  def handle_info(:recover, state) do
    recover_pending()
    recover_stale()
    Process.send_after(self(), :recover, @recovery_interval_ms)
    {:noreply, state}
  end

  def handle_info(_, state), do: {:noreply, state}

  defp process(delivery_id) do
    case WebhookDeliveries.claim(delivery_id) do
      {:ok, delivery} ->
        ctx =
          EventContext.from_delivery(%{
            delivery_id: delivery.delivery_id,
            event_type: delivery.event_type,
            repository_full_name: delivery.repository_full_name,
            sender_login: delivery.sender_login,
            payload: delivery.payload
          })

        try do
          run_built_ins(ctx, delivery.event_type)
          WebhookRulesExecutor.run(ctx)
          WebhookDeliveries.mark_processed(delivery.id)
        rescue
          e ->
            Logger.error("Webhook processing failed for #{delivery_id}: #{Exception.message(e)}")
            WebhookDeliveries.mark_failed(delivery.id, Exception.message(e))
        end

      {:error, :not_claimable} ->
        :ok
    end
  end

  defp run_built_ins(ctx, "pull_request" <> _), do: PullRequestHandler.handle(ctx)
  defp run_built_ins(ctx, "push"), do: PushHandler.handle(ctx)
  defp run_built_ins(ctx, "check_run" <> _), do: CheckRunHandler.handle(ctx)
  defp run_built_ins(_, _), do: :ok

  defp recover_pending do
    WebhookDeliveries.pending()
    |> Enum.each(&process(&1.delivery_id))
  end

  defp recover_stale do
    cutoff = DateTime.add(DateTime.utc_now(), @stale_minutes * 60)

    WebhookDeliveries.stale_processing(cutoff)
    |> Enum.each(fn delivery ->
      if delivery.attempt_count >= delivery.max_attempts do
        WebhookDeliveries.mark_failed(delivery.id, "max attempts exceeded")
      else
        WebhookDeliveries.reset_to_pending(delivery.id)
        process(delivery.delivery_id)
      end
    end)
  end
end
