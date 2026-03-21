defmodule EyeInTheSkyWeb.Telemetry do
  use Supervisor
  import Telemetry.Metrics

  def start_link(arg) do
    Supervisor.start_link(__MODULE__, arg, name: __MODULE__)
  end

  @impl true
  def init(_arg) do
    children = [
      # Telemetry poller will execute the given period measurements
      # every 10_000ms. Learn more here: https://hexdocs.pm/telemetry_metrics
      {:telemetry_poller, measurements: periodic_measurements(), period: 10_000}
      # Add reporters as children of your supervision tree.
      # {Telemetry.Metrics.ConsoleReporter, metrics: metrics()}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  def metrics do
    [
      # Phoenix Metrics
      summary("phoenix.endpoint.start.system_time",
        unit: {:native, :millisecond}
      ),
      summary("phoenix.endpoint.stop.duration",
        unit: {:native, :millisecond}
      ),
      summary("phoenix.router_dispatch.start.system_time",
        tags: [:route],
        unit: {:native, :millisecond}
      ),
      summary("phoenix.router_dispatch.exception.duration",
        tags: [:route],
        unit: {:native, :millisecond}
      ),
      summary("phoenix.router_dispatch.stop.duration",
        tags: [:route],
        unit: {:native, :millisecond}
      ),
      summary("phoenix.socket_connected.duration",
        unit: {:native, :millisecond}
      ),
      sum("phoenix.socket_drain.count"),
      summary("phoenix.channel_joined.duration",
        unit: {:native, :millisecond}
      ),
      summary("phoenix.channel_handled_in.duration",
        tags: [:event],
        unit: {:native, :millisecond}
      ),

      # Database Metrics
      summary("eye_in_the_sky.repo.query.total_time",
        unit: {:native, :millisecond},
        description: "The sum of the other measurements"
      ),
      summary("eye_in_the_sky.repo.query.decode_time",
        unit: {:native, :millisecond},
        description: "The time spent decoding the data received from the database"
      ),
      summary("eye_in_the_sky.repo.query.query_time",
        unit: {:native, :millisecond},
        description: "The time spent executing the query"
      ),
      summary("eye_in_the_sky.repo.query.queue_time",
        unit: {:native, :millisecond},
        description: "The time spent waiting for a database connection"
      ),
      summary("eye_in_the_sky.repo.query.idle_time",
        unit: {:native, :millisecond},
        description:
          "The time the connection spent waiting before being checked out for the query"
      ),

      # Claude SDK Metrics
      counter("eits.sdk.start.count"),
      counter("eits.sdk.complete.count"),
      counter("eits.sdk.error.count"),
      counter("eits.sdk.exit.count"),
      counter("eits.sdk.output.count"),
      last_value("eits.sdk.result.duration_ms"),
      last_value("eits.sdk.result.total_cost_usd"),
      last_value("eits.sdk.result.text_length"),

      # AgentWorker Metrics
      counter("eits.agent.job.received.count"),
      counter("eits.agent.job.started.count"),
      counter("eits.agent.job.queued.count"),
      last_value("eits.agent.job.queued.queue_length"),
      counter("eits.agent.result.saved.count"),
      last_value("eits.agent.result.saved.text_length"),
      counter("eits.agent.sdk.complete.count"),
      counter("eits.agent.sdk.error.count"),

      # CLI Metrics
      counter("eits.cli.spawn.count"),
      counter("eits.cli.exit.count"),
      counter("eits.cli.timeout.count"),

      # VM Metrics
      summary("vm.memory.total", unit: {:byte, :kilobyte}),
      summary("vm.total_run_queue_lengths.total"),

      # LiveView Metrics
      counter("liveview.mount.count"),
      summary("liveview.mount.duration", unit: {:native, :millisecond}),
      counter("liveview.event.count", tags: [:event]),
      summary("liveview.event.duration", unit: {:native, :millisecond}, tags: [:event]),
      last_value("liveview.connections.count"),
      last_value("liveview.channels.count"),
      summary("vm.total_run_queue_lengths.cpu"),
      summary("vm.total_run_queue_lengths.io")
    ]
  end

  defp periodic_measurements do
    [
      # A module, function and arguments to be invoked periodically.
      # This function must call :telemetry.execute/3 and a metric must be added above.
      # {EyeInTheSkyWeb, :count_users, []}
      {EyeInTheSkyWeb.Telemetry, :dispatch_measurements, []}
    ]
  end

  # Single dispatcher guards against hot-reload :undef errors. The telemetry_poller
  # calls this one MFA; if the module is mid-reload the poller logs once (for this
  # function) rather than once per measurement. Individual helpers stay public so
  # they can be called directly in tests.
  def dispatch_measurements do
    mod = __MODULE__

    if function_exported?(mod, :measure_memory, 0), do: measure_memory()
    if function_exported?(mod, :measure_processes, 0), do: measure_processes()
    if function_exported?(mod, :measure_liveview, 0), do: measure_liveview()
  end

  def measure_memory do
    memory_info = :erlang.memory()
    :telemetry.execute([:vm, :memory, :total], %{value: memory_info[:total]})
  end

  def measure_processes do
    process_count = :erlang.system_info(:process_count)
    :telemetry.execute([:vm, :processes], %{count: process_count})
  end

  def measure_liveview do
    # Just emit a simple metric for now to verify telemetry is working
    connection_count = 0
    :telemetry.execute([:liveview, :connections, :count], %{value: connection_count})
    :telemetry.execute([:liveview, :channels, :count], %{value: connection_count})
  end
end
