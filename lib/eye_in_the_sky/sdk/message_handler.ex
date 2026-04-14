defmodule EyeInTheSky.SDK.MessageHandler do
  @moduledoc """
  Behaviour and shared receive-loop skeleton for SDK message handlers.

  Both `EyeInTheSky.Claude.SDK` and `EyeInTheSky.Codex.SDK` run
  structurally identical receive loops that differ only in how they handle
  parsed messages and terminal results. This module captures the shared
  skeleton.

  ## State

  The `state` map must carry at minimum:

    * `:sdk_ref`    — unique reference for this SDK session
    * `:caller_pid` — process to deliver messages to
    * `:session_id` — current session ID (may be nil; updated as stream flows)

  Implementations may carry additional keys (e.g., `:accumulated_text` and
  `:fallback_session_id` for the Codex SDK).

  ## Behaviour Callbacks

  Implementing modules must define:

    * `handle_message/2` — called for each successfully parsed, non-result line
    * `handle_result/2`  — called when the terminal result message arrives

  Two optional callbacks have default implementations provided via `use`:

    * `on_session_id/2`          — called when the parser emits `{:session_id, sid}`
    * `resolve_exit_session_id/1` — returns the session ID to use on clean exit

  ## Usage

      defmodule MySDK do
        use EyeInTheSky.SDK.MessageHandler

        @impl true
        def handle_message(msg, state) do
          send(state.caller_pid, {:my_message, state.sdk_ref, msg})
          {:continue, state}
        end

        @impl true
        def handle_result(data, state) do
          send(state.caller_pid, {:my_complete, state.sdk_ref, data[:session_id]})
          MessageHandler.finalize_after_terminal_event(state.sdk_ref, data[:session_id], [])
        end
      end

      # In the handler process:
      MessageHandler.run_loop(MySDK, state, parser: MyParser, telemetry_prefix: [:my, :sdk])
  """

  alias EyeInTheSky.Claude.{Message, Utils}
  alias EyeInTheSky.Claude.SDK.Registry

  require Logger

  @type state :: %{
          required(:sdk_ref) => reference(),
          required(:caller_pid) => pid(),
          optional(:session_id) => String.t() | nil,
          optional(atom()) => any()
        }

  @terminal_exit_wait_ms 2_000

  # ---------------------------------------------------------------------------
  # Behaviour definition
  # ---------------------------------------------------------------------------

  @doc """
  Called for each successfully parsed non-result message.

  Return `{:continue, new_state}` to keep looping (updating state if needed),
  or `:stop` to halt the handler immediately.
  """
  @callback handle_message(msg :: Message.t(), state :: state()) ::
              {:continue, state()} | :stop

  @doc """
  Called when a terminal `{:result, data}` line arrives from the parser.

  The callback is responsible for:

    1. Emitting `:claude_complete` or `:claude_error` to `state.caller_pid`
    2. Calling `MessageHandler.finalize_after_terminal_event/3`

  Returns `:ok`.
  """
  @callback handle_result(data :: map(), state :: state()) :: :ok

  @doc """
  Called when the parser emits `{:session_id, sid}`.

  Default implementation updates `:session_id` in state and returns the new
  state. Implementing modules may override to send additional notifications.
  """
  @callback on_session_id(sid :: String.t(), state :: state()) :: state()

  @doc """
  Returns the session ID to use when the process exits cleanly (exit code 0)
  without a preceding `{:result, ...}` line.

  Default implementation returns `state[:session_id]`.
  Codex overrides this to also check `:fallback_session_id`.
  """
  @callback resolve_exit_session_id(state :: state()) :: String.t() | nil

  @optional_callbacks [on_session_id: 2, resolve_exit_session_id: 1]

  # ---------------------------------------------------------------------------
  # __using__ — inject default implementations
  # ---------------------------------------------------------------------------

  defmacro __using__(_opts) do
    quote do
      @behaviour EyeInTheSky.SDK.MessageHandler

      @impl EyeInTheSky.SDK.MessageHandler
      def on_session_id(sid, state), do: %{state | session_id: sid}

      @impl EyeInTheSky.SDK.MessageHandler
      def resolve_exit_session_id(state), do: state[:session_id]

      defoverridable on_session_id: 2, resolve_exit_session_id: 1
    end
  end

  # ---------------------------------------------------------------------------
  # Shared receive loop
  # ---------------------------------------------------------------------------

  @doc """
  Runs the shared SDK message receive loop, dispatching to `module` callbacks.

  ## Options

    * `:parser`           — module with `parse_stream_line/1` (required)
    * `:telemetry_prefix` — list of atoms for telemetry events (default: `[:eits, :sdk]`)
    * `:log_raw_key`      — settings key for raw-line logging toggle (default: `"log_claude_raw"`)
    * `:log_raw_prefix`   — log label prefix (default: `"claude.raw"`)
  """
  @spec run_loop(module(), state(), keyword()) :: :ok
  def run_loop(module, state, opts \\ []) do
    %{sdk_ref: sdk_ref, caller_pid: caller_pid} = state
    session_id = Map.get(state, :session_id)

    parser = Keyword.fetch!(opts, :parser)
    tel_prefix = Keyword.get(opts, :telemetry_prefix, [:eits, :sdk])
    log_raw_key = Keyword.get(opts, :log_raw_key, "log_claude_raw")
    log_raw_prefix = Keyword.get(opts, :log_raw_prefix, "claude.raw")
    forward_raw_lines = Keyword.get(opts, :forward_raw_lines, false)

    receive do
      {:claude_output, _cli_ref, line} ->
        maybe_log_raw_line(session_id, line, log_raw_key, log_raw_prefix)
        if forward_raw_lines do
          broadcast_id = Map.get(state, :eits_session_id) || session_id
          EyeInTheSky.Events.broadcast_codex_raw(broadcast_id, line)
        end

        :telemetry.execute(tel_prefix ++ [:output], %{byte_size: byte_size(line)}, %{
          session_id: session_id
        })

        case parser.parse_stream_line(line) do
          {:ok, message} ->
            case module.handle_message(message, state) do
              {:continue, new_state} -> run_loop(module, new_state, opts)
              :stop -> stop_and_unregister(sdk_ref)
            end

          {:session_id, sid} ->
            new_state = module.on_session_id(sid, state)
            run_loop(module, new_state, opts)

          {:result, data} ->
            module.handle_result(data, state)

          {:error, reason} ->
            send(caller_pid, {:claude_error, sdk_ref, reason})

            :telemetry.execute(
              tel_prefix ++ [:error],
              %{system_time: System.system_time()},
              %{session_id: session_id, reason: reason}
            )

            Logger.error(
              "[telemetry] #{tel_label(tel_prefix)}.error session_id=#{session_id} reason=#{inspect(reason)}"
            )

            stop_and_unregister(sdk_ref)
            :ok

          :tool_block_stop ->
            send(caller_pid, {:tool_block_stop, sdk_ref})
            run_loop(module, state, opts)

          :skip ->
            run_loop(module, state, opts)
        end

      {:claude_exit, _cli_ref, 0} ->
        final_session_id = module.resolve_exit_session_id(state)
        send(caller_pid, {:claude_complete, sdk_ref, final_session_id})
        log_sdk_exit(final_session_id, 0, tel_prefix)
        stop_and_unregister(sdk_ref)
        :ok

      {:claude_exit, _cli_ref, status} ->
        log_sdk_exit(session_id, status, tel_prefix)

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

  # ---------------------------------------------------------------------------
  # Shared helpers (public so implementing modules can call them)
  # ---------------------------------------------------------------------------

  @doc """
  Drains remaining `:claude_output` lines after a terminal event, then waits
  for the process exit message before unregistering the SDK ref.

  `opts` supports `:log_raw_key` and `:log_raw_prefix` (same as `run_loop/3`).
  """
  @spec finalize_after_terminal_event(reference(), String.t() | nil, keyword()) :: :ok
  def finalize_after_terminal_event(sdk_ref, session_id, opts \\ []) do
    log_raw_key = Keyword.get(opts, :log_raw_key, "log_claude_raw")
    log_raw_prefix = Keyword.get(opts, :log_raw_prefix, "claude.raw")
    tel_prefix = Keyword.get(opts, :telemetry_prefix, [:eits, :sdk])

    receive do
      {:claude_output, _cli_ref, line} ->
        maybe_log_raw_line(session_id, line, log_raw_key, log_raw_prefix)
        finalize_after_terminal_event(sdk_ref, session_id, opts)

      {:claude_exit, _cli_ref, status} ->
        log_sdk_exit(session_id, status, tel_prefix)
        stop_and_unregister(sdk_ref)
    after
      @terminal_exit_wait_ms ->
        Logger.warning(
          "[telemetry] #{tel_label(tel_prefix)}.force_close session_id=#{session_id} reason=no_exit_after_terminal_event"
        )

        stop_and_unregister(sdk_ref)
    end
  end

  @doc """
  Emits telemetry and logs for a process exit.
  """
  @spec log_sdk_exit(String.t() | nil, term(), list()) :: :ok
  def log_sdk_exit(session_id, status, tel_prefix \\ [:eits, :sdk]) do
    exit_code = if is_integer(status), do: status, else: -1

    :telemetry.execute(tel_prefix ++ [:exit], %{exit_code: exit_code}, %{
      session_id: session_id,
      status: status
    })

    if status == 0 do
      Logger.info("[telemetry] #{tel_label(tel_prefix)}.exit session_id=#{session_id} exit_code=0")
    else
      Logger.error(
        "[telemetry] #{tel_label(tel_prefix)}.exit session_id=#{session_id} exit_code=#{exit_code} status=#{inspect(status)}"
      )
    end
  end

  @doc """
  Closes the port/pid and removes the SDK ref from the registry.
  """
  @spec stop_and_unregister(reference()) :: :ok
  def stop_and_unregister(sdk_ref) do
    case Registry.lookup(sdk_ref) do
      nil -> :ok
      port_or_pid -> Utils.close_port_safely(port_or_pid)
    end

    Registry.unregister(sdk_ref)
    :ok
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp maybe_log_raw_line(session_id, line, log_raw_key, log_raw_prefix) do
    if EyeInTheSky.Settings.get_boolean(log_raw_key) do
      label = session_id || "unknown"
      Logger.info("[#{log_raw_prefix}] session_id=#{label} line=#{inspect(line, limit: 1_000)}")
    end
  end

  # Converts a telemetry prefix list to a dot-joined string for log messages.
  # e.g. [:eits, :codex, :sdk] → "codex.sdk"  (drops the leading :eits)
  defp tel_label(prefix) do
    prefix
    |> Enum.drop(1)
    |> Enum.map_join(".", &to_string/1)
  end
end
