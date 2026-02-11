defmodule EyeInTheSkyWeb.Claude.CLI do
  @moduledoc """
  Claude CLI subprocess spawner - spawns fresh Claude Code instances like opcode does.

  Spawns `claude` binary as a subprocess with `-p "message"` flag and streams
  stdout/stderr back to the caller via message passing.
  """

  require Logger

  @doc """
  Spawns a new Claude Code session with a user prompt.

  ## Options
    * `:model` - Model to use ("sonnet", "opus", "haiku"). Default: "sonnet"
    * `:project_path` - Working directory for Claude. Default: current directory
    * `:output_format` - Output format. Default: "stream-json"
    * `:skip_permissions` - Skip permission prompts. Default: true
    * `:caller` - PID to send output to. Default: self()

  ## Returns
    * `{:ok, port, session_ref}` - Port handle and session reference
    * `{:error, reason}` - If Claude binary not found or spawn failed

  ## Messages Sent to Caller
    * `{:claude_output, session_ref, line}` - Each line of stdout
    * `{:claude_error, session_ref, line}` - Each line of stderr
    * `{:claude_exit, session_ref, exit_code}` - Process exited
  """
  def spawn_new_session(prompt, opts \\ []) do
    model = Keyword.get(opts, :model, "sonnet")
    project_path = Keyword.get(opts, :project_path, File.cwd!())
    output_format = Keyword.get(opts, :output_format, "stream-json")
    skip_permissions = Keyword.get(opts, :skip_permissions, true)
    caller = Keyword.get(opts, :caller, self())
    session_id = Keyword.get(opts, :session_id)

    # Find claude binary
    case find_claude_binary() do
      {:ok, claude_path} ->
        # Build command args like opcode does
        base_args = build_args(prompt, model, output_format, skip_permissions)

        # If session_id provided, pass --session-id to Claude so it uses our ID
        args =
          if session_id do
            ["--session-id", session_id] ++ base_args
          else
            base_args
          end

        require Logger

        if session_id do
          Logger.debug("Spawning new Claude session with ID #{session_id} in #{project_path}")
        else
          Logger.debug("Spawning new Claude session in #{project_path}")
        end

        session_ref = Keyword.get(opts, :session_ref, make_ref())

        # Spawn output handler first
        handler_pid =
          spawn_link(fn ->
            receive do
              {:port, port} ->
                handle_port_output(port, session_ref, caller)
            end
          end)

        # Spawn Claude directly with line-buffered output
        port =
          Port.open(
            {:spawn_executable, claude_path},
            [
              :binary,
              :exit_status,
              :use_stdio,
              :stderr_to_stdout,
              {:line, 65536},
              {:args, args},
              {:cd, project_path},
              {:env, build_env()}
            ]
          )

        # Connect port to handler
        Port.connect(port, handler_pid)
        send(handler_pid, {:port, port})

        {:ok, port, session_ref}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Spawns a channel agent with tracked session-id and agent-id.

  Uses: claude --dangerously-skip-permissions --session-id UUID "session-id UUID agent-id UUID" -p "instructions"

  ## Options
    * `:model` - Model to use. Default: "sonnet"
    * `:project_path` - Working directory. Default: current directory
    * `:channel_id` - Channel ID for routing messages
    * `:prompt_name` - Name of the prompt template used (optional)
    * `:caller` - PID to send output to. Default: self()
  """
  def spawn_channel_agent(session_id, agent_id, instructions, opts \\ []) do
    model = Keyword.get(opts, :model, "sonnet")
    project_path = Keyword.get(opts, :project_path, File.cwd!())
    channel_id = Keyword.get(opts, :channel_id)
    prompt_name = Keyword.get(opts, :prompt_name)
    caller = Keyword.get(opts, :caller, self())

    case find_claude_binary() do
      {:ok, claude_path} ->
        # Build description with session-id and agent-id
        description = "session-id #{session_id} agent-id #{agent_id}"

        # Build initialization prompt with Eye in the Sky MCP call
        init_prompt = build_init_prompt(session_id, agent_id, prompt_name, instructions)

        # Build args: --dangerously-skip-permissions --session-id UUID "description" -p "init_prompt"
        args = [
          "--dangerously-skip-permissions",
          "--session-id",
          session_id,
          description,
          "-p",
          init_prompt,
          "--model",
          model,
          "--output-format",
          "stream-json",
          "--verbose"
        ]

        require Logger

        Logger.debug(
          "Spawning channel agent session=#{session_id} channel=#{channel_id} in #{project_path}"
        )

        session_ref = Keyword.get(opts, :session_ref, make_ref())

        # Spawn output handler with channel_id context and line buffer
        handler_pid =
          spawn_link(fn ->
            receive do
              {:port, port} ->
                handle_channel_output(port, session_ref, caller, channel_id, session_id, "")
            end
          end)

        # Spawn Claude process directly (without script wrapper for channel agents)
        port =
          Port.open(
            {:spawn_executable, claude_path},
            [
              :binary,
              :exit_status,
              :use_stdio,
              :stderr_to_stdout,
              # Increase line buffer to 64KB to handle long JSON output
              {:line, 65536},
              {:args, args},
              {:cd, project_path},
              {:env, build_env()}
            ]
          )

        Port.connect(port, handler_pid)
        send(handler_pid, {:port, port})

        {:ok, port, session_ref}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Continues an existing session (uses `-c` flag).
  """
  def continue_session(prompt, opts \\ []) do
    opts = Keyword.put(opts, :continue, true)
    spawn_with_flag(prompt, "-c", opts)
  end

  @doc """
  Resumes a specific session by UUID (uses `--resume` flag).
  """
  def resume_session(session_id, prompt, opts \\ []) do
    opts = Keyword.put(opts, :session_id, session_id)
    spawn_with_flag(prompt, "--resume", opts)
  end

  @doc """
  Cancels a running Claude process.
  """
  def cancel(port) when is_port(port) do
    Port.close(port)
    :ok
  end

  # Private functions

  defp build_init_prompt(session_id, agent_id, prompt_name, instructions) do
    prompt_info = if prompt_name, do: "\nPrompt Template: #{prompt_name}", else: ""

    """
    INITIALIZATION - Channel Agent Context:

    Session ID: #{session_id}
    Agent ID: #{agent_id}#{prompt_info}

    CRITICAL FIRST STEP: Call i-start-session MCP tool to register with Eye in the Sky:

    i-start-session({
      "session_id": "#{session_id}",
      "description": "#{instructions}",
      "agent_description": "#{prompt_name || "Channel agent"}",
      "project_name": "eye-in-the-sky",
      "worktree_path": "#{File.cwd!()}"
    })

    COMMUNICATION: Use i-chat-send MCP tool to send all messages to the channel.

    YOUR TASK: #{instructions}
    """
  end

  defp spawn_with_flag(prompt, flag, opts) do
    model = Keyword.get(opts, :model, "sonnet")
    project_path = Keyword.get(opts, :project_path, File.cwd!())
    output_format = Keyword.get(opts, :output_format, "stream-json")
    skip_permissions = Keyword.get(opts, :skip_permissions, true)
    caller = Keyword.get(opts, :caller, self())
    session_id = Keyword.get(opts, :session_id)

    case find_claude_binary() do
      {:ok, claude_path} ->
        # Build args with continue or resume flag
        base_args = build_args(prompt, model, output_format, skip_permissions)

        args =
          if flag == "--resume" && session_id do
            [flag, session_id] ++ base_args
          else
            [flag] ++ base_args
          end

        require Logger
        Logger.info("CLI.spawn_with_flag: #{flag} session=#{session_id} path=#{project_path}")
        Logger.info("CLI.spawn_with_flag: binary=#{claude_path}")
        Logger.info("CLI.spawn_with_flag: args=#{inspect(args)}")

        session_ref = Keyword.get(opts, :session_ref, make_ref())

        # Spawn output handler
        handler_pid =
          spawn_link(fn ->
            Logger.info("CLI: Port handler process started, waiting for port assignment")
            receive do
              {:port, port} ->
                Logger.info("CLI: Port handler got port #{inspect(port)}, entering output loop")
                handle_port_output(port, session_ref, caller)
            after
              10_000 ->
                Logger.error("CLI: Port handler never received port assignment after 10s")
            end
          end)

        Logger.info("CLI: Opening port for #{claude_path}")

        # Spawn Claude directly with line-buffered output
        port =
          Port.open(
            {:spawn_executable, claude_path},
            [
              :binary,
              :exit_status,
              :use_stdio,
              :stderr_to_stdout,
              {:line, 65536},
              {:args, args},
              {:cd, project_path},
              {:env, build_env()}
            ]
          )

        Logger.info("CLI: Port opened: #{inspect(port)}, connecting to handler #{inspect(handler_pid)}")

        # Connect port to handler
        Port.connect(port, handler_pid)
        send(handler_pid, {:port, port})

        Logger.info("CLI: Port connected and handler notified, spawn complete")

        {:ok, port, session_ref}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp build_args(prompt, model, output_format, skip_permissions) do
    base = [
      "-p",
      prompt,
      "--model",
      model,
      "--output-format",
      output_format,
      "--verbose"
    ]

    if skip_permissions do
      base ++ ["--dangerously-skip-permissions"]
    else
      base
    end
  end

  defp build_env do
    # Pass ALL environment variables to subprocess
    base_env =
      for {key, value} <- System.get_env() do
        {String.to_charlist(key), String.to_charlist(value)}
      end

    # Force non-interactive mode for Claude (disable TTY requirements)
    [
      # Tell Claude it's running in CI (no TTY)
      {~c"CI", ~c"true"},
      # Disable terminal features
      {~c"TERM", ~c"dumb"}
      | base_env
    ]
  end

  defp handle_port_output(port, session_ref, caller) do
    handle_port_output(port, session_ref, caller, "")
  end

  defp handle_port_output(port, session_ref, caller, buffer) do
    require Logger

    receive do
      # Line mode: complete line received
      {^port, {:data, {:eol, line}}} ->
        full_line = buffer <> line

        unless full_line == "" do
          Logger.info("CLI output [eol]: #{String.slice(full_line, 0, 200)}")
          send(caller, {:claude_output, session_ref, full_line})
        end

        handle_port_output(port, session_ref, caller, "")

      # Line mode: incomplete line, buffer it
      {^port, {:data, {:noeol, chunk}}} ->
        Logger.debug("CLI output [noeol]: #{byte_size(chunk)} bytes buffered")
        handle_port_output(port, session_ref, caller, buffer <> chunk)

      # Fallback: raw binary data
      {^port, {:data, data}} when is_binary(data) ->
        Logger.info("CLI output [raw]: #{byte_size(data)} bytes")

        new_buffer = buffer <> data
        lines = String.split(new_buffer, "\n")

        {complete_lines, remaining} =
          case List.pop_at(lines, -1) do
            {last, rest} ->
              if String.ends_with?(data, "\n") do
                {lines, ""}
              else
                {rest, last || ""}
              end
          end

        Enum.each(complete_lines, fn line ->
          unless line == "" do
            send(caller, {:claude_output, session_ref, line})
          end
        end)

        handle_port_output(port, session_ref, caller, remaining)

      {^port, {:exit_status, status}} ->
        unless buffer == "" do
          Logger.info("CLI final buffered line: #{buffer}")
          send(caller, {:claude_output, session_ref, buffer})
        end

        Logger.info("CLI process exited with status #{status}")
        send(caller, {:claude_exit, session_ref, status})
        :ok
    after
      300_000 ->
        Logger.warning("CLI: No output after 5 minutes, timing out port=#{inspect(port)}")
        Port.close(port)
        send(caller, {:claude_exit, session_ref, :timeout})
        :ok
    end
  end

  defp process_channel_line("", _channel_id) do
    # Empty line, skip
    :ok
  end

  defp process_channel_line(line, channel_id) do
    require Logger

    Logger.debug("Channel agent line: #{line}")

    case Jason.decode(line) do
      {:ok, %{"type" => "text", "text" => text}} when text != "" ->
        # Claude text output - agent should use i-chat-send MCP tool
        # This path is for fallback/legacy stdout parsing
        Logger.debug("Claude stdout text (agent should use i-chat-send instead): #{text}")

      {:ok, %{"type" => "error", "error" => error_msg}} ->
        Logger.error("Claude error: #{error_msg}")

        # Spawn async task to avoid blocking the port reader
        Task.Supervisor.start_child(EyeInTheSkyWeb.TaskSupervisor, fn ->
          {:ok, error_message} =
            EyeInTheSkyWeb.Messages.send_channel_message(%{
              channel_id: channel_id,
              session_id: "system",
              sender_role: "system",
              recipient_role: "user",
              provider: "system",
              body: "Agent error: #{error_msg}"
            })

          Phoenix.PubSub.broadcast(
            EyeInTheSkyWeb.PubSub,
            "channel:#{channel_id}:messages",
            {:new_message, error_message}
          )
        end)

      {:ok, _other} ->
        # Other JSON types (metadata, thinking, etc.) - log but don't display
        Logger.debug("Claude metadata: #{line}")

      {:error, err} ->
        # Not JSON - might be stderr or startup messages
        Logger.warning("Failed to parse JSON: #{inspect(err)} - line: #{line}")
    end
  end

  defp handle_channel_output(port, session_ref, caller, channel_id, session_id, buffer) do
    require Logger

    receive do
      {^port, {:data, {:eol, line}}} ->
        # Line mode: complete line received (newline already stripped)
        process_channel_line(line, channel_id)

        handle_channel_output(port, session_ref, caller, channel_id, session_id, "")

      {^port, {:data, {:noeol, chunk}}} ->
        # Line mode: incomplete line, buffer it
        new_buffer = buffer <> chunk
        handle_channel_output(port, session_ref, caller, channel_id, session_id, new_buffer)

      {^port, {:data, data}} when is_binary(data) ->
        # Fallback: raw binary data (shouldn't happen with {:line, N} but handle gracefully)
        Logger.debug("Channel agent output received: #{byte_size(data)} bytes")

        # Append to buffer and process line-by-line
        new_buffer = buffer <> data
        lines = String.split(new_buffer, "\n")

        {complete_lines, remaining} =
          case List.pop_at(lines, -1) do
            {last, rest} ->
              if String.ends_with?(data, "\n") do
                {lines, ""}
              else
                {rest, last || ""}
              end
          end

        Enum.each(complete_lines, fn line ->
          unless line == "" do
            process_channel_line(line, channel_id)
          end
        end)

        handle_channel_output(port, session_ref, caller, channel_id, session_id, remaining)

      {^port, {:exit_status, status}} ->
        Logger.error("Channel agent process exited with status #{status}")
        Logger.error("Session ID: #{session_id}")
        Logger.error("Channel ID: #{channel_id}")

        # Spawn async task to send exit notification without blocking port reader
        Task.Supervisor.start_child(EyeInTheSkyWeb.TaskSupervisor, fn ->
          {:ok, exit_msg} =
            EyeInTheSkyWeb.Messages.send_channel_message(%{
              channel_id: channel_id,
              session_id: "system",
              sender_role: "system",
              recipient_role: "user",
              provider: "system",
              body: "Agent session ended (exit code: #{status})"
            })

          Phoenix.PubSub.broadcast(
            EyeInTheSkyWeb.PubSub,
            "channel:#{channel_id}:messages",
            {:new_message, exit_msg}
          )
        end)

        send(caller, {:claude_exit, session_ref, status})
        :ok
    after
      300_000 ->
        Logger.warning("No output from channel agent after 5 minutes, timing out")
        Port.close(port)

        # Spawn async task to send timeout notification without blocking port reader
        Task.Supervisor.start_child(EyeInTheSkyWeb.TaskSupervisor, fn ->
          {:ok, timeout_msg} =
            EyeInTheSkyWeb.Messages.send_channel_message(%{
              channel_id: channel_id,
              session_id: "system",
              sender_role: "system",
              recipient_role: "user",
              provider: "system",
              body: "Agent session timed out (no activity for 5 minutes)"
            })

          Phoenix.PubSub.broadcast(
            EyeInTheSkyWeb.PubSub,
            "channel:#{channel_id}:messages",
            {:new_message, timeout_msg}
          )
        end)

        send(caller, {:claude_exit, session_ref, :timeout})
        :ok
    end
  end

  defp find_claude_binary do
    # Try multiple detection strategies like opcode
    cond do
      # 1. Check which/where command
      path = System.find_executable("claude") ->
        {:ok, path}

      # 2. Check standard locations
      path = find_in_standard_paths() ->
        {:ok, path}

      # 3. Check NVM installations
      path = find_in_nvm() ->
        {:ok, path}

      true ->
        {:error, "Claude binary not found in PATH, standard locations, or NVM"}
    end
  end

  defp find_in_standard_paths do
    standard_paths = [
      "/usr/local/bin/claude",
      "/opt/homebrew/bin/claude",
      Path.expand("~/.local/bin/claude")
    ]

    Enum.find(standard_paths, &File.exists?/1)
  end

  defp find_in_nvm do
    nvm_dir = System.get_env("NVM_DIR") || Path.expand("~/.nvm")
    versions_dir = Path.join(nvm_dir, "versions/node")

    if File.dir?(versions_dir) do
      versions_dir
      |> File.ls!()
      |> Enum.map(&Path.join([versions_dir, &1, "bin", "claude"]))
      |> Enum.filter(&File.exists?/1)
      |> List.first()
    else
      nil
    end
  end
end
