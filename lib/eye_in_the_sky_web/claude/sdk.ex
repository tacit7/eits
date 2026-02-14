defmodule EyeInTheSkyWeb.Claude.SDK do
  @moduledoc """
  High-level SDK for interacting with Claude Code CLI.

  Provides streaming API that spawns Claude processes and delivers parsed messages
  to the caller. Session management is left to the caller.

  ## Usage

      # Start a new streaming session
      {:ok, ref} = SDK.start("Write hello world in Python", to: self())

      # Handle messages
      receive do
        {:claude_message, ^ref, %Message{type: :text, content: text}} ->
          IO.write(text)

        {:claude_complete, ^ref, session_id} ->
          IO.puts("\\nDone: \#{session_id}")

        {:claude_error, ^ref, reason} ->
          IO.puts("Error: \#{inspect(reason)}")
      end

      # Resume a conversation
      {:ok, ref} = SDK.resume(session_id, "Now add error handling", to: self())

  ## Messages

  The SDK sends these messages to the caller process:

    * `{:claude_message, ref, %Message{}}` - each parsed event (text deltas, tool uses, etc)
    * `{:claude_complete, ref, session_id}` - conversation completed successfully
    * `{:claude_error, ref, reason}` - error occurred during processing

  """

  alias EyeInTheSkyWeb.Claude.{CLI, Message, Parser}
  require Logger

  @type ref :: reference()
  @type opts :: keyword()

  # Agent to track running sessions for cancellation
  defmodule Registry do
    use Agent

    def start_link(_) do
      Agent.start_link(fn -> %{} end, name: __MODULE__)
    end

    def register(ref, port) do
      Agent.update(__MODULE__, &Map.put(&1, ref, port))
    end

    def lookup(ref) do
      Agent.get(__MODULE__, &Map.get(&1, ref))
    end

    def unregister(ref) do
      Agent.update(__MODULE__, &Map.delete(&1, ref))
    end
  end

  @doc """
  Start a new Claude session with streaming output.

  ## Options

  Required:
    * `:to` - pid to send messages to

  Optional (passed to CLI):
    * `:model` - model name (e.g., "sonnet", "haiku", "opus")
    * `:allowedTools` - comma-separated tool names to auto-approve
    * `:max_turns` - maximum conversation turns
    * `:permission_mode` - permission mode (see CLI module)
    * `:project_path` - working directory for Claude
    * All other CLI options supported by CLI.build_args/1

  ## Returns

    * `{:ok, ref}` - unique reference for this session
    * `{:error, reason}` - failed to start

  """
  @spec start(String.t(), opts()) :: {:ok, ref()} | {:error, term()}
  def start(prompt, opts \\ []) do
    to = Keyword.fetch!(opts, :to)
    sdk_ref = make_ref()

    # Spawn handler first so we can pass its PID to CLI
    handler_pid = spawn_handler_process(sdk_ref, to)

    cli_opts =
      opts
      |> Keyword.put(:output_format, "stream-json")
      |> Keyword.put(:verbose, true)
      |> Keyword.put(:caller, handler_pid)
      |> Keyword.delete(:to)

    case CLI.spawn_new_session(prompt, cli_opts) do
      {:ok, port, _cli_ref} ->
        Registry.register(sdk_ref, port)
        send(handler_pid, {:start_handling, sdk_ref})
        {:ok, sdk_ref}

      {:error, reason} ->
        Process.exit(handler_pid, :kill)
        {:error, reason}
    end
  end

  @doc """
  Resume an existing Claude session.

  Same as `start/2` but resumes a conversation by session_id.

  ## Options

  Required:
    * `:to` - pid to send messages to

  Optional: same as `start/2`

  """
  @spec resume(String.t(), String.t(), opts()) :: {:ok, ref()} | {:error, term()}
  def resume(session_id, prompt, opts \\ []) do
    to = Keyword.fetch!(opts, :to)
    sdk_ref = make_ref()

    # Spawn handler first so we can pass its PID to CLI
    handler_pid = spawn_handler_process(sdk_ref, to)

    cli_opts =
      opts
      |> Keyword.put(:output_format, "stream-json")
      |> Keyword.put(:verbose, true)
      |> Keyword.put(:caller, handler_pid)
      |> Keyword.delete(:to)

    case CLI.resume_session(session_id, prompt, cli_opts) do
      {:ok, port, _cli_ref} ->
        Registry.register(sdk_ref, port)
        send(handler_pid, {:start_handling, sdk_ref})
        {:ok, sdk_ref}

      {:error, reason} ->
        Process.exit(handler_pid, :kill)
        {:error, reason}
    end
  end

  @doc """
  Cancel a running Claude session.

  Closes the port and stops message delivery. The handler will send
  `{:claude_error, ref, :cancelled}` to the caller.
  """
  @spec cancel(ref()) :: :ok | {:error, :not_found}
  def cancel(ref) do
    case Registry.lookup(ref) do
      nil ->
        {:error, :not_found}

      port ->
        CLI.cancel(port)
        :ok
    end
  end

  # Spawn a handler process that will receive CLI messages
  defp spawn_handler_process(sdk_ref, caller_pid) do
    spawn_link(fn ->
      # Wait for start signal with sdk_ref
      receive do
        {:start_handling, ^sdk_ref} ->
          handle_messages(sdk_ref, caller_pid, nil)
      after
        5_000 ->
          send(caller_pid, {:claude_error, sdk_ref, :handler_timeout})
      end
    end)
  end

  # Message handler loop - receives {:claude_output, ref, line} from CLI
  defp handle_messages(sdk_ref, caller_pid, session_id) do
    receive do
      {:claude_output, _cli_ref, line} ->
        case Parser.parse_stream_line(line) do
          {:ok, message} ->
            send(caller_pid, {:claude_message, sdk_ref, message})
            handle_messages(sdk_ref, caller_pid, session_id)

          {:session_id, sid} ->
            handle_messages(sdk_ref, caller_pid, sid)

          {:complete, sid} ->
            final_session_id = sid || session_id
            send(caller_pid, {:claude_complete, sdk_ref, final_session_id})
            Registry.unregister(sdk_ref)
            :ok

          {:error, reason} ->
            send(caller_pid, {:claude_error, sdk_ref, reason})
            Registry.unregister(sdk_ref)
            :ok

          :skip ->
            handle_messages(sdk_ref, caller_pid, session_id)
        end

      {:claude_exit, _cli_ref, 0} ->
        # Normal exit - if we didn't get a complete message, send one now
        send(caller_pid, {:claude_complete, sdk_ref, session_id})
        Registry.unregister(sdk_ref)
        :ok

      {:claude_exit, _cli_ref, status} ->
        # Error exit
        reason =
          case status do
            :timeout -> :timeout
            code when is_integer(code) -> {:exit_code, code}
            other -> other
          end

        send(caller_pid, {:claude_error, sdk_ref, reason})
        Registry.unregister(sdk_ref)
        :ok
    end
  end
end
