defmodule EyeInTheSkyWeb.Claude.SessionManager do
  @moduledoc """
  Manages multiple Claude CLI subprocess sessions.

  Tracks running processes, routes output to correct LiveView sessions,
  and handles process cleanup.
  """

  use GenServer
  require Logger

  alias EyeInTheSkyWeb.Claude.CLI
  alias EyeInTheSkyWeb.Messages
  alias EyeInTheSkyWeb.NATS.Publisher

  # Client API

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Starts a new Claude CLI session.

  Returns `{:ok, session_ref}` which should be used to identify this session.
  """
  def start_session(session_id, prompt, opts \\ []) do
    GenServer.call(__MODULE__, {:start_session, session_id, prompt, opts})
  end

  @doc """
  Continues an existing Claude session.
  """
  def continue_session(session_id, prompt, opts \\ []) do
    GenServer.call(__MODULE__, {:continue_session, session_id, prompt, opts})
  end

  @doc """
  Resumes a specific Claude session by session ID.
  """
  def resume_session(session_id, prompt, opts \\ []) do
    GenServer.call(__MODULE__, {:resume_session, session_id, prompt, opts})
  end

  @doc """
  Cancels a running Claude session.
  """
  def cancel_session(session_ref) do
    GenServer.call(__MODULE__, {:cancel_session, session_ref})
  end

  @doc """
  Lists all active sessions.
  """
  def list_sessions do
    GenServer.call(__MODULE__, :list_sessions)
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    # State: %{session_ref => %{port, session_id, started_at, output_buffer}}
    {:ok, %{}}
  end

  @impl true
  def handle_call({:start_session, session_id, prompt, opts}, _from, state) do
    # Add this GenServer as the caller and pass session_id so Claude uses it
    opts =
      opts
      |> Keyword.put(:caller, self())
      |> Keyword.put(:session_id, session_id)

    case CLI.spawn_new_session(prompt, opts) do
      {:ok, port, session_ref} ->
        session_info = %{
          port: port,
          session_id: session_id,
          started_at: DateTime.utc_now(),
          output_buffer: []
        }

        new_state = Map.put(state, session_ref, session_info)

        Logger.info("Started Claude CLI session #{inspect(session_ref)} with ID #{session_id}")

        {:reply, {:ok, session_ref}, new_state}

      {:error, reason} ->
        Logger.error("Failed to start Claude CLI: #{inspect(reason)}")
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:continue_session, session_id, prompt, opts}, _from, state) do
    opts =
      opts
      |> Keyword.put(:caller, self())
      |> Keyword.put(:session_id, session_id)

    case CLI.continue_session(prompt, opts) do
      {:ok, port, session_ref} ->
        session_info = %{
          port: port,
          session_id: session_id,
          started_at: DateTime.utc_now(),
          output_buffer: []
        }

        new_state = Map.put(state, session_ref, session_info)

        {:reply, {:ok, session_ref}, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:resume_session, session_id, prompt, opts}, _from, state) do
    # session_id is now the unified ID (same as Claude's session ID)
    opts = Keyword.put(opts, :caller, self())

    case CLI.resume_session(session_id, prompt, opts) do
      {:ok, port, session_ref} ->
        session_info = %{
          port: port,
          session_id: session_id,
          started_at: DateTime.utc_now(),
          output_buffer: []
        }

        new_state = Map.put(state, session_ref, session_info)

        Logger.info("Resumed Claude CLI session #{session_id} (ref: #{inspect(session_ref)})")

        {:reply, {:ok, session_ref}, new_state}

      {:error, reason} ->
        Logger.error("Failed to resume Claude CLI session #{session_id}: #{inspect(reason)}")

        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:cancel_session, session_ref}, _from, state) do
    case Map.get(state, session_ref) do
      nil ->
        {:reply, {:error, :not_found}, state}

      session_info ->
        CLI.cancel(session_info.port)
        new_state = Map.delete(state, session_ref)

        Logger.info("Cancelled Claude CLI session #{inspect(session_ref)}")

        {:reply, :ok, new_state}
    end
  end

  @impl true
  def handle_call(:list_sessions, _from, state) do
    sessions =
      Enum.map(state, fn {ref, info} ->
        %{
          session_ref: ref,
          session_id: info.session_id,
          started_at: info.started_at,
          output_lines: length(info.output_buffer)
        }
      end)

    {:reply, sessions, state}
  end

  @impl true
  def handle_info({:claude_output, session_ref, line}, state) do
    case Map.get(state, session_ref) do
      nil ->
        Logger.warning("Received output for unknown session_ref: #{inspect(session_ref)}")
        {:noreply, state}

      session_info ->
        Logger.debug("📥 RAW CLAUDE LINE: #{line}")

        # Parse the JSON line
        case Jason.decode(line) do
          {:ok, parsed} ->
            handle_parsed_output(session_ref, session_info, parsed, state)

          {:error, reason} ->
            # Not JSON, just buffer it
            Logger.warning("⚠️  FAILED TO PARSE JSON: #{inspect(reason)} - Line: #{line}")
            updated_info = update_in(session_info.output_buffer, &[line | &1])
            {:noreply, Map.put(state, session_ref, updated_info)}
        end
    end
  end

  @impl true
  def handle_info({:claude_exit, session_ref, exit_code}, state) do
    case Map.get(state, session_ref) do
      nil ->
        {:noreply, state}

      session_info ->
        Logger.info("Claude CLI session #{inspect(session_ref)} exited with code #{exit_code}")

        # Broadcast completion to LiveView (both old and new topics for compatibility)
        Phoenix.PubSub.broadcast(
          EyeInTheSkyWeb.PubSub,
          "session:#{session_info.session_id}",
          {:claude_complete, session_ref, exit_code}
        )

        # Clean up
        new_state = Map.delete(state, session_ref)
        {:noreply, new_state}
    end
  end

  @impl true
  def handle_info({port, {:data, data}}, state) when is_port(port) do
    # Port message leaked through - this shouldn't happen but handle gracefully
    Logger.warning("Unexpected port data received directly in SessionManager: #{inspect(data)}")
    {:noreply, state}
  end

  @impl true
  def handle_info({port, {:exit_status, status}}, state) when is_port(port) do
    # Port exit leaked through - log it
    Logger.warning("Port exited with status #{status}")
    {:noreply, state}
  end

  @impl true
  def handle_info(msg, state) do
    # Catch-all for unexpected messages
    Logger.debug("Unhandled message in SessionManager: #{inspect(msg)}")
    {:noreply, state}
  end

  # Private Helpers

  defp handle_parsed_output(session_ref, session_info, parsed, state) do
    # DEBUG: Log all parsed messages to understand Claude's output format
    Logger.info("🔍 PARSED CLAUDE OUTPUT: #{inspect(parsed, pretty: true)}")

    # Log init message for debugging (session ID is now unified, no need to store)
    if parsed["type"] == "system" && parsed["subtype"] == "init" do
      Logger.info("Claude init confirmed for session #{session_info.session_id}")
    end

    # Handle assistant messages - check multiple possible field structures
    if parsed["type"] == "assistant" || parsed["role"] == "assistant" do
      # Extract text from Claude's content array structure
      content = extract_text_content(parsed)

      Logger.info("🤖 ASSISTANT MESSAGE DETECTED - Content: #{inspect(content)}")

      # Create inbound message in database (async to avoid blocking GenServer)
      if content && is_binary(content) do
        session_id = session_info.session_id

        Task.start(fn ->
          case Messages.record_incoming_reply(session_id, "claude", content) do
            {:ok, message} ->
              Publisher.publish_message(message)

              Logger.info(
                "✅ Recorded and published assistant message for session #{session_id}"
              )

            {:error, reason} ->
              Logger.error(
                "❌ Failed to record assistant message for session #{session_id}: #{inspect(reason)}"
              )
          end
        end)
      else
        Logger.warning("⚠️  ASSISTANT MESSAGE BUT NO VALID TEXT CONTENT: #{inspect(parsed)}")
      end
    end

    # Buffer the output
    updated_info = %{session_info | output_buffer: [parsed | session_info.output_buffer]}

    # Broadcast to LiveView - use :claude_response to match dm_live.ex expectations
    Phoenix.PubSub.broadcast(
      EyeInTheSkyWeb.PubSub,
      "session:#{session_info.session_id}",
      {:claude_response, session_ref, parsed}
    )

    {:noreply, Map.put(state, session_ref, updated_info)}
  end

  # Extract text content from Claude's response structure
  # Claude returns: {"message": {"content": [{"type": "text", "text": "actual message"}]}}
  defp extract_text_content(parsed) do
    cond do
      # Check if there's a "message" wrapper with "content" array
      message = parsed["message"] ->
        extract_from_content_array(message["content"])

      # Check if "content" is directly in parsed
      content = parsed["content"] ->
        extract_from_content_array(content)

      # Fallback to old structure checks
      true ->
        parsed["text"] || parsed["body"]
    end
  end

  defp extract_from_content_array(content) when is_list(content) do
    # Find all text blocks and tool_use blocks, combine them
    content
    |> Enum.map(fn item ->
      case item do
        %{"type" => "text", "text" => text} ->
          text

        %{"type" => "tool_use", "name" => name, "input" => input} ->
          # Format tool use as readable text
          "Using #{name} with #{inspect(input)}"

        _ ->
          nil
      end
    end)
    |> Enum.filter(&(&1 != nil))
    |> Enum.join("\n")
    |> case do
      "" -> nil
      text -> text
    end
  end

  defp extract_from_content_array(_), do: nil
end
