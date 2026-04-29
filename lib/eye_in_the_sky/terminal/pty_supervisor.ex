defmodule EyeInTheSky.Terminal.PtySupervisor do
  @moduledoc "DynamicSupervisor for per-session PTY processes."

  use DynamicSupervisor

  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  @doc "Spawn a new PtyServer. Returns `{:ok, pid}`."
  def start_pty(opts) do
    spec = {EyeInTheSky.Terminal.PtyServer, opts}
    DynamicSupervisor.start_child(__MODULE__, spec)
  end
end
