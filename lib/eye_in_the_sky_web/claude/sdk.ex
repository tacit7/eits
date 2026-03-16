defmodule EyeInTheSkyWeb.Claude.SDK do
  @moduledoc """
  High-level SDK for interacting with Claude Code CLI.

  Provides streaming API that spawns Claude processes and delivers parsed messages
  to the caller. Session management is left to the caller.

  ## Usage

      # Start a new streaming session
      {:ok, ref, _handler} = SDK.start("Write hello world in Python", to: self())

      # Handle messages
      receive do
        {:claude_message, ^ref, %Message{type: :text, content: text}} ->
          IO.write(text)

        {:claude_complete, ^ref, session_id} ->
          IO.puts("\\nDone: \#{session_id}")

        {:claude_error, ^ref, reason} ->
          IO.puts("Error: \#{inspect(reason)}")
      end

      # Resume a conversation
      {:ok, ref, _handler} = SDK.resume(session_id, "Now add error handling", to: self())

  ## Messages

  The SDK sends these messages to the caller process:

    * `{:claude_message, ref, %Message{}}` - each parsed event (text deltas, tool uses, etc)
    * `{:claude_complete, ref, session_id}` - conversation completed successfully
    * `{:claude_error, ref, reason}` - error occurred during processing

  """

  alias EyeInTheSkyWeb.Claude.{CLI, Message, Parser, Utils}
  require Logger

  @type ref :: reference()
  @type opts :: keyword()
  @terminal_exit_wait_ms 2_000

  # ETS-based registry for tracking running sessions (lock-free concurrent reads)
  defmodule Registry do
    use GenServer

    @table __MODULE__

    def start_link(_) do
      GenServer.start_link(__MODULE__, [], name: __MODULE__)
    end

    @impl true
    def init(_) do
      :ets.new(@table, [:named_table, :public, :set])
      {:ok, nil}
    end

    def register(ref, port) do
      :ets.insert(@table, {ref, port})
      :ok
    end

    def lookup(ref) do
      case :ets.lookup(@table, ref) do
        [{^ref, port}] -> port
        [] -> nil
      end
    end

    def unregister(ref) do
      :ets.delete(@table, ref)
      :ok
    end
  end

  @doc """
  Start a new Claude session with streaming output.

  ## Options

  Required:
    * `:to` - pid to send messages to

  Optional (passed to CLI):
    * `:model` - model name (e.g., "sonnet", "haiku", "opus")
    * `:allowedTools` - comma-separated tool names to auto-approve
    * `:max_turns` - maximum conversation turns
    * `:permission_mode` - permission mode (see CLI module)
    * `:project_path` - working directory for Claude
    * All other CLI options supported by CLI.build_args/1

  ## Returns

    * `{:ok, ref}` - unique reference for this session
    * `{:error, reason}` - failed to start

  """
  @spec start(String.t(), opts()) :: {:ok, ref(), pid()} | {:error, term()}
  def start(prompt, opts \\ []) do
    run_session(:start, prompt, nil, opts)
  end

  @doc """
  Resume an existing Claude session.

  Same as `start/2` but resumes a conversation by session_id.

  ## Options

  Required:
    * `:to` - pid to send messages to

  Optional: same as `start/2`

  """
  @spec resume(String.t(), String.t(), opts()) :: {:ok, ref(), pid()} | {:error, term()}
  def resume(session_id, prompt, opts \\ []) do
    run_session(:resume, prompt, session_id, opts)
  end

  defp run_session(mode, prompt, session_id, opts) do
    to = Keyword.fetch!(opts, :to)
    sdk_ref = make_ref()
    meta_session_id = if mode == :resume, do: session_id, else: opts[:session_id]
    meta = %{session_id: meta_session_id, model: opts[:model]}

    :telemetry.execute([:eits, :sdk, :start], %{system_time: System.system_time()}, meta)
    Logger.info("[telemetry] sdk.#{mode} session_id=#{meta_session_id} model=#{meta.model}")

    handler_pid = spawn_handler_process(sdk_ref, to)
    cli = Keyword.get(opts, :cli_module) || Utils.cli_module()

    cli_opts =
      opts
      |> Keyword.put(:output_format, "stream-json")
      |> Keyword.put(:verbose, true)
      |> Keyword.put(:include_partial_messages, true)
      |> Keyword.put(:caller, handler_pid)
      |> Keyword.delete(:to)
      |> Keyword.delete(:cli_module)

    cli_result =
      case mode do
        :start -> cli.spawn_new_session(prompt, cli_opts)
        :resume -> cli.resume_session(session_id, prompt, cli_opts)
      end

    case cli_result do
      {:ok, port, _cli_ref} ->
        Registry.register(sdk_ref, port)
        send(handler_pid, {:start_handling, sdk_ref})
        {:ok, sdk_ref, handler_pid}

      {:error, reason} ->
        :telemetry.execute(
          [:eits, :sdk, :error],
          %{system_time: System.system_time()},
          Map.put(meta, :reason, reason)
        )

        Logger.error(
          "[telemetry] sdk.error session_id=#{meta_session_id} reason=#{inspect(reason)}"
        )

        Process.exit(handler_pid, :kill)
        {:error, reason}
    end
  end

  @doc """
  Cancel a running Claude session.

  Closes the port and stops message delivery. The handler will send
  `{:claude_error, ref, :cancelled}` to the caller.
  """
  @spec cancel(ref()) :: :ok | {:error, :not_found}
  def cancel(ref) do
    case Registry.lookup(ref) do
      nil ->
        {:error, :not_found}

      port when is_port(port) ->
        CLI.cancel(port)
        :ok

      pid when is_pid(pid) ->
        # Mock ports in tests are pids
        send(pid, :cancel)
        :ok
    end
  end

  # Spawn a monitored handler process that will receive CLI messages.
  # Uses spawn (not spawn_link) so handler crashes don't kill the caller.
  # Handler monitors caller so it exits cleanly if caller goes down.
  defp spawn_handler_process(sdk_ref, caller_pid) do
    spawn(fn ->
      Process.monitor(caller_pid)

      receive do
        {:start_handling, ^sdk_ref} ->
          :telemetry.execute(
            [:eits, :sdk, :handler, :ready],
            %{system_time: System.system_time()},
            %{}
          )

          handle_messages(sdk_ref, caller_pid, nil)

        {:DOWN, _ref, :process, ^caller_pid, _reason} ->
          stop_and_unregister(sdk_ref)
      after
        5_000 ->
          send(caller_pid, {:claude_error, sdk_ref, :handler_timeout})
      end
    end)
  end

  # Message handler loop - receives {:claude_output, ref, line} from CLI
  defp handle_messages(sdk_ref, caller_pid, session_id) do
    receive do
      {:claude_output, _cli_ref, line} ->
        maybe_log_raw_line(session_id, line)

        :telemetry.execute([:eits, :sdk, :output], %{byte_size: byte_size(line)}, %{
          session_id: session_id
        })

        case Parser.parse_stream_line(line) do
          {:ok, message} ->
            send(caller_pid, {:claude_message, sdk_ref, message})
            handle_messages(sdk_ref, caller_pid, session_id)

          {:session_id, sid} ->
            handle_messages(sdk_ref, caller_pid, sid)

          {:result, data} ->
            result_text = data[:result]
            metadata = Map.drop(data, [:result])
            text_len = if(result_text, do: String.length(result_text), else: 0)
            duration = metadata[:duration_ms] || 0
            cost = metadata[:total_cost_usd] || 0
            is_error = metadata[:is_error] == true

            :telemetry.execute(
              [:eits, :sdk, :result],
              %{
                text_length: text_len,
                duration_ms: duration,
                total_cost_usd: cost
              },
              %{session_id: data[:session_id] || session_id}
            )

            Logger.info(
              "[telemetry] sdk.result session_id=#{data[:session_id] || session_id} text_length=#{text_len} duration_ms=#{duration} cost=$#{cost} is_error=#{is_error}"
            )

            if result_text do
              msg = Message.result(result_text, metadata)
              send(caller_pid, {:claude_message, sdk_ref, msg})
            end

            final_session_id = data[:session_id] || session_id

            if is_error do
              reason =
                {:claude_result_error,
                 %{
                   session_id: final_session_id,
                   errors: metadata[:errors],
                   result: result_text
                 }}

              send(caller_pid, {:claude_error, sdk_ref, reason})

              :telemetry.execute([:eits, :sdk, :error], %{system_time: System.system_time()}, %{
                session_id: final_session_id,
                reason: reason
              })

              Logger.error(
                "[telemetry] sdk.error session_id=#{final_session_id} reason=#{inspect(reason)}"
              )
            else
              send(caller_pid, {:claude_complete, sdk_ref, final_session_id})

              :telemetry.execute(
                [:eits, :sdk, :complete],
                %{system_time: System.system_time()},
                %{
                  session_id: final_session_id
                }
              )

              Logger.info("[telemetry] sdk.complete session_id=#{final_session_id}")
            end

            finalize_after_terminal_event(sdk_ref, final_session_id)
            :ok

          {:error, reason} ->
            send(caller_pid, {:claude_error, sdk_ref, reason})

            :telemetry.execute([:eits, :sdk, :error], %{system_time: System.system_time()}, %{
              session_id: session_id,
              reason: reason
            })

            Logger.error(
              "[telemetry] sdk.error session_id=#{session_id} reason=#{inspect(reason)}"
            )

            stop_and_unregister(sdk_ref)
            :ok

          :tool_block_stop ->
            send(caller_pid, {:tool_block_stop, sdk_ref})
            handle_messages(sdk_ref, caller_pid, session_id)

          :skip ->
            handle_messages(sdk_ref, caller_pid, session_id)
        end

      {:claude_exit, _cli_ref, 0} ->
        # Normal exit - if we didn't get a complete message, send one now
        send(caller_pid, {:claude_complete, sdk_ref, session_id})
        log_sdk_exit(session_id, 0)
        stop_and_unregister(sdk_ref)
        :ok

      {:claude_exit, _cli_ref, status} ->
        log_sdk_exit(session_id, status)

        reason =
          case status do
            :timeout -> :timeout
            code when is_integer(code) -> {:exit_code, code}
            other -> other
          end

        send(caller_pid, {:claude_error, sdk_ref, reason})
        stop_and_unregister(sdk_ref)
        :ok
    end
  end

  defp maybe_log_raw_line(session_id, line) do
    if EyeInTheSkyWeb.Settings.get_boolean("log_claude_raw") do
      label = session_id || "unknown"
      Logger.info("[claude.raw] session_id=#{label} line=#{inspect(line, limit: 1_000)}")
    end
  end

  defp finalize_after_terminal_event(sdk_ref, session_id) do
    receive do
      {:claude_output, _cli_ref, line} ->
        maybe_log_raw_line(session_id, line)
        finalize_after_terminal_event(sdk_ref, session_id)

      {:claude_exit, _cli_ref, status} ->
        log_sdk_exit(session_id, status)
        stop_and_unregister(sdk_ref)
    after
      @terminal_exit_wait_ms ->
        Logger.warning(
          "[telemetry] sdk.force_close session_id=#{session_id} reason=no_exit_after_terminal_event"
        )

        stop_and_unregister(sdk_ref)
    end
  end

  defp log_sdk_exit(session_id, status) do
    exit_code = if is_integer(status), do: status, else: -1

    :telemetry.execute([:eits, :sdk, :exit], %{exit_code: exit_code}, %{
      session_id: session_id,
      status: status
    })

    if status == 0 do
      Logger.info("[telemetry] sdk.exit session_id=#{session_id} exit_code=0")
    else
      Logger.error(
        "[telemetry] sdk.exit session_id=#{session_id} exit_code=#{exit_code} status=#{inspect(status)}"
      )
    end
  end

  defp stop_and_unregister(sdk_ref) do
    case Registry.lookup(sdk_ref) do
      nil -> :ok
      port_or_pid -> Utils.close_port_safely(port_or_pid)
    end

    Registry.unregister(sdk_ref)
    :ok
  end
end
