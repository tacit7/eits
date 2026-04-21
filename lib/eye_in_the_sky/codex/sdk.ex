defmodule EyeInTheSky.Codex.SDK do
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

  use EyeInTheSky.SDK.MessageHandler

  alias EyeInTheSky.Claude.{Message, Utils}
  alias EyeInTheSky.Claude.SDK.Registry
  alias EyeInTheSky.Codex.{Parser, ToolMapper}
  alias EyeInTheSky.SDK.MessageHandler

  require Logger

  @type ref :: reference()
  @type opts :: keyword()

  @loop_opts [
    parser: Parser,
    telemetry_prefix: [:eits, :codex, :sdk],
    log_raw_key: "log_codex_raw",
    log_raw_prefix: "codex.raw",
    forward_raw_lines: true
  ]

  @eits_cli_reference """
    eits tasks begin --title "<title>"
    eits tasks annotate <id> --body "..."
    eits tasks update <id> --state 4
    eits dm --to <session_uuid> --message "<text>"
    eits commits create --hash <hash>
  """

  @doc """
  Build the EITS init prompt prepended to new Codex sessions.

  Injects session-specific EITS context and eits CLI workflow instructions.
  Accepts any struct with the fields: eits_session_uuid, session_id, agent_id, project_id.
  """
  @spec eits_init_prompt(map()) :: String.t()
  def eits_init_prompt(state) do
    """
    EITS context:
    - EITS_SESSION_UUID=#{state.eits_session_uuid}
    - EITS_SESSION_ID=#{state.session_id}
    - EITS_AGENT_ID=#{state.agent_id}
    - EITS_PROJECT_ID=#{state.project_id}

    Use the eits CLI script for all EITS operations:

    #{@eits_cli_reference}
    To spawn a child agent, always pass --provider codex:
      eits agents spawn --provider codex --instructions "<text>" [--model <model>]

    You MUST claim a task before editing files:
      eits tasks begin --title "<title of your work>"

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
    sdk_ref = make_ref()

    Logger.info(
      "[telemetry] codex.sdk.start session_id=#{opts[:session_id]} model=#{opts[:model]}"
    )

    run_codex_session(sdk_ref, prompt, opts, fn cli, p, o -> cli.spawn_new_session(p, o) end)
  end

  @doc """
  Resume an existing Codex session.

  Same as `start/2` but resumes a conversation by thread/session ID.
  """
  @spec resume(String.t(), String.t(), opts()) :: {:ok, ref(), pid()} | {:error, term()}
  def resume(session_id, prompt, opts \\ []) do
    sdk_ref = make_ref()
    Logger.info("[telemetry] codex.sdk.resume session_id=#{session_id} model=#{opts[:model]}")

    run_codex_session(sdk_ref, prompt, opts, fn cli, p, o ->
      cli.resume_session(session_id, p, o)
    end)
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
  # Private helpers
  # ---------------------------------------------------------------------------

  defp run_codex_session(sdk_ref, prompt, opts, cli_fn) do
    to = Keyword.fetch!(opts, :to)
    meta = %{session_id: opts[:session_id], model: opts[:model]}

    :telemetry.execute([:eits, :codex, :sdk, :start], %{system_time: System.system_time()}, meta)

    cli = Keyword.get(opts, :cli_module) || Utils.codex_cli_module()
    task_supervisor = Keyword.get(opts, :task_supervisor, EyeInTheSky.TaskSupervisor)

    case spawn_handler_process(sdk_ref, to, opts[:session_id], task_supervisor) do
      {:ok, handler_pid} ->
        cli_opts =
          opts
          |> Keyword.put(:caller, handler_pid)
          |> Keyword.delete(:to)
          |> Keyword.delete(:cli_module)

        case cli_fn.(cli, prompt, cli_opts) do
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

      {:error, reason} ->
        Logger.error(
          "[telemetry] codex.sdk.error session_id=#{meta.session_id} reason=handler_start_failed #{inspect(reason)}"
        )

        {:error, {:handler_start_failed, reason}}
    end
  end

  # ---------------------------------------------------------------------------
  # Handler process
  # ---------------------------------------------------------------------------

  defp spawn_handler_process(sdk_ref, caller_pid, eits_session_id, supervisor) do
    Task.Supervisor.start_child(
      supervisor,
      fn ->
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
              accumulated_parts: [],
              eits_session_id: eits_session_id
            }

            MessageHandler.run_loop(__MODULE__, state, @loop_opts)

          {:DOWN, _ref, :process, ^caller_pid, _reason} ->
            MessageHandler.stop_and_unregister(sdk_ref)
        after
          5_000 ->
            send(caller_pid, {:claude_error, sdk_ref, :handler_timeout})
        end
      end,
      restart: :temporary
    )
  end

  # ---------------------------------------------------------------------------
  # MessageHandler behaviour implementation
  # ---------------------------------------------------------------------------

  @impl MessageHandler
  def handle_message(%Message{type: :text} = message, state) do
    %{sdk_ref: sdk_ref, caller_pid: caller_pid, accumulated_text: acc} = state
    text = message.content || ""
    new_acc = acc <> text

    new_parts =
      if text == "", do: state.accumulated_parts, else: state.accumulated_parts ++ [{:text, text}]

    send(caller_pid, {:claude_message, sdk_ref, message})
    {:continue, %{state | accumulated_text: new_acc, accumulated_parts: new_parts}}
  end

  def handle_message(
        %Message{
          type: :tool_use,
          content: %{name: name, input: input},
          metadata: metadata
        } = message,
        state
      ) do
    send(state.caller_pid, {:claude_message, state.sdk_ref, message})

    if Map.get(metadata || %{}, :partial, false) do
      {:continue, state}
    else
      summary = format_codex_tool_summary(name, input)

      new_parts =
        if summary == "",
          do: state.accumulated_parts,
          else: state.accumulated_parts ++ [{:tool, summary}]

      {:continue, %{state | accumulated_parts: new_parts}}
    end
  end

  def handle_message(message, state) do
    send(state.caller_pid, {:claude_message, state.sdk_ref, message})
    {:continue, state}
  end

  @impl MessageHandler
  def handle_result(data, state) do
    %{sdk_ref: sdk_ref, caller_pid: caller_pid, accumulated_text: acc} = state

    final_session_id = data[:session_id] || state[:session_id]
    result_text = build_result_text(state.accumulated_parts, acc)

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
    emit_completion_telemetry(final_session_id)

    MessageHandler.finalize_after_terminal_event(sdk_ref, final_session_id, @loop_opts)
    :ok
  end

  defp build_result_text(parts, acc) do
    parts_text =
      parts
      |> Enum.reduce("", fn
        {:text, text}, a ->
          a <> text

        {:tool, summary}, a ->
          prefix = if a == "" or String.ends_with?(a, "\n\n"), do: "", else: "\n\n"
          a <> prefix <> summary <> "\n\n"
      end)
      |> String.trim()

    cond do
      parts_text != "" -> parts_text
      acc != "" -> acc
      true -> nil
    end
  end

  defp emit_completion_telemetry(session_id) do
    :telemetry.execute(
      [:eits, :codex, :sdk, :complete],
      %{system_time: System.system_time()},
      %{session_id: session_id}
    )

    Logger.info("[telemetry] codex.sdk.complete session_id=#{session_id}")
  end

  @impl MessageHandler
  def on_session_id(sid, state) do
    # Notify the worker immediately so it can sync the provider_conversation_id
    send(state.caller_pid, {:codex_session_id, state.sdk_ref, sid})
    %{state | session_id: sid}
  end

  @impl MessageHandler
  def resolve_exit_session_id(state) do
    state[:session_id] || state[:eits_session_id] || ""
  end

  defp format_codex_tool_summary(name, input) do
    ToolMapper.format_codex_tool_summary(name, input)
  end
end
