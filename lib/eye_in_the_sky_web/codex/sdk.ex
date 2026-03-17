defmodule EyeInTheSkyWeb.Codex.SDK do
  @moduledoc """
  High-level SDK for interacting with OpenAI Codex CLI.

  Provides the same streaming API as Claude.SDK, using Codex.CLI and Codex.Parser.
  Delivers parsed messages to the caller using the same message protocol:

    * `{:claude_message, ref, %Message{}}` - each parsed event
    * `{:claude_complete, ref, session_id}` - conversation completed
    * `{:claude_error, ref, reason}` - error occurred

  ## Key Differences from Claude.SDK

  - Codex emits complete items (no streaming deltas)
  - The handler accumulates agent_message texts during a turn
  - On turn.completed, builds a synthetic Message.result with accumulated text
  - Reuses Claude.SDK.Registry for ref->port tracking
  """

  alias EyeInTheSkyWeb.Claude.{Message, Utils}
  alias EyeInTheSkyWeb.Claude.SDK.Registry
  alias EyeInTheSkyWeb.Codex.Parser

  require Logger

  @type ref :: reference()
  @type opts :: keyword()
  @terminal_exit_wait_ms 2_000

  @doc """
  Start a new Codex session with streaming output.

  ## Options

  Required:
    * `:to` - pid to send messages to

  Optional:
    * `:model` - model name (e.g., "o3-mini", "o4-mini")
    * `:project_path` - working directory for Codex
    * `:full_auto` - autonomous mode (default: true)
  """
  @spec start(String.t(), opts()) :: {:ok, ref(), pid()} | {:error, term()}
  def start(prompt, opts \\ []) do
    to = Keyword.fetch!(opts, :to)
    sdk_ref = make_ref()
    meta = %{session_id: opts[:session_id], model: opts[:model]}

    :telemetry.execute([:eits, :codex, :sdk, :start], %{system_time: System.system_time()}, meta)
    Logger.info("[telemetry] codex.sdk.start session_id=#{meta.session_id} model=#{meta.model}")

    handler_pid = spawn_handler_process(sdk_ref, to, opts[:session_id])
    cli = Keyword.get(opts, :cli_module) || Utils.codex_cli_module()

    cli_opts =
      opts
      |> Keyword.put(:caller, handler_pid)
      |> Keyword.delete(:to)
      |> Keyword.delete(:cli_module)

    case cli.spawn_new_session(prompt, cli_opts) do
      {:ok, port, _cli_ref} ->
        Registry.register(sdk_ref, port)
        send(handler_pid, {:start_handling, sdk_ref})
        {:ok, sdk_ref, handler_pid}

      {:error, reason} ->
        :telemetry.execute(
          [:eits, :codex, :sdk, :error],
          %{system_time: System.system_time()},
          Map.put(meta, :reason, reason)
        )

        Logger.error(
          "[telemetry] codex.sdk.error session_id=#{meta.session_id} reason=#{inspect(reason)}"
        )

        Process.exit(handler_pid, :kill)
        {:error, reason}
    end
  end

  @doc """
  Resume an existing Codex session.

  Same as `start/2` but resumes a conversation by thread/session ID.
  """
  @spec resume(String.t(), String.t(), opts()) :: {:ok, ref(), pid()} | {:error, term()}
  def resume(session_id, prompt, opts \\ []) do
    to = Keyword.fetch!(opts, :to)
    sdk_ref = make_ref()
    meta = %{session_id: session_id, model: opts[:model]}

    :telemetry.execute([:eits, :codex, :sdk, :start], %{system_time: System.system_time()}, meta)

    Logger.info("[telemetry] codex.sdk.resume session_id=#{session_id} model=#{meta.model}")

    handler_pid = spawn_handler_process(sdk_ref, to, opts[:session_id])
    cli = Keyword.get(opts, :cli_module) || Utils.codex_cli_module()

    cli_opts =
      opts
      |> Keyword.put(:caller, handler_pid)
      |> Keyword.delete(:to)
      |> Keyword.delete(:cli_module)

    case cli.resume_session(session_id, prompt, cli_opts) do
      {:ok, port, _cli_ref} ->
        Registry.register(sdk_ref, port)
        send(handler_pid, {:start_handling, sdk_ref})
        {:ok, sdk_ref, handler_pid}

      {:error, reason} ->
        :telemetry.execute(
          [:eits, :codex, :sdk, :error],
          %{system_time: System.system_time()},
          Map.put(meta, :reason, reason)
        )

        Logger.error(
          "[telemetry] codex.sdk.error session_id=#{session_id} reason=#{inspect(reason)}"
        )

        Process.exit(handler_pid, :kill)
        {:error, reason}
    end
  end

  @doc """
  Cancel a running Codex session.
  """
  @spec cancel(ref()) :: :ok | {:error, :not_found}
  def cancel(ref) do
    cli = Utils.codex_cli_module()

    case Registry.lookup(ref) do
      nil ->
        {:error, :not_found}

      port when is_port(port) ->
        cli.cancel(port)
        :ok

      pid when is_pid(pid) ->
        send(pid, :cancel)
        :ok
    end
  end

  # ---------------------------------------------------------------------------
  # Handler process
  # ---------------------------------------------------------------------------

  defp spawn_handler_process(sdk_ref, caller_pid, fallback_session_id) do
    spawn(fn ->
      Process.monitor(caller_pid)

      receive do
        {:start_handling, ^sdk_ref} ->
          :telemetry.execute(
            [:eits, :codex, :sdk, :handler, :ready],
            %{system_time: System.system_time()},
            %{}
          )

          # accumulated_text collects agent_message content during a turn
          handle_messages(
            sdk_ref,
            caller_pid,
            _session_id = nil,
            _accumulated_text = "",
            fallback_session_id
          )

        {:DOWN, _ref, :process, ^caller_pid, _reason} ->
          stop_and_unregister(sdk_ref)
      after
        5_000 ->
          send(caller_pid, {:claude_error, sdk_ref, :handler_timeout})
      end
    end)
  end

  # Message handler loop - receives {:claude_output, ref, line} from CLI
  defp handle_messages(
         sdk_ref,
         caller_pid,
         session_id,
         accumulated_text,
         fallback_session_id
       ) do
    receive do
      {:claude_output, _cli_ref, line} ->
        maybe_log_raw_line(session_id, line)

        :telemetry.execute([:eits, :codex, :sdk, :output], %{byte_size: byte_size(line)}, %{
          session_id: session_id
        })

        case Parser.parse_stream_line(line) do
          {:ok, %Message{type: :text} = message} ->
            # Accumulate agent_message text for the result
            new_text = accumulated_text <> (message.content || "")
            send(caller_pid, {:claude_message, sdk_ref, message})
            handle_messages(sdk_ref, caller_pid, session_id, new_text, fallback_session_id)

          {:ok, message} ->
            send(caller_pid, {:claude_message, sdk_ref, message})

            handle_messages(
              sdk_ref,
              caller_pid,
              session_id,
              accumulated_text,
              fallback_session_id
            )

          {:session_id, sid} ->
            handle_messages(sdk_ref, caller_pid, sid, accumulated_text, fallback_session_id)

          {:result, data} ->
            # Turn completed - build synthetic result message with accumulated text
            final_session_id = data[:session_id] || session_id
            result_text = if accumulated_text != "", do: accumulated_text, else: nil

            metadata = %{
              session_id: final_session_id,
              usage: data[:usage],
              input_tokens: data[:input_tokens],
              output_tokens: data[:output_tokens]
            }

            :telemetry.execute(
              [:eits, :codex, :sdk, :result],
              %{
                text_length: if(result_text, do: String.length(result_text), else: 0),
                input_tokens: data[:input_tokens] || 0,
                output_tokens: data[:output_tokens] || 0
              },
              %{session_id: final_session_id}
            )

            Logger.info(
              "[telemetry] codex.sdk.result session_id=#{final_session_id} " <>
                "text_length=#{if result_text, do: String.length(result_text), else: 0}"
            )

            if result_text do
              msg = Message.result(result_text, metadata)
              send(caller_pid, {:claude_message, sdk_ref, msg})
            end

            send(caller_pid, {:claude_complete, sdk_ref, final_session_id})

            :telemetry.execute(
              [:eits, :codex, :sdk, :complete],
              %{system_time: System.system_time()},
              %{session_id: final_session_id}
            )

            Logger.info("[telemetry] codex.sdk.complete session_id=#{final_session_id}")

            finalize_after_terminal_event(sdk_ref, final_session_id)
            :ok

          {:error, reason} ->
            send(caller_pid, {:claude_error, sdk_ref, reason})

            :telemetry.execute(
              [:eits, :codex, :sdk, :error],
              %{system_time: System.system_time()},
              %{session_id: session_id, reason: reason}
            )

            Logger.error(
              "[telemetry] codex.sdk.error session_id=#{session_id} reason=#{inspect(reason)}"
            )

            stop_and_unregister(sdk_ref)
            :ok

          :skip ->
            handle_messages(
              sdk_ref,
              caller_pid,
              session_id,
              accumulated_text,
              fallback_session_id
            )
        end

      {:claude_exit, _cli_ref, 0} ->
        # Normal exit without turn.completed - send complete
        # Use fallback (execution agent uuid) if thread.started wasn't observed
        final_session_id = session_id || fallback_session_id || ""
        send(caller_pid, {:claude_complete, sdk_ref, final_session_id})
        log_sdk_exit(final_session_id, 0)
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

      {:DOWN, _ref, :process, ^caller_pid, _reason} ->
        stop_and_unregister(sdk_ref)
        :ok
    end
  end

  defp maybe_log_raw_line(session_id, line) do
    if EyeInTheSkyWeb.Settings.get_boolean("log_codex_raw") do
      label = session_id || "unknown"
      Logger.info("[codex.raw] session_id=#{label} line=#{inspect(line, limit: 1_000)}")
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
          "[telemetry] codex.sdk.force_close session_id=#{session_id} reason=no_exit_after_terminal_event"
        )

        stop_and_unregister(sdk_ref)
    end
  end

  defp log_sdk_exit(session_id, status) do
    exit_code = if is_integer(status), do: status, else: -1

    :telemetry.execute([:eits, :codex, :sdk, :exit], %{exit_code: exit_code}, %{
      session_id: session_id,
      status: status
    })

    if status == 0 do
      Logger.info("[telemetry] codex.sdk.exit session_id=#{session_id} exit_code=0")
    else
      Logger.error(
        "[telemetry] codex.sdk.exit session_id=#{session_id} exit_code=#{exit_code} status=#{inspect(status)}"
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
