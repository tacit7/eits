defmodule EyeInTheSkyWeb.Claude.SimpleWorker do
  @moduledoc """
  Dead simple worker that spawns Claude with a prompt and exits when done.

  No queuing, no state management, no complexity. Just spawn and go.
  """

  use GenServer, restart: :temporary
  require Logger

  alias EyeInTheSkyWeb.Claude.CLI

  # --- Client API ---

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @doc """
  Spawn a worker that runs Claude with the given prompt.

  ## Options
    * `:prompt` - The prompt to send (required)
    * `:model` - Model to use (default: "sonnet")
    * `:project_path` - Working directory (default: current directory)
    * `:session_id` - Session UUID for resume (optional)
  """
  def spawn(prompt, opts \\ []) do
    child_spec = {__MODULE__, Keyword.put(opts, :prompt, prompt)}
    DynamicSupervisor.start_child(EyeInTheSkyWeb.Claude.SessionSupervisor, child_spec)
  end

  # --- Server Callbacks ---

  @impl true
  def init(opts) do
    prompt = Keyword.fetch!(opts, :prompt)
    session_id = Keyword.get(opts, :session_id)

    Logger.info("🚀 SimpleWorker: spawning Claude with prompt: #{String.slice(prompt, 0, 50)}...")

    cli_opts = [
      model: Keyword.get(opts, :model, "sonnet"),
      project_path: Keyword.get(opts, :project_path, File.cwd!()),
      caller: self()
    ]

    spawn_result = if session_id do
      CLI.resume_session(session_id, prompt, cli_opts)
    else
      CLI.spawn_new_session(prompt, cli_opts)
    end

    case spawn_result do
      {:ok, port, ref} ->
        Logger.info("✅ SimpleWorker: Claude spawned (ref: #{inspect(ref)})")
        {:ok, %{port: port, ref: ref, prompt: prompt}}

      {:error, reason} ->
        Logger.error("❌ SimpleWorker: failed to spawn Claude - #{inspect(reason)}")
        {:stop, reason}
    end
  end

  @impl true
  def handle_info({:claude_output, _ref, line}, state) do
    # Just log it
    Logger.info("📤 Claude: #{line}")
    {:noreply, state}
  end

  @impl true
  def handle_info({:claude_exit, _ref, status}, state) do
    if status == 0 do
      Logger.info("🏁 Claude exited successfully")
      {:stop, :normal, state}
    else
      Logger.error("❌ Claude exited with error status: #{status}")
      {:stop, {:shutdown, {:exit_status, status}}, state}
    end
  end

  @impl true
  def handle_info(msg, state) do
    Logger.debug("SimpleWorker: unhandled message #{inspect(msg)}")
    {:noreply, state}
  end
end
