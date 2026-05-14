defmodule EyeInTheSky.Terminal.PtySupervisor do
  @moduledoc """
  DynamicSupervisor for persistent PTY processes.

  PTY sessions are keyed by `session_key` in `PtyRegistry`. Use
  `find_or_start_pty/1` to get an existing PTY or start a new one.
  This is the primary API — callers should never start PtyServer directly.
  """

  use DynamicSupervisor

  alias EyeInTheSky.Terminal.{PtyRegistry, PtyServer}

  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  @doc """
  Return the pid of the PTY for `session_key`, starting one if needed.

  Options are passed through to `PtyServer.start_link/1` on first start.
  `:session_key` is required. On subsequent calls the existing pid is returned
  and remaining opts are ignored.

  Returns `{:ok, pid}`.
  """
  @spec find_or_start_pty(keyword()) :: {:ok, pid()} | {:error, term()}
  def find_or_start_pty(opts) do
    session_key = Keyword.fetch!(opts, :session_key)

    case Registry.lookup(PtyRegistry, session_key) do
      [{pid, _}] ->
        {:ok, pid}

      [] ->
        case DynamicSupervisor.start_child(__MODULE__, {PtyServer, opts}) do
          {:ok, pid} -> {:ok, pid}
          {:error, {:already_started, pid}} -> {:ok, pid}
          {:error, reason} -> {:error, reason}
        end
    end
  end

  @doc "Spawn a new PtyServer unconditionally. Prefer `find_or_start_pty/1`."
  def start_pty(opts) do
    DynamicSupervisor.start_child(__MODULE__, {PtyServer, opts})
  end
end
