defmodule EyeInTheSky.Gemini.StreamHandler do
  @moduledoc """
  Handles streaming from Gemini CLI SDK and translates events to Claude message tuples.

  Spawns a supervised Task that consumes the lazy Stream from GeminiCliSdk.execute/2
  or GeminiCliSdk.resume_session/3 and sends parsed messages to a caller process.
  """

  alias EyeInTheSky.Claude.Message
  alias EyeInTheSky.Gemini.StreamHandler.Registry, as: StreamRegistry
  alias GeminiCliSdk.Types

  require Logger

  @doc """
  Start a new Gemini session with streaming output.

  Spawns a Task under EyeInTheSky.TaskSupervisor that consumes the stream
  and sends messages to the caller_pid.

  Returns `{:ok, sdk_ref, handler_pid}` where:
    * `sdk_ref` is a unique reference for this session (used for cancellation)
    * `handler_pid` is the pid of the spawned task
  """
  @spec start(prompt :: String.t(), opts :: map(), caller :: pid()) ::
        {:ok, sdk_ref :: reference(), handler_pid :: pid()} | {:error, term()}
  def start(prompt, opts, caller_pid, test_opts \\ []) do
    sdk_ref = make_ref()

    stream_fn =
      Keyword.get(test_opts, :stream_fn, fn -> GeminiCliSdk.execute(prompt, opts) end)

    case spawn_stream_consumer(sdk_ref, stream_fn, caller_pid) do
      {:ok, pid} ->
        StreamRegistry.register(sdk_ref, pid)
        {:ok, sdk_ref, pid}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Resume an existing Gemini session.

  Same as start/3 but resumes a conversation by session_id.
  """
  @spec resume(session_id :: String.t(), prompt :: String.t(),
               opts :: map(), caller :: pid()) ::
        {:ok, sdk_ref :: reference(), handler_pid :: pid()} | {:error, term()}
  def resume(session_id, prompt, opts, caller_pid, test_opts \\ []) do
    sdk_ref = make_ref()

    stream_fn =
      Keyword.get(test_opts, :stream_fn,
        fn -> GeminiCliSdk.resume_session(session_id, opts, prompt) end
      )

    case spawn_stream_consumer(sdk_ref, stream_fn, caller_pid) do
      {:ok, pid} ->
        StreamRegistry.register(sdk_ref, pid)
        {:ok, sdk_ref, pid}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Cancel a running Gemini session.

  Stops the task and unregisters it from the ETS registry.
  """
  @spec cancel(sdk_ref :: reference()) :: :ok | {:error, :not_found}
  def cancel(sdk_ref) do
    case StreamRegistry.lookup(sdk_ref) do
      nil ->
        {:error, :not_found}

      pid when is_pid(pid) ->
        Process.exit(pid, :kill)
        StreamRegistry.unregister(sdk_ref)
        :ok
    end
  end

  # --- Registry ---

  defmodule Registry do
    @moduledoc false
    use GenServer

    @table :eits_gemini_stream_registry

    def start_link(_) do
      GenServer.start_link(__MODULE__, [], name: __MODULE__)
    end

    @impl true
    def init(_) do
      :ets.new(@table, [:named_table, :public, :set])
      {:ok, nil}
    end

    def register(ref, pid) do
      :ets.insert(@table, {ref, pid})
      :ok
    end

    def lookup(ref) do
      case :ets.lookup(@table, ref) do
        [{^ref, pid}] -> pid
        [] -> nil
      end
    end

    def unregister(ref) do
      :ets.delete(@table, ref)
      :ok
    end
  end

  # --- Private ---

  defp spawn_stream_consumer(sdk_ref, stream_fn, caller_pid) do
    Task.Supervisor.start_child(
      EyeInTheSky.TaskSupervisor,
      fn ->
        Process.monitor(caller_pid)
        consume_stream(sdk_ref, stream_fn.(), caller_pid)
      end,
      restart: :temporary
    )
  end

  defp consume_stream(sdk_ref, stream, caller_pid) do
    stream
    |> Stream.each(&handle_event(sdk_ref, &1, caller_pid))
    |> Stream.run()
  rescue
    e ->
      Logger.error("Stream error in Gemini handler: #{inspect(e)}")
      send(caller_pid, {:claude_error, sdk_ref, {:gemini_error, inspect(e)}})
  end

  defp handle_event(sdk_ref, event, caller_pid) do
    case event do
      %Types.InitEvent{session_id: session_id} ->
        send(caller_pid, {:codex_session_id, sdk_ref, session_id})

      %Types.MessageEvent{role: "assistant", content: content} when is_binary(content) ->
        msg = Message.text(content)
        send(caller_pid, {:claude_message, sdk_ref, msg})

      %Types.MessageEvent{role: "user"} ->
        :ok

      %Types.ToolUseEvent{tool_name: name, parameters: params} ->
        msg = %Message{type: :tool_use, content: name, metadata: %{input: params}}
        send(caller_pid, {:claude_message, sdk_ref, msg})

      %Types.ToolResultEvent{tool_id: tool_id, output: output} ->
        msg = %Message{type: :tool_result, content: output, metadata: %{tool_id: tool_id}}
        send(caller_pid, {:claude_message, sdk_ref, msg})

      %Types.ResultEvent{status: "ok", stats: stats} ->
        stats_map = stats_to_map(stats)
        msg = %Message{type: :result, content: "", metadata: stats_map}
        send(caller_pid, {:claude_message, sdk_ref, msg})
        send(caller_pid, {:claude_complete, sdk_ref, ""})

      %Types.ResultEvent{status: "success", stats: stats} ->
        stats_map = stats_to_map(stats)
        msg = %Message{type: :result, content: "", metadata: stats_map}
        send(caller_pid, {:claude_message, sdk_ref, msg})
        send(caller_pid, {:claude_complete, sdk_ref, ""})

      %Types.ResultEvent{status: "error", error: error} ->
        send(caller_pid, {:claude_error, sdk_ref, {:gemini_error, error}})

      %Types.ErrorEvent{message: msg} ->
        send(caller_pid, {:claude_error, sdk_ref, {:gemini_error, msg}})

      _ ->
        :ok
    end
  end

  defp stats_to_map(nil), do: %{}

  defp stats_to_map(%{total_tokens: total, input_tokens: input, output_tokens: output,
                      duration_ms: duration} = stats) do
    %{
      total_tokens: total,
      input_tokens: input,
      output_tokens: output,
      duration_ms: duration,
      tool_calls: Map.get(stats, :tool_calls, 0)
    }
  end
end
