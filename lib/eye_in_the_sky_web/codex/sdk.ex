defmodule EyeInTheSkyWeb.Codex.SDK do
  @moduledoc """
  High-level SDK for interacting with OpenAI Codex CLI.

  Provides the same streaming API as Claude.SDK, using Codex.CLI and Codex.Parser.
  Delivers parsed messages to the caller using the same message protocol:

    * `{:claude_message, ref, %Message{}}` - each parsed event
    * `{:claude_complete, ref, session_id}` - conversation completed
    * `{:claude_error, ref, reason}` - error occurred

  ## Key Differences from Claude.SDK

  - Codex emits complete items (no streaming deltas)
  - The handler accumulates agent_message texts during a turn
  - On turn.completed, builds a synthetic Message.result with accumulated text
  - Reuses Claude.SDK.Registry for ref->port tracking
  """

  use EyeInTheSkyWeb.SDK.MessageHandler

  alias EyeInTheSkyWeb.Claude.{Message, Utils}
  alias EyeInTheSkyWeb.Claude.SDK.Registry
  alias EyeInTheSkyWeb.Codex.Parser
  alias EyeInTheSkyWeb.SDK.MessageHandler

  require Logger

  @type ref :: reference()
  @type opts :: keyword()

  @loop_opts [
    parser: Parser,
    telemetry_prefix: [:eits, :codex, :sdk],
    log_raw_key: "log_codex_raw",
    log_raw_prefix: "codex.raw"
  ]

  @doc """
  Build the EITS init prompt prepended to new Codex sessions.

  Provides the agent with EITS environment context and CLI instructions.
  Accepts any struct with the fields: eits_session_uuid, session_id, agent_id, project_id.
  """
  @spec eits_init_prompt(map()) :: String.t()
  def eits_init_prompt(state) do
    """
    EITS environment variables are pre-set in your shell via shell_environment_policy:
    - EITS_SESSION_UUID=#{state.eits_session_uuid}
    - EITS_SESSION_ID=#{state.session_id}
    - EITS_AGENT_UUID=#{state.agent_id}
    - EITS_PROJECT_ID=#{state.project_id}
    - EITS_URL=http://localhost:5001/api/v1

    Use `eits` CLI for task tracking:
    - `eits tasks create --title "Task name" --description "Details"`
    - `eits tasks start <task_id>`
    - `eits tasks update <task_id> --state 4` (when done)
    - `eits notes create --parent-type session --parent-id $EITS_SESSION_UUID --title "Note" --body "Content"`

    Now proceed with the task:
    """
  end

  @doc """
  Start a new Codex session with streaming output.

  ## Options

  Required:
    * `:to` - pid to send messages to

  Optional:
    * `:model` - model name (e.g., "o3-mini", "o4-mini")
    * `:project_path` - working directory for Codex
    * `:full_auto` - autonomous mode (default: true)
  """
  @spec start(String.t(), opts()) :: {:ok, ref(), pid()} | {:error, term()}
  def start(prompt, opts \\ []) do
    to = Keyword.fetch!(opts, :to)
    sdk_ref = make_ref()
    meta = %{session_id: opts[:session_id], model: opts[:model]}

    :telemetry.execute([:eits, :codex, :sdk, :start], %{system_time: System.system_time()}, meta)
    Logger.info("[telemetry] codex.sdk.start session_id=#{meta.session_id} model=#{meta.model}")

    handler_pid = spawn_handler_process(sdk_ref, to, opts[:session_id])
    cli = Keyword.get(opts, :cli_module) || Utils.codex_cli_module()

    cli_opts =
      opts
      |> Keyword.put(:caller, handler_pid)
      |> Keyword.delete(:to)
      |> Keyword.delete(:cli_module)

    case cli.spawn_new_session(prompt, cli_opts) do
      {:ok, port, _cli_ref} ->
        Registry.register(sdk_ref, port)
        send(handler_pid, {:start_handling, sdk_ref})
        {:ok, sdk_ref, handler_pid}

      {:error, reason} ->
        :telemetry.execute(
          [:eits, :codex, :sdk, :error],
          %{system_time: System.system_time()},
          Map.put(meta, :reason, reason)
        )

        Logger.error(
          "[telemetry] codex.sdk.error session_id=#{meta.session_id} reason=#{inspect(reason)}"
        )

        Process.exit(handler_pid, :kill)
        {:error, reason}
    end
  end

  @doc """
  Resume an existing Codex session.

  Same as `start/2` but resumes a conversation by thread/session ID.
  """
  @spec resume(String.t(), String.t(), opts()) :: {:ok, ref(), pid()} | {:error, term()}
  def resume(session_id, prompt, opts \\ []) do
    to = Keyword.fetch!(opts, :to)
    sdk_ref = make_ref()
    meta = %{session_id: session_id, model: opts[:model]}

    :telemetry.execute([:eits, :codex, :sdk, :start], %{system_time: System.system_time()}, meta)

    Logger.info("[telemetry] codex.sdk.resume session_id=#{session_id} model=#{meta.model}")

    handler_pid = spawn_handler_process(sdk_ref, to, opts[:session_id])
    cli = Keyword.get(opts, :cli_module) || Utils.codex_cli_module()

    cli_opts =
      opts
      |> Keyword.put(:caller, handler_pid)
      |> Keyword.delete(:to)
      |> Keyword.delete(:cli_module)

    case cli.resume_session(session_id, prompt, cli_opts) do
      {:ok, port, _cli_ref} ->
        Registry.register(sdk_ref, port)
        send(handler_pid, {:start_handling, sdk_ref})
        {:ok, sdk_ref, handler_pid}

      {:error, reason} ->
        :telemetry.execute(
          [:eits, :codex, :sdk, :error],
          %{system_time: System.system_time()},
          Map.put(meta, :reason, reason)
        )

        Logger.error(
          "[telemetry] codex.sdk.error session_id=#{session_id} reason=#{inspect(reason)}"
        )

        Process.exit(handler_pid, :kill)
        {:error, reason}
    end
  end

  @doc """
  Cancel a running Codex session.
  """
  @spec cancel(ref()) :: :ok | {:error, :not_found}
  def cancel(ref) do
    cli = Utils.codex_cli_module()

    case Registry.lookup(ref) do
      nil ->
        {:error, :not_found}

      port when is_port(port) ->
        cli.cancel(port)
        :ok

      pid when is_pid(pid) ->
        send(pid, :cancel)
        :ok
    end
  end

  # ---------------------------------------------------------------------------
  # Handler process
  # ---------------------------------------------------------------------------

  defp spawn_handler_process(sdk_ref, caller_pid, fallback_session_id) do
    spawn(fn ->
      Process.monitor(caller_pid)

      receive do
        {:start_handling, ^sdk_ref} ->
          :telemetry.execute(
            [:eits, :codex, :sdk, :handler, :ready],
            %{system_time: System.system_time()},
            %{}
          )

          state = %{
            sdk_ref: sdk_ref,
            caller_pid: caller_pid,
            session_id: nil,
            accumulated_text: "",
            fallback_session_id: fallback_session_id
          }

          MessageHandler.run_loop(__MODULE__, state, @loop_opts)

        {:DOWN, _ref, :process, ^caller_pid, _reason} ->
          MessageHandler.stop_and_unregister(sdk_ref)
      after
        5_000 ->
          send(caller_pid, {:claude_error, sdk_ref, :handler_timeout})
      end
    end)
  end

  # ---------------------------------------------------------------------------
  # MessageHandler behaviour implementation
  # ---------------------------------------------------------------------------

  @impl MessageHandler
  def handle_message(%Message{type: :text} = message, state) do
    %{sdk_ref: sdk_ref, caller_pid: caller_pid, accumulated_text: acc} = state
    new_acc = acc <> (message.content || "")
    send(caller_pid, {:claude_message, sdk_ref, message})
    {:continue, %{state | accumulated_text: new_acc}}
  end

  def handle_message(message, state) do
    send(state.caller_pid, {:claude_message, state.sdk_ref, message})
    {:continue, state}
  end

  @impl MessageHandler
  def handle_result(data, state) do
    %{sdk_ref: sdk_ref, caller_pid: caller_pid, accumulated_text: acc} = state

    final_session_id = data[:session_id] || state[:session_id]
    result_text = if acc != "", do: acc, else: nil

    metadata = %{
      session_id: final_session_id,
      usage: data[:usage],
      input_tokens: data[:input_tokens],
      output_tokens: data[:output_tokens]
    }

    :telemetry.execute(
      [:eits, :codex, :sdk, :result],
      %{
        text_length: if(result_text, do: String.length(result_text), else: 0),
        input_tokens: data[:input_tokens] || 0,
        output_tokens: data[:output_tokens] || 0
      },
      %{session_id: final_session_id}
    )

    Logger.info(
      "[telemetry] codex.sdk.result session_id=#{final_session_id} " <>
        "text_length=#{if result_text, do: String.length(result_text), else: 0}"
    )

    if result_text do
      msg = Message.result(result_text, metadata)
      send(caller_pid, {:claude_message, sdk_ref, msg})
    end

    send(caller_pid, {:claude_complete, sdk_ref, final_session_id})

    :telemetry.execute(
      [:eits, :codex, :sdk, :complete],
      %{system_time: System.system_time()},
      %{session_id: final_session_id}
    )

    Logger.info("[telemetry] codex.sdk.complete session_id=#{final_session_id}")

    MessageHandler.finalize_after_terminal_event(sdk_ref, final_session_id, @loop_opts)
    :ok
  end

  @impl MessageHandler
  def on_session_id(sid, state) do
    # Notify the worker immediately so it can sync the provider_conversation_id
    send(state.caller_pid, {:codex_session_id, state.sdk_ref, sid})
    %{state | session_id: sid}
  end

  @impl MessageHandler
  def resolve_exit_session_id(state) do
    state[:session_id] || state[:fallback_session_id] || ""
  end
end
