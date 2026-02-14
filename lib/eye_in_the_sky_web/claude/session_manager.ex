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

  alias EyeInTheSkyWeb.Claude.{SessionWorker, CLI}
  alias EyeInTheSkyWeb.{Sessions, Agents}

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
    GenServer.call(__MODULE__, {:spawn, :resume, session_id, prompt, opts})
  end

  @doc """
  Creates an agent + session and starts a SessionWorker with the initial prompt.

  Same DB setup as AgentManager.create_agent/1 but routes through
  SessionWorker instead of AgentWorker.

  ## Options
    * `:agent_type` - Agent type (e.g., "claude", "codex"). Default: "claude"
    * `:model` - Model to use
    * `:project_id` - Project ID to associate with
    * `:project_path` - Working directory for Claude
    * `:description` - Human-readable agent description
    * `:instructions` - Initial prompt/instructions for the agent

  Returns `{:ok, %{agent: agent, session: session, session_ref: ref}}` or `{:error, reason}`.
  """
  def create_agent(opts) do
    agent_uuid = Ecto.UUID.generate()
    session_uuid = Ecto.UUID.generate()

    description = opts[:description] || "Agent session"

    with {:ok, agent} <-
           Agents.create_agent(%{
             uuid: agent_uuid,
             agent_type: opts[:agent_type] || "claude",
             project_id: opts[:project_id],
             status: "active",
             description: description
           }),
         {:ok, session} <-
           Sessions.create_session(%{
             uuid: session_uuid,
             agent_id: agent.id,
             name: description,
             description: "session-id #{session_uuid} agent-id #{agent_uuid}",
             model: opts[:model],
             provider: "claude",
             git_worktree_path: opts[:project_path],
             started_at: DateTime.utc_now() |> DateTime.to_iso8601()
           }) do
      instructions = opts[:instructions] || description

      # Use minimal options like the working command line test
      session_opts = [
        model: opts[:model] || "sonnet",
        project_path: opts[:project_path]
      ]

      Logger.info("🔧 create_agent: starting session with opts: #{inspect(session_opts)}")

      case start_session(session.uuid, instructions, session_opts) do
        {:ok, session_ref} ->
          Logger.info("✅ create_agent: session started, ref=#{inspect(session_ref)}")
          {:ok, %{agent: agent, session: session, session_ref: session_ref}}

        {:error, reason} ->
          Logger.error("❌ create_agent: session start failed - #{inspect(reason)}")
          {:error, {:send_failed, reason}}
      end
    else
      {:error, reason} ->
        Logger.error("❌ create_agent: DB record creation failed - #{inspect(reason)}")
        {:error, reason}
    end
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
