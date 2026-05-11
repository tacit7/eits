defmodule EyeInTheSky.Gemini.StreamHandler do
  @moduledoc """
  Handles streaming from Gemini CLI SDK and translates events to Claude message tuples.

  Spawns a supervised Task that consumes the lazy Stream from GeminiCliSdk.execute/2
  or GeminiCliSdk.resume_session/3 and sends parsed messages to a caller process.
  """

  alias EyeInTheSky.Claude.Message
  alias EyeInTheSky.Gemini.Pricing
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
    model = opts_model(opts)

    stream_fn =
      Keyword.get(test_opts, :stream_fn, fn -> GeminiCliSdk.execute(prompt, opts) end)

    case spawn_stream_consumer(sdk_ref, stream_fn, caller_pid, model) do
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
  @spec resume(session_id :: String.t(), prompt :: String.t(), opts :: map(), caller :: pid()) ::
          {:ok, sdk_ref :: reference(), handler_pid :: pid()} | {:error, term()}
  def resume(session_id, prompt, opts, caller_pid, test_opts \\ []) do
    sdk_ref = make_ref()
    model = opts_model(opts)

    stream_fn =
      Keyword.get(test_opts, :stream_fn, fn ->
        GeminiCliSdk.resume_session(session_id, opts, prompt)
      end)

    case spawn_stream_consumer(sdk_ref, stream_fn, caller_pid, model) do
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
    @moduledoc """
    ETS-backed registry for Gemini stream tasks.

    Entries are keyed by `sdk_ref` and monitor the registered pid. When the
    pid terminates (normal completion, error, crash, or cancel), the entry
    is removed automatically so no stale refs accumulate.
    """
    use GenServer

    @table :eits_gemini_stream_registry

    def start_link(_) do
      GenServer.start_link(__MODULE__, [], name: __MODULE__)
    end

    @impl true
    def init(_) do
      :ets.new(@table, [:named_table, :protected, :set])
      # Secondary index: monitor_ref -> sdk_ref, so :DOWN can find the entry.
      :ets.new(monitor_table(), [:named_table, :protected, :set])
      {:ok, %{}}
    end

    def register(ref, pid) do
      GenServer.call(__MODULE__, {:register, ref, pid})
    end

    def lookup(ref) do
      case :ets.lookup(@table, ref) do
        [{^ref, pid, _mon}] -> pid
        [] -> nil
      end
    end

    def unregister(ref) do
      GenServer.call(__MODULE__, {:unregister, ref})
    end

    @impl true
    def handle_call({:register, ref, pid}, _from, state) do
      mon = Process.monitor(pid)
      :ets.insert(@table, {ref, pid, mon})
      :ets.insert(monitor_table(), {mon, ref})
      {:reply, :ok, state}
    end

    def handle_call({:unregister, ref}, _from, state) do
      case :ets.lookup(@table, ref) do
        [{^ref, _pid, mon}] ->
          Process.demonitor(mon, [:flush])
          :ets.delete(@table, ref)
          :ets.delete(monitor_table(), mon)

        [] ->
          :ok
      end

      {:reply, :ok, state}
    end

    @impl true
    def handle_info({:DOWN, mon, :process, _pid, _reason}, state) do
      case :ets.lookup(monitor_table(), mon) do
        [{^mon, ref}] ->
          :ets.delete(@table, ref)
          :ets.delete(monitor_table(), mon)

        [] ->
          :ok
      end

      {:noreply, state}
    end

    defp monitor_table, do: :eits_gemini_stream_registry_monitors
  end

  # --- Private ---

  defp opts_model(%{model: model}) when is_binary(model), do: model
  defp opts_model(_), do: nil

  defp spawn_stream_consumer(sdk_ref, stream_fn, caller_pid, model) do
    Task.Supervisor.start_child(
      EyeInTheSky.TaskSupervisor,
      fn ->
        Process.monitor(caller_pid)
        consume_stream(sdk_ref, stream_fn.(), caller_pid, model)
      end,
      restart: :temporary
    )
  end

  defp consume_stream(sdk_ref, stream, caller_pid, model) do
    # State carries the accumulated assistant text, session_id from InitEvent,
    # and per-turn tool_calls so the :result event can emit a body that has
    # the tool invocations baked in. The DM renderer parses lines matching
    # `> \`ToolName\` <args>` out of the persisted body to draw tool widgets
    # — same convention Codex uses (e.g. `> \`Bash\` cd ... && ...`).
    initial = %{text: "", session_id: nil, model: model, tool_calls: []}

    Enum.reduce(stream, initial, fn event, state ->
      handle_event(sdk_ref, event, caller_pid, state)
    end)
  rescue
    e ->
      Logger.error("Stream error in Gemini handler: #{inspect(e)}")
      send(caller_pid, {:claude_error, sdk_ref, {:gemini_error, inspect(e)}})
  end

  defp handle_event(sdk_ref, event, caller_pid, state) do
    case event do
      %Types.InitEvent{session_id: session_id} ->
        send(caller_pid, {:codex_session_id, sdk_ref, session_id})
        %{state | session_id: session_id}

      # Gemini CLI emits TWO kinds of assistant MessageEvents:
      #   * delta: true   — incremental streaming chunk
      #   * delta: false  — final aggregated content (sum of all preceding deltas)
      # If we accumulate both into state.text, the final message gets the chunks
      # concatenated with the full text → doubled output. So:
      #   * On a delta, append to state.text and send a delta Message for live
      #     streaming display.
      #   * On a final non-delta, REPLACE state.text (don't append) so the
      #     :result event carries the correct single copy. Don't emit a
      #     duplicate :text Message — the StreamAssembler already shows the
      #     accumulated deltas and the final :result will commit it.
      %Types.MessageEvent{role: "assistant", content: content, delta: true}
      when is_binary(content) ->
        msg = Message.text(content, true)
        send(caller_pid, {:claude_message, sdk_ref, msg})
        %{state | text: state.text <> content}

      %Types.MessageEvent{role: "assistant", content: content}
      when is_binary(content) ->
        # Non-delta (delta: false or nil) — final aggregated message.
        # If we accumulated deltas, replace; otherwise treat as the only emit.
        if state.text == "" do
          msg = Message.text(content, false)
          send(caller_pid, {:claude_message, sdk_ref, msg})
        end

        %{state | text: content}

      %Types.MessageEvent{role: "user"} ->
        state

      # Codex-style tool_use: name + input live inside `content` so the
      # CodexStreamAssembler can render rich tool blocks (name + parsed input)
      # in the live-stream indicator. We also remember the call in state so
      # the final :result body can embed a `> \`name\` <args>` line that the
      # persisted DM renderer picks up via parse_body_segment/1.
      %Types.ToolUseEvent{tool_name: name, parameters: params, tool_id: tool_id} ->
        msg = %Message{
          type: :tool_use,
          content: %{name: name, input: params},
          metadata: %{tool_id: tool_id}
        }

        send(caller_pid, {:claude_message, sdk_ref, msg})
        %{state | tool_calls: state.tool_calls ++ [{name, params}]}

      %Types.ToolResultEvent{tool_id: tool_id, output: output} ->
        # CodexStreamAssembler has no tool_result handler today — output is
        # surfaced via the originating tool_use's input/output metadata.
        # We still forward the message in case a future assembler picks it up.
        msg = %Message{type: :tool_result, content: output, metadata: %{tool_id: tool_id}}
        send(caller_pid, {:claude_message, sdk_ref, msg})
        state

      %Types.ResultEvent{status: status, stats: stats, timestamp: ts}
      when status in ["ok", "success"] ->
        # Derive a stable per-turn UUID so a subsequent Sync from JSONL can't
        # insert a duplicate row. We can't know the JSONL turn "id" during the
        # live stream, but a deterministic hash of (session_id, turn_timestamp)
        # is stable enough for the dedup unique index on source_uuid.
        turn_uuid = derive_turn_uuid(state.session_id, ts)
        stats_map = stats_to_map(stats, state.model, turn_uuid)
        body = build_result_body(state.text, state.tool_calls)
        msg = %Message{type: :result, content: body, metadata: stats_map}
        send(caller_pid, {:claude_message, sdk_ref, msg})
        send(caller_pid, {:claude_complete, sdk_ref, state.session_id})
        state

      %Types.ResultEvent{status: "error", error: error} ->
        send(caller_pid, {:claude_error, sdk_ref, {:gemini_error, error}})
        state

      %Types.ErrorEvent{message: msg} ->
        send(caller_pid, {:claude_error, sdk_ref, {:gemini_error, msg}})
        state

      _ ->
        state
    end
  end

  # Format the persisted assistant body. Tool calls are appended after the
  # prose as `> \`ToolName\` <json-args>` lines so DmHelpers.parse_body_segment/1
  # recognizes them and the DM renderer draws tool widgets.
  defp build_result_body(text, []), do: text

  defp build_result_body(text, tool_calls) do
    lines = Enum.map_join(tool_calls, "\n", &format_tool_call_line/1)

    case String.trim(text) do
      "" -> lines
      _ -> text <> "\n\n" <> lines
    end
  end

  defp format_tool_call_line({name, params}) do
    args = format_tool_args(params)
    "> `#{name}` #{args}"
  end

  defp format_tool_args(%{} = params) do
    case Jason.encode(params) do
      {:ok, json} -> json
      {:error, _} -> inspect(params)
    end
  end

  defp format_tool_args(other), do: to_string(other)

  defp stats_to_map(nil, _model, _turn_uuid), do: %{}

  defp stats_to_map(
         %{total_tokens: total, input_tokens: input, output_tokens: output, duration_ms: duration} =
           stats,
         model,
         turn_uuid
       ) do
    # Atom keys — AgentWorkerEvents.build_db_metadata/1 looks them up via
    # `metadata[:duration_ms]` / `metadata[:usage]`. String keys here cause
    # every db_metadata field to come back nil and the row persists with
    # metadata = NULL (verified empirically). The encoder turns atoms into
    # JSON keys on persist, and consumers read them back as strings — the
    # roundtrip is one-way so the storage shape stays string-keyed.
    #
    # :uuid is forwarded by AgentWorker → WorkerEvents.on_result_received as
    # source_uuid on the persisted message row. A stable per-turn UUID prevents
    # duplicate rows when the user later clicks Sync to import from JSONL.
    cost = Pricing.cost(model, input, output)
    model_usage = Pricing.model_usage(model, input, output)

    %{
      uuid: turn_uuid,
      usage: %{
        input_tokens: input,
        output_tokens: output,
        total_tokens: total
      },
      duration_ms: duration,
      tool_calls: Map.get(stats, :tool_calls, 0),
      total_cost_usd: cost,
      model_usage: model_usage
    }
  end

  # Derive a deterministic UUID from the Gemini session_id and per-turn
  # timestamp. The JSONL turn "id" is not available in the live stream, so
  # this is a best-effort stable key for dedup. Falls back to a random UUID
  # if session_id is nil (should not happen in practice).
  defp derive_turn_uuid(session_id, timestamp) when is_binary(session_id) do
    input = "#{session_id}:#{timestamp || Ecto.UUID.generate()}"
    hash = :crypto.hash(:sha256, input) |> binary_part(0, 16)

    case Ecto.UUID.cast(hash) do
      {:ok, uuid} -> uuid
      _ -> Ecto.UUID.generate()
    end
  end

  defp derive_turn_uuid(_, _), do: Ecto.UUID.generate()
end
