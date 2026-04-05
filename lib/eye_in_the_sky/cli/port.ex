defmodule EyeInTheSky.CLI.Port do
  @moduledoc """
  Shared port-handling utilities for CLI subprocess spawners.

  Used by `EyeInTheSky.Claude.CLI` and `EyeInTheSky.Codex.CLI` to share
  the identical logic for:

    * Port output buffering and line splitting (`handle_port_output/6`)
    * Binary path caching via `:persistent_term` (`find_binary/2`, `clear_binary_cache/1`)
    * Standard path search (`find_in_standard_paths/1`)
    * Environment variable helpers (`maybe_add_env/3`)

  Wire format (`:claude_output` / `:claude_exit` tags) is unchanged — callers
  rely on these atoms and they must not be renamed.
  """

  require Logger

  @max_buffer_bytes_default nil

  # ---------------------------------------------------------------------------
  # Port output handler
  # ---------------------------------------------------------------------------

  @doc """
  Loops on port messages, buffers partial lines, and forwards complete lines
  to `caller` as `{:claude_output, session_ref, line}`.

  Sends `{:claude_exit, session_ref, exit_code | :timeout}` on termination.

  ## Options

    * `:telemetry_prefix` - list of atoms prepended to `:exit` / `:timeout`
      telemetry events. Defaults to `[:eits, :cli]`.
    * `:log_prefix` - string used in log messages. Defaults to `"CLI"`.
    * `:max_buffer_bytes` - integer byte limit for the line buffer. When
      exceeded the buffer is flushed to prevent memory growth. `nil` disables
      the guard (default).
  """
  @spec handle_port_output(port(), reference(), pid(), binary(), pos_integer() | :infinity, keyword()) :: :ok
  def handle_port_output(port, session_ref, caller, buffer, idle_timeout_ms, opts \\ []) do
    telemetry_prefix = Keyword.get(opts, :telemetry_prefix, [:eits, :cli])
    log_prefix = Keyword.get(opts, :log_prefix, "CLI")
    max_buffer_bytes = Keyword.get(opts, :max_buffer_bytes, @max_buffer_bytes_default)

    receive do
      {^port, {:data, data}} ->
        new_buffer = buffer <> data

        new_buffer =
          if max_buffer_bytes && byte_size(new_buffer) > max_buffer_bytes do
            Logger.warning(
              "[#{log_prefix}] port buffer exceeded #{max_buffer_bytes} bytes, flushing"
            )

            ""
          else
            new_buffer
          end

        lines = String.split(new_buffer, "\n")

        {complete_lines, remaining} =
          case List.pop_at(lines, -1) do
            {last, rest} ->
              if String.ends_with?(data, "\n"),
                do: {lines, ""},
                else: {rest, last || ""}
          end

        Enum.each(complete_lines, fn line ->
          unless line == "" do
            send(caller, {:claude_output, session_ref, line})
          end
        end)

        handle_port_output(port, session_ref, caller, remaining, idle_timeout_ms, opts)

      {^port, {:exit_status, status}} ->
        unless buffer == "" do
          send(caller, {:claude_output, session_ref, buffer})
        end

        Logger.info("[#{log_prefix}] Process exited with status #{status}")

        :telemetry.execute(telemetry_prefix ++ [:exit], %{exit_code: status}, %{})

        send(caller, {:claude_exit, session_ref, status})
        :ok
    after
      idle_timeout_ms ->
        Logger.warning(
          "[#{log_prefix}] No output after #{div(idle_timeout_ms, 60_000)} minutes, timing out"
        )

        :telemetry.execute(
          telemetry_prefix ++ [:timeout],
          %{system_time: System.system_time()},
          %{timeout_ms: idle_timeout_ms}
        )

        Elixir.Port.close(port)
        send(caller, {:claude_exit, session_ref, :timeout})
        :ok
    end
  end

  # ---------------------------------------------------------------------------
  # Binary locator (cached via :persistent_term)
  # ---------------------------------------------------------------------------

  @doc """
  Looks up a cached binary path from `:persistent_term`, or calls `finder_fun`
  to locate it and caches the result.

  `finder_fun` must return `{:ok, path}` or `{:error, reason}`.
  """
  @spec find_binary(term(), (-> {:ok, String.t()} | {:error, term()})) ::
          {:ok, String.t()} | {:error, term()}
  def find_binary(persistent_term_key, finder_fun) do
    case :persistent_term.get(persistent_term_key, :not_cached) do
      :not_cached ->
        case finder_fun.() do
          {:ok, path} = ok ->
            :persistent_term.put(persistent_term_key, path)
            ok

          error ->
            error
        end

      cached_path ->
        if File.exists?(cached_path) do
          {:ok, cached_path}
        else
          :persistent_term.erase(persistent_term_key)
          find_binary(persistent_term_key, finder_fun)
        end
    end
  end

  @doc """
  Erases the cached binary path for the given key. Useful in tests.
  """
  @spec clear_binary_cache(term()) :: :ok
  def clear_binary_cache(persistent_term_key) do
    :persistent_term.erase(persistent_term_key)
    :ok
  rescue
    ArgumentError -> :ok
  end

  @doc """
  Returns the first path in `standard_paths` that exists on disk, or `nil`.
  """
  @spec find_in_standard_paths([String.t()]) :: String.t() | nil
  def find_in_standard_paths(standard_paths) do
    Enum.find(standard_paths, &File.exists?/1)
  end

  # ---------------------------------------------------------------------------
  # Idle timeout resolution
  # ---------------------------------------------------------------------------

  @doc """
  Resolves the effective idle timeout from the `cli_idle_timeout_ms` setting
  and the `:idle_timeout_ms` caller opt.

  `fallback_ms` is used when both the setting and the opt are absent or invalid.
  Pass `:infinity` to disable idle timeouts by default.
  """
  @spec resolve_idle_timeout(keyword(), pos_integer() | :infinity) :: pos_integer() | :infinity
  def resolve_idle_timeout(opts, fallback_ms) do
    default_timeout = resolve_default_timeout(fallback_ms)
    resolve_opt_timeout(Keyword.get(opts, :idle_timeout_ms, default_timeout), default_timeout)
  end

  defp resolve_default_timeout(fallback_ms) do
    case EyeInTheSky.Settings.get_integer("cli_idle_timeout_ms") do
      0 -> :infinity
      n when is_integer(n) and n > 0 -> n
      _ -> fallback_ms
    end
  end

  defp resolve_opt_timeout(opt_value, default_timeout) do
    case opt_value do
      0 -> :infinity
      n when is_integer(n) and n > 0 -> n
      :infinity -> :infinity
      _ -> default_timeout
    end
  end

  # ---------------------------------------------------------------------------
  # Environment helpers
  # ---------------------------------------------------------------------------

  # ---------------------------------------------------------------------------
  # Process cancellation
  # ---------------------------------------------------------------------------

  @doc """
  Kills the OS process (group and direct) behind `port`, then closes the port.

  Sends SIGTERM first. If the process is still alive after 500 ms, escalates to
  SIGKILL. Both the process group (`-pid`) and the direct PID are targeted to
  handle cases where the spawned binary is not the session leader.

  `log_prefix` is used in informational log messages (e.g. `"CLI"`, `"Codex.CLI"`).
  """
  @spec cancel_port(port(), String.t()) :: :ok
  def cancel_port(port, log_prefix \\ "CLI") when is_port(port) do
    case Elixir.Port.info(port, :os_pid) do
      {:os_pid, os_pid} ->
        System.cmd("kill", ["-TERM", "-#{os_pid}"], stderr_to_stdout: true)
        System.cmd("kill", ["-TERM", "#{os_pid}"], stderr_to_stdout: true)

        Process.sleep(500)

        case System.cmd("kill", ["-0", "#{os_pid}"], stderr_to_stdout: true) do
          {_, 0} ->
            Logger.info("[#{log_prefix}] Process #{os_pid} still alive, sending SIGKILL")
            System.cmd("kill", ["-9", "-#{os_pid}"], stderr_to_stdout: true)
            System.cmd("kill", ["-9", "#{os_pid}"], stderr_to_stdout: true)

          _ ->
            :ok
        end

      nil ->
        :ok
    end

    try do
      Elixir.Port.close(port)
    rescue
      ArgumentError -> :ok
    end

    :ok
  end

  # ---------------------------------------------------------------------------
  # Handler spawning
  # ---------------------------------------------------------------------------

  @doc """
  Spawns a handler process that waits for `{:port, port}`, then calls
  `handle_port_output/6`. Connects `port` to the handler and sends it the
  `{:port, port}` trigger message. Returns the handler `pid`.

  ## Options

  Same as `handle_port_output/6` — `:telemetry_prefix`, `:log_prefix`,
  `:max_buffer_bytes`.
  """
  @spec spawn_handler(port(), reference(), pid(), pos_integer() | :infinity, keyword()) :: pid()
  def spawn_handler(port, session_ref, caller, idle_timeout_ms, opts \\ []) do
    handler_pid =
      spawn_link(fn ->
        receive do
          {:port, received_port} ->
            handle_port_output(received_port, session_ref, caller, "", idle_timeout_ms, opts)
        end
      end)

    Port.connect(port, handler_pid)
    send(handler_pid, {:port, port})

    handler_pid
  end

  # ---------------------------------------------------------------------------
  # Environment helpers
  # ---------------------------------------------------------------------------

  @doc """
  Appends `{key, value}` to the charlist env list, skipping nil and empty values.
  """
  @spec maybe_add_env([{charlist(), charlist()}], String.t(), term()) ::
          [{charlist(), charlist()}]
  def maybe_add_env(env, _key, nil), do: env
  def maybe_add_env(env, _key, ""), do: env

  def maybe_add_env(env, key, value) do
    env ++ [{String.to_charlist(key), String.to_charlist(to_string(value))}]
  end
end
