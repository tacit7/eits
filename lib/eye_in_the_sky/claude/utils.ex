defmodule EyeInTheSky.Claude.Utils do
  @moduledoc """
  Shared utilities for Claude CLI workers.
  """

  @doc """
  Strip ANSI escape sequences from CLI output.
  """
  @spec strip_ansi_codes(String.t()) :: String.t()
  def strip_ansi_codes(text) when is_binary(text) do
    text
    |> String.replace(~r/\e\[[0-9;]*[a-zA-Z]/, "")
    |> String.replace(~r/\e\][^\a]*\a/, "")
    |> String.replace(~r/\e[^[\]]*/, "")
  end

  def strip_ansi_codes(text), do: text

  @doc """
  Close a port safely, ignoring errors if already closed.
  """
  @spec close_port_safely(port() | pid() | nil) :: :ok
  def close_port_safely(nil), do: :ok

  def close_port_safely(port) when is_port(port) do
    if Port.info(port) != nil do
      try do
        Port.close(port)
      rescue
        _ -> :ok
      end
    end

    :ok
  end

  # Mock ports are pids in tests
  def close_port_safely(pid) when is_pid(pid) do
    if Process.alive?(pid) do
      send(pid, :cancel)
    end

    :ok
  end

  def close_port_safely(_), do: :ok

  @doc """
  Returns the configured CLI module (real or mock for tests).
  """
  @spec cli_module() :: module()
  def cli_module do
    Application.get_env(:eye_in_the_sky, :cli_module, EyeInTheSky.Claude.CLI)
  end

  @doc """
  Returns the configured Codex CLI module (real or mock for tests).
  """
  @spec codex_cli_module() :: module()
  def codex_cli_module do
    Application.get_env(:eye_in_the_sky, :codex_cli_module, EyeInTheSky.Codex.CLI)
  end
end
