defmodule EyeInTheSky.Pi.SDK do
  @moduledoc """
  EITS MessageHandler adapter for the Pi harness (NOT the upstream Pi SDK).

  Owns request ids, pending-request bookkeeping, preamble sequencing, and
  the protocol verbs abort/dispose. Transport lives in Pi.CLI.

  ## Preamble state machine

      :initializing --init response ok (protocolVersion==1)--> send start_session --> :starting
      :starting     --start_session response ok AND ready seen (either order)--> send prompt --> :streaming
      :streaming    --{:result, data} (turn_end)--> handle_result: dispose, complete/fail
      any phase     --failed initialize/start_session/prompt envelope--> {:halt, {:pi_preamble_failed, command, error}}
      (failed mid-turn verbs — deny_tool/dispose/abort — are logged, never fatal)

  ## Terminal exactly-once

  `state.terminal` (nil | :completed | :failed | :canceled) guards every path
  that would emit `{:claude_complete, ...}` or `{:claude_error, ...}` from
  a terminal event so exactly one terminal message reaches the caller.

  Cancel emits `{:claude_error, ref, :user_canceled}` on the terminal path.
  `ErrorClassifier.classify(:user_canceled)` returns `:user_canceled`
  (systemic → no retry) so a user cancel is never re-run.
  """

  use EyeInTheSky.SDK.MessageHandler

  alias EyeInTheSky.Claude.Message
  alias EyeInTheSky.Claude.SDK.Registry
  alias EyeInTheSky.Claude.Utils
  alias EyeInTheSky.SDK.MessageHandler

  require Logger

  @protocol_version 1
  @cancel_grace_ms 3_000

  @loop_opts [
    parser: EyeInTheSky.Pi.Parser,
    telemetry_prefix: [:eits, :pi, :sdk],
    log_raw_key: "log_pi_raw",
    log_raw_prefix: "pi.raw"
  ]

  @doc false
  def loop_opts, do: @loop_opts

  @doc "Returns the configured Pi CLI transport module (real or mock for tests)."
  def cli_module, do: Utils.pi_cli_module()

  # -- Public API (same contract as Codex.SDK) ---------------------------------

  @doc "Start a new Pi session."
  @spec start(String.t(), keyword()) :: {:ok, reference(), pid()} | {:error, term()}
  def start(prompt, opts \\ []), do: run_session(prompt, opts)

  @doc """
  Resume an existing Pi session.

  Resume is identical to start — the sessionDir (keyed by :session_id) carries
  continuity. Signature parity with Codex.SDK.resume/3.
  """
  @spec resume(String.t(), String.t(), keyword()) :: {:ok, reference(), pid()} | {:error, term()}
  def resume(_session_id, prompt, opts \\ []), do: run_session(prompt, opts)

  @doc """
  Cancel a running Pi session (protocol abort → 3 s grace → transport kill).

  Marks the ref as canceled (Registry marker entry) so the handler reports the
  terminal outcome as `:user_canceled` — never a retryable-looking exit error —
  regardless of whether the harness ends the turn via `turn_end`, a clean
  exit, or the grace-timeout kill.
  """
  @spec cancel(reference()) :: :ok | {:error, :not_found}
  def cancel(ref) do
    case Registry.lookup(ref) do
      nil ->
        {:error, :not_found}

      port when is_port(port) ->
        mark_canceled(ref)
        cli_module().send_ndjson(port, %{id: "pi-cancel", type: "abort"})

        Task.start(fn ->
          Process.sleep(@cancel_grace_ms)
          if Port.info(port), do: cli_module().cancel(port)
        end)

        :ok

      pid when is_pid(pid) ->
        mark_canceled(ref)
        send(pid, :cancel)
        :ok
    end
  end

  # Cancel marker lives in the shared Registry ETS table under a derived key.
  # Consumed (deleted) by every terminal path; a handler killed via :DOWN can
  # leak one row, which is bounded and harmless.
  defp mark_canceled(ref), do: Registry.register({ref, :pi_canceled}, true)

  defp canceled?(ref), do: Registry.lookup({ref, :pi_canceled}) != nil

  defp consume_cancel_marker(ref) do
    canceled = canceled?(ref)
    Registry.unregister({ref, :pi_canceled})
    canceled
  end

  # -- Session bootstrap -------------------------------------------------------

  defp run_session(prompt, opts) do
    sdk_ref = make_ref()
    to = Keyword.fetch!(opts, :to)
    task_supervisor = Keyword.get(opts, :task_supervisor, EyeInTheSky.TaskSupervisor)
    cli = cli_module()

    Logger.info("[telemetry] pi.sdk.start session_id=#{opts[:session_id]} model=#{opts[:model]}")

    :telemetry.execute([:eits, :pi, :sdk, :start], %{system_time: System.system_time()}, %{
      session_id: opts[:session_id],
      model: opts[:model]
    })

    case spawn_handler_process(sdk_ref, to, prompt, opts, task_supervisor) do
      {:ok, handler_pid} ->
        cli_opts =
          opts
          |> Keyword.put(:caller, handler_pid)
          |> Keyword.delete(:to)

        case cli.spawn_harness(cli_opts) do
          {:ok, port, _cli_ref} ->
            Registry.register(sdk_ref, port)
            send(handler_pid, {:start_handling, sdk_ref, port})
            {:ok, sdk_ref, handler_pid}

          {:error, reason} ->
            Logger.error(
              "[telemetry] pi.sdk.error session_id=#{opts[:session_id]} reason=#{inspect(reason)}"
            )

            Process.exit(handler_pid, :kill)
            {:error, reason}
        end

      {:error, reason} ->
        {:error, {:handler_start_failed, reason}}
    end
  end

  defp spawn_handler_process(sdk_ref, caller_pid, prompt, opts, supervisor) do
    Task.Supervisor.start_child(
      supervisor,
      fn ->
        Process.monitor(caller_pid)

        receive do
          {:start_handling, ^sdk_ref, port} ->
            state =
              initial_state(sdk_ref, caller_pid, Keyword.put(opts, :prompt, prompt))
              |> Map.put(:port, port)
              |> send_request("initialize", %{
                type: "initialize",
                protocolVersion: @protocol_version
              })

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

  @doc false
  def initial_state(sdk_ref, caller_pid, opts) do
    %{
      sdk_ref: sdk_ref,
      caller_pid: caller_pid,
      session_id: opts[:session_id],
      eits_session_id: opts[:session_id],
      phase: :initializing,
      port: nil,
      pending: %{},
      next_id: 1,
      turn_end_seen: false,
      sticky_error: nil,
      ready_seen: false,
      start_session_acked: false,
      terminal: nil,
      accumulated_text: "",
      prompt: opts[:prompt],
      start_session_payload: start_session_payload(opts)
    }
  end

  defp start_session_payload(opts) do
    session_dir =
      case opts[:session_id] do
        sid when is_binary(sid) and sid != "" -> EyeInTheSky.Pi.session_dir(sid)
        _ -> nil
      end

    %{
      type: "start_session",
      cwd: opts[:project_path] || File.cwd!(),
      sessionId: opts[:session_id],
      sessionDir: session_dir,
      model: opts[:model],
      allowedTools: opts[:allowed_tools] || ["*"],
      customInstructions: opts[:custom_instructions]
    }
  end

  defp send_request(state, command, payload) do
    id = "pi-#{state.next_id}"
    cli_module().send_ndjson(state.port, Map.put(payload, :id, id))

    %{state | next_id: state.next_id + 1, pending: Map.put(state.pending, id, command)}
  end

  # -- MessageHandler callbacks ------------------------------------------------

  @impl MessageHandler
  def handle_message(%Message{type: :text, content: text} = msg, state) when is_binary(text) do
    send(state.caller_pid, {:claude_message, state.sdk_ref, msg})
    {:continue, %{state | accumulated_text: state.accumulated_text <> text}}
  end

  def handle_message(%Message{} = msg, state) do
    send(state.caller_pid, {:claude_message, state.sdk_ref, msg})
    {:continue, state}
  end

  @impl MessageHandler
  def handle_protocol_event(%{"type" => "response", "id" => id} = event, state) do
    {command, remaining} = Map.pop(state.pending, id)
    state = %{state | pending: remaining}

    cond do
      is_nil(command) ->
        Logger.warning("[Pi.SDK] response for unknown id=#{id}, ignoring")
        {:continue, state}

      # Failed initialize/start_session/prompt envelopes fail the turn
      # immediately — in ANY phase. A failed prompt response can arrive after
      # streaming noise and must still kill the turn (spec §2 invariants).
      event["success"] == false and command in ~w(initialize start_session prompt) ->
        {:halt, {:pi_preamble_failed, command, event["error"]}}

      # Failed mid-turn verbs (deny_tool, dispose, abort) must not kill a
      # turn that is otherwise streaming fine.
      event["success"] == false ->
        Logger.warning("[Pi.SDK] #{command} request failed: #{inspect(event["error"])}")
        {:continue, state}

      true ->
        advance_phase(command, event["data"] || %{}, state)
    end
  end

  def handle_protocol_event(%{"type" => "ready"} = event, state) do
    expected = state.eits_session_id
    got = event["sessionId"]

    # The ready event must echo OUR session id (the harness persists the
    # transcript under it). A mismatch means the wrong transcript lineage —
    # fail before prompt is ever sent. Skipped when no session id was
    # requested (in-memory session).
    if is_binary(expected) and expected != "" and got != expected do
      {:halt, {:pi_session_mismatch, expected: expected, got: got}}
    else
      advance_phase("ready", nil, %{state | ready_seen: true})
    end
  end

  def handle_protocol_event(%{"type" => "turn_error"} = event, state) do
    msg = event["error"] || event["message"] || "turn_error"
    {:continue, %{state | sticky_error: msg}}
  end

  def handle_protocol_event(%{"type" => "tool_request"} = event, state) do
    req_id = event["requestId"] || event["id"]

    state = send_request(state, "deny_tool", %{type: "deny_tool", requestId: req_id})

    status_msg =
      Message.text(
        "Pi requested tool approval — approvals are not enabled; denied (configure bypassPermissions)",
        false
      )

    send(state.caller_pid, {:claude_message, state.sdk_ref, status_msg})

    {:continue, state}
  end

  def handle_protocol_event(%{"type" => "exit"} = event, state) do
    # Diagnostic. OS port exit is authoritative — but if turn_end never came,
    # stash so on_clean_exit knows.
    if state.turn_end_seen do
      {:continue, state}
    else
      msg = event["error"] || event["message"] || "harness exit"
      {:continue, %{state | sticky_error: state.sticky_error || msg}}
    end
  end

  def handle_protocol_event(_event, state), do: {:continue, state}

  @impl MessageHandler
  def handle_result(data, state) do
    state = %{state | turn_end_seen: true}

    if state.terminal do
      # Exactly-once: already emitted a terminal message.
      :ok
    else
      finalize_terminal(data, state)
    end
  end

  @impl MessageHandler
  def on_clean_exit(state) do
    cond do
      state.terminal == :canceled or consume_cancel_marker(state.sdk_ref) ->
        {:error, :user_canceled}

      state.terminal == :completed ->
        {:complete, state.eits_session_id}

      state.terminal == :failed ->
        {:error, state.sticky_error || :exit_before_turn_end}

      state.turn_end_seen and is_nil(state.sticky_error) ->
        {:complete, state.eits_session_id}

      not is_nil(state.sticky_error) ->
        {:error, {:pi_turn_error, state.sticky_error}}

      true ->
        {:error, :exit_before_turn_end}
    end
  end

  @impl MessageHandler
  def on_abnormal_exit(status, state) do
    if state.terminal == :canceled or consume_cancel_marker(state.sdk_ref) do
      {:error, :user_canceled}
    else
      {:error, MessageHandler.default_exit_reason(status)}
    end
  end

  # Every stream-error / halt terminal path routes through here so the cancel
  # marker is consumed exactly once and post-cancel errors surface as the
  # non-retryable :user_canceled reason. Without this, a harness `error` event
  # after cancel produced a {:pi_error, ...} that ErrorClassifier mapped to
  # :transient → retry, AND the Registry marker leaked (never consumed).
  @impl MessageHandler
  def on_stream_error(reason, state) do
    if state.terminal == :canceled or consume_cancel_marker(state.sdk_ref) do
      {:error, :user_canceled}
    else
      {:error, reason}
    end
  end

  # -- Phase transitions -------------------------------------------------------

  defp advance_phase("initialize", data, %{phase: :initializing} = state) do
    case data["protocolVersion"] do
      @protocol_version ->
        new_state =
          %{state | phase: :starting}
          |> send_request("start_session", state.start_session_payload)

        {:continue, new_state}

      other ->
        {:halt, {:pi_protocol_version_mismatch, other}}
    end
  end

  defp advance_phase("start_session", _data, %{phase: :starting} = state) do
    maybe_send_prompt(%{state | start_session_acked: true})
  end

  defp advance_phase("ready", _data, state), do: maybe_send_prompt(state)

  defp advance_phase("dispose", _data, state), do: {:continue, state}

  defp advance_phase(_cmd, _data, state), do: {:continue, state}

  defp maybe_send_prompt(state) do
    if state.phase == :starting and state.start_session_acked and state.ready_seen do
      new_state =
        %{state | phase: :streaming}
        |> send_request("prompt", %{type: "prompt", prompt: state.prompt})

      {:continue, new_state}
    else
      {:continue, state}
    end
  end

  # -- Terminal handling -------------------------------------------------------

  defp finalize_terminal(data, state) do
    %{sdk_ref: sdk_ref, caller_pid: caller_pid, eits_session_id: eits_session_id} = state
    sticky = state.sticky_error || data[:error]

    canceled = consume_cancel_marker(sdk_ref)

    if canceled do
      # User cancel: the abort produced a turn_end, but the outcome is
      # terminal :canceled — never completed, never a retryable error shape.
      state = %{state | terminal: :canceled}
      log_usage("pi.sdk.canceled", eits_session_id, data)
      send(caller_pid, {:claude_error, sdk_ref, :user_canceled})
      after_terminal(state, data)
    else
      finalize_uncanceled(data, state, sticky)
    end
  end

  defp finalize_uncanceled(data, state, sticky) do
    %{sdk_ref: sdk_ref, caller_pid: caller_pid, eits_session_id: eits_session_id} = state

    if sticky do
      state = %{state | terminal: :failed, sticky_error: sticky}
      log_usage("pi.sdk.turn_error", eits_session_id, data)
      send(caller_pid, {:claude_error, sdk_ref, {:pi_turn_error, sticky}})
      after_terminal(state, data)
    else
      state = %{state | terminal: :completed}

      metadata = %{
        session_id: eits_session_id,
        usage: data[:usage],
        input_tokens: data[:input_tokens],
        output_tokens: data[:output_tokens],
        total_cost_usd: data[:total_cost_usd],
        duration_ms: data[:duration_ms]
      }

      # turn_end carries usage only — the persisted result text comes from the
      # deltas accumulated during the turn (Codex.SDK does the same for its
      # text-less turn.completed). nil text would persist an empty message.
      result_text =
        case String.trim(state.accumulated_text) do
          "" -> nil
          text -> text
        end

      result_msg = Message.result(result_text, metadata)
      send(caller_pid, {:claude_message, sdk_ref, result_msg})
      send(caller_pid, {:claude_complete, sdk_ref, eits_session_id})

      :telemetry.execute(
        [:eits, :pi, :sdk, :complete],
        %{
          input_tokens: data[:input_tokens] || 0,
          output_tokens: data[:output_tokens] || 0
        },
        %{session_id: eits_session_id}
      )

      Logger.info("[telemetry] pi.sdk.complete session_id=#{eits_session_id}")

      after_terminal(state, data)
    end
  end

  defp after_terminal(state, _data) do
    # Best-effort protocol dispose. Ignore result — the harness may already be gone.
    _ = send_request(state, "dispose", %{type: "dispose"})
    MessageHandler.finalize_after_terminal_event(state.sdk_ref, state.eits_session_id, @loop_opts)
    :ok
  end

  defp log_usage(label, session_id, data) do
    Logger.info(
      "[telemetry] #{label} session_id=#{session_id} input=#{data[:input_tokens] || 0} output=#{data[:output_tokens] || 0}"
    )
  end
end
