defmodule EyeInTheSkyWeb.Claude.SessionManager do
  @moduledoc """
  Thin coordinator for Claude CLI sessions.

  Delegates session lifecycle to per-session SessionWorker processes
  running under DynamicSupervisor. Registry provides O(1) lookup.

  Resume requests are deduplicated: if a worker already exists for a
  session_id, the message is queued on the existing worker instead of
  spawning a new one.
  """

  use GenServer
  require Logger

  alias EyeInTheSkyWeb.Claude.SessionWorker

  @supervisor EyeInTheSkyWeb.Claude.SessionSupervisor
  @registry EyeInTheSkyWeb.Claude.Registry

  # --- Client API ---

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def start_session(session_id, prompt, opts \\ []) do
    GenServer.call(__MODULE__, {:spawn, :new, session_id, prompt, opts})
  end

  def continue_session(session_id, prompt, opts \\ []) do
    GenServer.call(__MODULE__, {:spawn, :continue, session_id, prompt, opts})
  end

  def resume_session(session_id, prompt, opts \\ []) do
    GenServer.call(__MODULE__, {:resume_or_queue, session_id, prompt, opts})
  end

  def cancel_session(session_ref) do
    GenServer.call(__MODULE__, {:cancel_session, session_ref})
  end

  def list_sessions do
    GenServer.call(__MODULE__, :list_sessions)
  end

  # --- Server Callbacks ---

  @impl true
  def init(_opts) do
    {:ok, %{}}
  end

  @impl true
  def handle_call({:spawn, spawn_type, session_id, prompt, opts}, _from, state) do
    case spawn_worker(spawn_type, session_id, prompt, opts) do
      {:ok, session_ref} ->
        {:reply, {:ok, session_ref}, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:resume_or_queue, session_id, prompt, opts}, _from, state) do
    case find_alive_worker(session_id) do
      {:ok, pid} ->
        # Worker exists, queue the message
        SessionWorker.queue_message(pid, prompt, opts)
        {:reply, {:ok, :queued}, state}

      :not_found ->
        # No worker, spawn a new one
        case spawn_worker(:resume, session_id, prompt, opts) do
          {:ok, session_ref} ->
            {:reply, {:ok, session_ref}, state}

          {:error, reason} ->
            {:reply, {:error, reason}, state}
        end
    end
  end

  @impl true
  def handle_call({:cancel_session, session_ref}, _from, state) do
    case Registry.lookup(@registry, {:ref, session_ref}) do
      [{pid, _}] ->
        try do
          SessionWorker.cancel(pid)
          {:reply, :ok, state}
        catch
          :exit, _ -> {:reply, {:error, :not_found}, state}
        end

      [] ->
        {:reply, {:error, :not_found}, state}
    end
  end

  @impl true
  def handle_call(:list_sessions, _from, state) do
    sessions =
      @supervisor
      |> DynamicSupervisor.which_children()
      |> Enum.flat_map(fn
        {_, pid, :worker, _} when is_pid(pid) ->
          try do
            [SessionWorker.get_info(pid)]
          catch
            :exit, _ -> []
          end

        _ ->
          []
      end)

    {:reply, sessions, state}
  end

  @impl true
  def handle_info(msg, state) do
    Logger.debug("Unhandled message in SessionManager: #{inspect(msg)}")
    {:noreply, state}
  end

  # --- Private ---

  defp spawn_worker(spawn_type, session_id, prompt, opts) do
    session_ref = make_ref()
    opts = Keyword.put(opts, :session_ref, session_ref)

    child_spec =
      {SessionWorker,
       %{spawn_type: spawn_type, session_id: session_id, prompt: prompt, opts: opts}}

    case DynamicSupervisor.start_child(@supervisor, child_spec) do
      {:ok, _pid} ->
        Logger.info("Spawned SessionWorker for #{session_id} (#{spawn_type})")
        {:ok, session_ref}

      {:error, reason} ->
        Logger.error("Failed to spawn SessionWorker: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp find_alive_worker(session_id) do
    case Registry.lookup(@registry, {:session, session_id}) do
      [{pid, _}] ->
        if Process.alive?(pid), do: {:ok, pid}, else: :not_found

      _ ->
        :not_found
    end
  end
end
