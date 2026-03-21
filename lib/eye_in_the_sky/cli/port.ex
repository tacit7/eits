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
  @spec handle_port_output(port(), reference(), pid(), binary(), pos_integer(), keyword()) :: :ok
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
