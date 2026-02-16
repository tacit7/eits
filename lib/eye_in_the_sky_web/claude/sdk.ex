defmodule EyeInTheSkyWeb.Claude.SDK do
  @moduledoc """
  High-level SDK for interacting with Claude Code CLI.

  Provides streaming API that spawns Claude processes and delivers parsed messages
  to the caller. Session management is left to the caller.

  ## Usage

      # Start a new streaming session
      {:ok, ref} = SDK.start("Write hello world in Python", to: self())

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
      {:ok, ref} = SDK.resume(session_id, "Now add error handling", to: self())

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

  # Agent to track running sessions for cancellation
  defmodule Registry do
    use Agent

    def start_link(_) do
      Agent.start_link(fn -> %{} end, name: __MODULE__)
    end

    def register(ref, port) do
      Agent.update(__MODULE__, &Map.put(&1, ref, port))
    end

    def lookup(ref) do
      Agent.get(__MODULE__, &Map.get(&1, ref))
    end

    def unregister(ref) do
      Agent.update(__MODULE__, &Map.delete(&1, ref))
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
  @spec start(String.t(), opts()) :: {:ok, ref()} | {:error, term()}
  def start(prompt, opts \\ []) do
    to = Keyword.fetch!(opts, :to)
    sdk_ref = make_ref()
    meta = %{session_id: opts[:session_id], model: opts[:model]}

    :telemetry.execute([:eits, :sdk, :start], %{system_time: System.system_time()}, meta)
    Logger.info("[telemetry] sdk.start session_id=#{meta.session_id} model=#{meta.model}")

    # Spawn handler first so we can pass its PID to CLI
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

    case cli.spawn_new_session(prompt, cli_opts) do
      {:ok, port, _cli_ref} ->
        Registry.register(sdk_ref, port)
        send(handler_pid, {:start_handling, sdk_ref})
        {:ok, sdk_ref}

      {:error, reason} ->
        :telemetry.execute(
          [:eits, :sdk, :error],
          %{system_time: System.system_time()},
          Map.put(meta, :reason, reason)
        )

        Logger.error(
          "[telemetry] sdk.error session_id=#{meta.session_id} reason=#{inspect(reason)}"
        )

        Process.exit(handler_pid, :kill)
        {:error, reason}
    end
  end

  @doc """
  Resume an existing Claude session.

  Same as `start/2` but resumes a conversation by session_id.

  ## Options

  Required:
    * `:to` - pid to send messages to

  Optional: same as `start/2`

  """
  @spec resume(String.t(), String.t(), opts()) :: {:ok, ref()} | {:error, term()}
  def resume(session_id, prompt, opts \\ []) do
    to = Keyword.fetch!(opts, :to)
    sdk_ref = make_ref()
    meta = %{session_id: session_id, model: opts[:model]}

    :telemetry.execute([:eits, :sdk, :start], %{system_time: System.system_time()}, meta)
    Logger.info("[telemetry] sdk.resume session_id=#{session_id} model=#{meta.model}")

    # Spawn handler first so we can pass its PID to CLI
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

    case cli.resume_session(session_id, prompt, cli_opts) do
      {:ok, port, _cli_ref} ->
        Registry.register(sdk_ref, port)
        send(handler_pid, {:start_handling, sdk_ref})
        {:ok, sdk_ref}

      {:error, reason} ->
        :telemetry.execute(
          [:eits, :sdk, :error],
          %{system_time: System.system_time()},
          Map.put(meta, :reason, reason)
        )

        Logger.error("[telemetry] sdk.error session_id=#{session_id} reason=#{inspect(reason)}")
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

  # Spawn a handler process that will receive CLI messages
  defp spawn_handler_process(sdk_ref, caller_pid) do
    spawn_link(fn ->
      # Wait for start signal with sdk_ref
      receive do
        {:start_handling, ^sdk_ref} ->
          :telemetry.execute(
            [:eits, :sdk, :handler, :ready],
            %{system_time: System.system_time()},
            %{}
          )

          handle_messages(sdk_ref, caller_pid, nil)
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

          {:complete, sid} ->
            final_session_id = sid || session_id
            send(caller_pid, {:claude_complete, sdk_ref, final_session_id})

            :telemetry.execute([:eits, :sdk, :complete], %{system_time: System.system_time()}, %{
              session_id: final_session_id
            })

            Logger.info("[telemetry] sdk.complete session_id=#{final_session_id}")
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
    if Application.get_env(:eye_in_the_sky_web, :log_claude_raw, false) do
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
