defmodule EyeInTheSkyWeb.Claude.SessionWorker do
  use GenServer, restart: :temporary
  require Logger

  alias EyeInTheSkyWeb.Claude.Utils
  alias EyeInTheSkyWeb.Messages
  alias EyeInTheSkyWeb.Sessions

  @registry EyeInTheSkyWeb.Claude.Registry
  @max_queue_size 5

  @moduledoc """
  Persistent per-session GenServer that owns a Claude CLI port.

  Stays alive after CLI exits (idle state). Manages a message queue
  (max #{@max_queue_size}) and processes queued messages sequentially.
  Broadcasts status changes on "session:{session_id}:status".

  Registry provides O(1) lookup by session_ref or session_id.
  """

  # --- Client API ---

  def start_link(args) do
    GenServer.start_link(__MODULE__, args)
  end

  def cancel(pid) do
    GenServer.call(pid, :cancel)
  end

  def get_info(pid) do
    GenServer.call(pid, :get_info)
  end

  @doc """
  Queue a message for processing. If idle, spawns CLI immediately.
  If busy, appends to queue (max #{@max_queue_size}, drops overflow).
  """
  def queue_message(pid, prompt, opts) do
    GenServer.cast(pid, {:queue_message, prompt, opts})
  end

  # --- Server Callbacks ---

  @impl true
  def init(%{spawn_type: spawn_type, session_id: session_id, prompt: prompt, opts: opts}) do
    session_ref = Keyword.fetch!(opts, :session_ref)

    Logger.info(
      "🔧 SessionWorker.init: spawn_type=#{spawn_type}, session_id=#{session_id}, ref=#{inspect(session_ref)}"
    )

    # Register under both keys for lookup flexibility
    Registry.register(@registry, {:ref, session_ref}, session_id)
    Registry.register(@registry, {:session, session_id}, session_ref)

    # Point the handler back at this worker
    opts =
      opts
      |> Keyword.put(:caller, self())
      |> Keyword.put(:session_id, session_id)

    # Resolve integer PK from sessions table for FK references (messages, etc.)
    # Wrapped in rescue for test environments without Repo
    session_int_id = resolve_session_int_id(session_id)

    Logger.debug(
      "SessionWorker.init: resolved session_int_id=#{inspect(session_int_id)} for session_id=#{session_id}"
    )

    case spawn_cli(spawn_type, session_id, prompt, opts) do
      {:ok, port, ^session_ref} ->
        state = %{
          session_ref: session_ref,
          session_id: session_id,
          session_int_id: session_int_id,
          port: port,
          processing: true,
          queue: [],
          started_at: DateTime.utc_now(),
          output_buffer: []
        }

        Logger.info(
          "✅ SessionWorker started for #{session_id} (spawn_type=#{spawn_type}, port=#{inspect(port)})"
        )

        broadcast_status(session_id, :working)

        if session_int_id do
          Phoenix.PubSub.broadcast(
            EyeInTheSkyWeb.PubSub,
            "agent:working",
            {:agent_working, session_id, session_int_id}
          )
        end

        {:ok, state}

      {:error, reason} ->
        Logger.error(
          "❌ SessionWorker.init failed for #{session_id} (spawn_type=#{spawn_type}) - #{inspect(reason)}"
        )

        {:stop, reason}
    end
  end

  @impl true
  def handle_call(:cancel, _from, state) do
    Utils.close_port_safely(state.port)
    {:stop, :normal, :ok, state}
  end

  @impl true
  def handle_call(:get_info, _from, state) do
    info = %{
      session_ref: state.session_ref,
      session_id: state.session_id,
      started_at: state.started_at,
      queue_depth: length(state.queue),
      processing: state.processing
    }

    {:reply, info, state}
  end

  @impl true
  def handle_cast({:queue_message, prompt, opts}, state) do
    if state.processing do
      # Busy: queue or drop
      if length(state.queue) >= @max_queue_size do
        broadcast_status(state.session_id, :queue_full)
        {:noreply, state}
      else
        {:noreply, %{state | queue: state.queue ++ [{prompt, opts}]}}
      end
    else
      # Idle: spawn CLI immediately
      case spawn_next_cli(state, prompt, opts) do
        {:ok, new_state} ->
          {:noreply, new_state}

        {:error, reason} ->
          Logger.error("[#{state.session_id}] Failed to spawn CLI: #{inspect(reason)}")
          {:noreply, state}
      end
    end
  end

  @impl true
  def handle_info({:claude_output, _ref, line}, state) do
    clean_line = Utils.strip_ansi_codes(line)

    # Always log raw output at debug level so we don't miss anything
    Logger.debug("[#{state.session_id}] Raw output: #{inspect(line, limit: 500)}")

    case Jason.decode(clean_line) do
      {:ok, parsed} ->
        handle_parsed_output(parsed, state)

      {:error, reason} ->
        # Always log non-JSON output, even if empty, as it might contain error messages
        Logger.warning("⚠️  Non-JSON output from Claude [session=#{state.session_id}]:")
        Logger.warning("   Raw: #{inspect(line, limit: 500)}")
        Logger.warning("   Cleaned: #{inspect(clean_line, limit: 500)}")
        Logger.warning("   Length: #{String.length(clean_line)} chars")
        Logger.warning("   JSON decode error: #{inspect(reason)}")

        {:noreply, %{state | output_buffer: [clean_line | state.output_buffer]}}
    end
  end

  @impl true
  def handle_info({:claude_exit, _ref, exit_code}, state) do
    Logger.info("Claude CLI exited with code #{exit_code} for #{state.session_id}")

    # If exit code is non-zero and we have buffered output, show it
    if exit_code != 0 && length(state.output_buffer) > 0 do
      Logger.error(
        "❌ Claude exited with error (code #{exit_code}), #{length(state.output_buffer)} items in output buffer:"
      )

      state.output_buffer
      |> Enum.reverse()
      |> Enum.with_index()
      |> Enum.each(fn {line, idx} ->
        # Use custom_options to ensure we see full content
        Logger.error(
          "   [#{idx}] #{inspect(line, limit: :infinity, printable_limit: :infinity, width: 120)}"
        )
      end)

      # Also try to find any error messages
      errors =
        state.output_buffer
        |> Enum.filter(fn
          %{"is_error" => true} -> true
          %{"errors" => errors} when is_list(errors) and errors != [] -> true
          _ -> false
        end)

      if length(errors) > 0 do
        Logger.error("🔍 Found #{length(errors)} error messages in buffer:")

        Enum.each(errors, fn err ->
          Logger.error("   #{inspect(err, limit: :infinity, printable_limit: :infinity)}")
        end)
      end
    end

    # Broadcast completion to session topic
    if state.session_int_id do
      Phoenix.PubSub.broadcast(
        EyeInTheSkyWeb.PubSub,
        "session:#{state.session_int_id}",
        {:claude_complete, state.session_ref, exit_code}
      )
    end

    # Process next queued message or go idle
    case state.queue do
      [] ->
        broadcast_status(state.session_id, :idle)

        if state.session_int_id do
          Phoenix.PubSub.broadcast(
            EyeInTheSkyWeb.PubSub,
            "agent:working",
            {:agent_stopped, state.session_id, state.session_int_id}
          )
        end

        {:noreply, %{state | port: nil, processing: false, session_ref: nil}}

      [{prompt, opts} | rest] ->
        case spawn_next_cli(%{state | queue: rest}, prompt, opts) do
          {:ok, new_state} ->
            {:noreply, new_state}

          {:error, reason} ->
            Logger.error("[#{state.session_id}] Failed to spawn next CLI: #{inspect(reason)}")
            {:noreply, %{state | port: nil, processing: false, queue: rest, session_ref: nil}}
        end
    end
  end

  @impl true
  def handle_info({port, {:data, data}}, state) when is_port(port) do
    Logger.warning("Unexpected port data in SessionWorker: #{inspect(data)}")
    {:noreply, state}
  end

  @impl true
  def handle_info({port, {:exit_status, status}}, state) when is_port(port) do
    Logger.warning("Port exited with status #{status}")
    {:noreply, state}
  end

  @impl true
  def handle_info(msg, state) do
    Logger.debug("Unhandled message in SessionWorker: #{inspect(msg)}")
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, state) do
    if state[:session_id] do
      broadcast_status(state.session_id, :idle)
    end

    if state[:session_id] && state[:session_int_id] do
      Phoenix.PubSub.broadcast(
        EyeInTheSkyWeb.PubSub,
        "agent:working",
        {:agent_stopped, state.session_id, state.session_int_id}
      )
    end

    Utils.close_port_safely(state[:port])
    :ok
  end

  # --- Private ---

  defp resolve_session_int_id(session_id) do
    case Sessions.get_session_by_uuid(session_id) do
      {:ok, session} -> session.id
      {:error, _} -> nil
    end
  rescue
    _ -> nil
  end

  defp spawn_next_cli(state, prompt, opts) do
    session_ref = make_ref()

    # Register new ref
    Registry.register(@registry, {:ref, session_ref}, state.session_id)

    cli_opts =
      (opts || [])
      |> Keyword.put(:caller, self())
      |> Keyword.put(:session_ref, session_ref)
      |> Keyword.put(:session_id, state.session_id)

    # Determine spawn type from opts
    spawn_type = Keyword.get(opts || [], :spawn_type, :resume)

    case spawn_cli(spawn_type, state.session_id, prompt, cli_opts) do
      {:ok, port, ^session_ref} ->
        broadcast_status(state.session_id, :working)

        if state.session_int_id do
          Phoenix.PubSub.broadcast(
            EyeInTheSkyWeb.PubSub,
            "agent:working",
            {:agent_working, state.session_id, state.session_int_id}
          )
        end

        {:ok,
         %{
           state
           | port: port,
             session_ref: session_ref,
             processing: true,
             output_buffer: []
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp spawn_cli(:new, _session_id, prompt, opts) do
    Utils.cli_module().spawn_new_session(prompt, opts)
  end

  defp spawn_cli(:resume, session_id, prompt, opts) do
    Utils.cli_module().resume_session(session_id, prompt, opts)
  end

  defp broadcast_status(session_id, status) do
    Phoenix.PubSub.broadcast(
      EyeInTheSkyWeb.PubSub,
      "session:#{session_id}:status",
      {:session_status, session_id, status}
    )
  end

  # --- Output handling ---

  defp handle_parsed_output(parsed, state) when is_list(parsed) do
    {:noreply, %{state | output_buffer: [parsed | state.output_buffer]}}
  end

  defp handle_parsed_output(parsed, state) when is_map(parsed) do
    type = Map.get(parsed, "type") || Map.get(parsed, :type)
    subtype = Map.get(parsed, "subtype") || Map.get(parsed, :subtype)

    # Log all parsed output for debugging
    content =
      case type do
        "assistant" ->
          Map.get(parsed, "message", %{})
          |> Map.get("content", "")
          |> inspect()
          |> String.slice(0..200)

        "result" ->
          Map.get(parsed, "result", "") |> String.slice(0..200)

        _ ->
          ""
      end

    Logger.info("[#{state.session_id}] stream: type=#{type} subtype=#{subtype} #{content}")

    state =
      if type == "system" && subtype == "init" do
        Logger.info("📋 Init message received: #{inspect(parsed)}")
        claude_session_id = Map.get(parsed, "session_id") || Map.get(parsed, :session_id)

        if claude_session_id && state.session_int_id do
          Logger.info(
            "🔄 Updating session #{state.session_int_id} with Claude session_id: #{claude_session_id}"
          )

          case Sessions.get_session(state.session_int_id) do
            {:ok, agent} ->
              case Sessions.update_session(agent, %{uuid: claude_session_id}) do
                {:ok, _updated} ->
                  Logger.info(
                    "✅ Session UUID updated: #{state.session_id} -> #{claude_session_id}"
                  )

                  %{state | session_id: claude_session_id}

                {:error, reason} ->
                  Logger.error("❌ Failed to update session UUID: #{inspect(reason)}")
                  state
              end

            {:error, reason} ->
              Logger.error("❌ Failed to load session for UUID update: #{inspect(reason)}")
              state
          end
        else
          Logger.info("✅ Claude init confirmed for session #{state.session_id}")
          state
        end
      else
        state
      end

    # Check for session not found error
    is_error = Map.get(parsed, "is_error") || Map.get(parsed, :is_error)
    errors = Map.get(parsed, "errors") || Map.get(parsed, :errors) || []

    if is_error && Enum.any?(errors, &String.contains?(&1, "No conversation found")) do
      Logger.error(
        "❌ Session not found for session_id=#{state.session_id}, session_int_id=#{state.session_int_id}, errors=#{inspect(errors)} - stopping worker"
      )

      {:stop, :session_not_found, state}
    else
      maybe_record_result(parsed, type, state)

      updated_buffer = [parsed | state.output_buffer]

      if state.session_int_id do
        Phoenix.PubSub.broadcast(
          EyeInTheSkyWeb.PubSub,
          "session:#{state.session_int_id}",
          {:claude_response, state.session_ref, parsed}
        )
      end

      {:noreply, %{state | output_buffer: updated_buffer}}
    end
  end

  defp maybe_record_result(parsed, "result", state) do
    result = Map.get(parsed, "result") || Map.get(parsed, :result)

    if result && is_binary(result) && state.session_int_id do
      message_uuid = Map.get(parsed, "uuid") || Map.get(parsed, :uuid)

      metadata = %{
        stream_type: "result",
        duration_ms: Map.get(parsed, "duration_ms") || Map.get(parsed, :duration_ms),
        duration_api_ms: Map.get(parsed, "duration_api_ms") || Map.get(parsed, :duration_api_ms),
        num_turns: Map.get(parsed, "num_turns") || Map.get(parsed, :num_turns),
        total_cost_usd: Map.get(parsed, "total_cost_usd") || Map.get(parsed, :total_cost_usd),
        usage: Map.get(parsed, "usage") || Map.get(parsed, :usage),
        model_usage: Map.get(parsed, "modelUsage") || Map.get(parsed, :modelUsage),
        is_error: Map.get(parsed, "is_error") || Map.get(parsed, :is_error)
      }

      opts = [source_uuid: message_uuid, metadata: metadata]

      case Messages.record_incoming_reply(state.session_int_id, "claude", result, opts) do
        {:ok, _message} ->
          Logger.info("Recorded result for session #{state.session_id}")

        {:error, reason} ->
          Logger.error("Failed to record result for #{state.session_id}: #{inspect(reason)}")
      end
    end
  end

  defp maybe_record_result(parsed, "assistant", state) do
    if state.session_int_id do
      message = Map.get(parsed, "message") || Map.get(parsed, :message) || %{}
      content_blocks = Map.get(message, "content") || Map.get(message, :content) || []
      message_uuid = Map.get(parsed, "uuid") || Map.get(parsed, :uuid)

      thinking_text =
        content_blocks
        |> Enum.filter(fn block ->
          (Map.get(block, "type") || Map.get(block, :type)) == "thinking"
        end)
        |> Enum.map(fn block ->
          Map.get(block, "thinking") || Map.get(block, :thinking) || ""
        end)
        |> Enum.reject(&(&1 == ""))
        |> Enum.join("\n\n")

      Enum.each(content_blocks, fn block ->
        block_type = Map.get(block, "type") || Map.get(block, :type)

        case block_type do
          "text" ->
            text = Map.get(block, "text") || Map.get(block, :text) || ""

            if String.trim(text) != "" do
              metadata =
                if thinking_text != "" do
                  %{stream_type: "assistant", thinking: thinking_text}
                else
                  %{stream_type: "assistant"}
                end

              record_stream_message(state, "assistant", text, metadata, message_uuid)
            end

          "tool_use" ->
            tool_name = Map.get(block, "name") || Map.get(block, :name) || "unknown"
            tool_id = Map.get(block, "id") || Map.get(block, :id)
            input = Map.get(block, "input") || Map.get(block, :input) || %{}

            body = "Tool: #{tool_name}\n#{Jason.encode!(input, pretty: true)}"

            metadata = %{
              stream_type: "tool_use",
              tool_name: tool_name,
              tool_id: tool_id,
              input: input
            }

            record_stream_message(state, "tool", body, metadata, message_uuid)

          _ ->
            :ok
        end
      end)
    end
  end

  defp maybe_record_result(parsed, "user", state) do
    if state.session_int_id do
      content_blocks = Map.get(parsed, "message") || Map.get(parsed, :message) || %{}
      content = Map.get(content_blocks, "content") || Map.get(content_blocks, :content) || []
      message_uuid = Map.get(parsed, "uuid") || Map.get(parsed, :uuid)

      Enum.each(content, fn block ->
        block_type = Map.get(block, "type") || Map.get(block, :type)

        if block_type == "tool_result" do
          tool_id = Map.get(block, "tool_use_id") || Map.get(block, :tool_use_id)
          result_content = Map.get(block, "content") || Map.get(block, :content) || ""

          body =
            if is_binary(result_content), do: result_content, else: Jason.encode!(result_content)

          body = String.slice(body, 0..4000)

          metadata = %{stream_type: "tool_result", tool_use_id: tool_id}
          record_stream_message(state, "tool", body, metadata, message_uuid)
        end
      end)
    end
  end

  defp maybe_record_result(_parsed, _type, _state), do: :ok

  defp record_stream_message(state, sender_role, body, metadata, source_uuid) do
    attrs = %{
      uuid: Ecto.UUID.generate(),
      session_id: state.session_int_id,
      sender_role: sender_role,
      recipient_role: "user",
      provider: "claude",
      direction: "inbound",
      body: body,
      status: "delivered",
      source_uuid: source_uuid,
      metadata: metadata
    }

    # Use record_incoming_reply if we have source_uuid for deduplication
    result =
      if source_uuid do
        Messages.record_incoming_reply(state.session_int_id, "claude", body,
          source_uuid: source_uuid,
          metadata: Map.put(metadata, :sender_role, sender_role)
        )
      else
        Messages.create_message(attrs)
      end

    case result do
      {:ok, _msg} ->
        :ok

      {:error, reason} ->
        Logger.warning(
          "[#{state.session_id}] Failed to save #{sender_role} message: #{inspect(reason)}"
        )
    end
  end
end
