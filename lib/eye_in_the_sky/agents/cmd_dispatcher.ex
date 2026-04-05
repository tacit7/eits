defmodule EyeInTheSky.Agents.CmdDispatcher do
  @moduledoc """
  Parses and dispatches EITS-CMD directives from agent text output.

  Protocol: the agent writes a line starting with `EITS-CMD:` anywhere in its
  text. The AgentWorker intercepts these lines before broadcasting to the stream,
  strips them from the visible output, and dispatches them in-process — no HTTP
  round-trips required.

  ## Supported commands

      EITS-CMD: dm --to <session_ref> --message <text>
      EITS-CMD: dm list [--limit <n>]

      EITS-CMD: team broadcast --message <text>

      EITS-CMD: task create <title>
      EITS-CMD: task begin <title>
      EITS-CMD: task start <id>
      EITS-CMD: task update <id> <state_id>
      EITS-CMD: task done <id>
      EITS-CMD: task delete <id>
      EITS-CMD: task annotate <id> <body>
      EITS-CMD: task link-session <id>
      EITS-CMD: task unlink-session <id>
      EITS-CMD: task tag <id> <tag_id>

      EITS-CMD: note <body>
      EITS-CMD: note task <id> <body>

      EITS-CMD: commit <hash>

      EITS-CMD: spawn --instructions <text> [--description <text>] [--model <model>]
                      [--worktree <branch>] [--effort-level <level>]
                      [--team-name <name>] [--member-name <alias>]
                      [--agent <name>] [--provider <claude|codex>] [--yolo]

      EITS-CMD: teams join <team_id> --name <name> [--role <role>]
      EITS-CMD: teams leave <team_id> <member_id>
      EITS-CMD: teams done
      EITS-CMD: teams update-member <team_id> <member_id> --status <status>

      EITS-CMD: channel send <channel_id> --body <text>

  ## Submodules

    * `CmdDispatcher.Helpers`      — shared notify/extract/with_task helpers
    * `CmdDispatcher.TaskHandler`  — task subcommands
    * `CmdDispatcher.DmHandler`    — dm subcommands
    * `CmdDispatcher.TeamsHandler` — teams + team subcommands

  Smaller command groups (note, commit, spawn, channel) are handled inline.
  """

  require Logger

  alias EyeInTheSky.Agents.AgentManager
  alias EyeInTheSky.Agents.CmdDispatcher.{DmHandler, Helpers, TaskHandler, TeamsHandler}
  alias EyeInTheSky.{ChannelMessages, Commits, Notes, Tasks}
  alias EyeInTheSky.Utils.ToolHelpers

  import Helpers,
    only: [
      notify_success: 2,
      notify_error: 3,
      get_session!: 1,
      extract_flag: 2,
      put_optional_flag: 4
    ]

  @cmd_prefix "EITS-CMD:"

  @doc """
  Scans text content for EITS-CMD lines.
  Returns `{cmd_lines, clean_text}` where `clean_text` has CMD lines stripped.
  """
  @spec extract_commands(String.t()) :: {[String.t()], String.t()}
  def extract_commands(text) when is_binary(text) do
    lines = String.split(text, "\n")

    {cmd_lines, clean_lines} =
      Enum.split_with(lines, fn line ->
        String.starts_with?(String.trim(line), @cmd_prefix)
      end)

    {cmd_lines, Enum.join(clean_lines, "\n")}
  end

  @doc """
  Dispatches a list of EITS-CMD lines in the context of the given session.
  Each command is dispatched asynchronously to avoid blocking the worker.
  """
  @spec dispatch_all([String.t()], integer()) :: :ok
  def dispatch_all(cmd_lines, from_session_id) do
    Enum.each(cmd_lines, fn line ->
      Task.Supervisor.start_child(EyeInTheSky.TaskSupervisor, fn ->
        dispatch(String.trim(line), from_session_id)
      end)
    end)
  end

  # ---------------------------------------------------------------------------
  # Top-level router
  # ---------------------------------------------------------------------------

  defp dispatch(@cmd_prefix <> rest, from_session_id) do
    case String.split(String.trim(rest), " ", parts: 2) do
      ["dm", args]      -> DmHandler.dispatch(args, from_session_id)
      ["task", args]    -> TaskHandler.dispatch(args, from_session_id)
      ["note", args]    -> dispatch_note(args, from_session_id)
      ["commit", hash]  -> dispatch_commit(String.trim(hash), from_session_id)
      ["spawn", args]   -> dispatch_spawn(args, from_session_id)
      ["teams", args]   -> TeamsHandler.dispatch_teams(args, from_session_id)
      ["team", args]    -> TeamsHandler.dispatch_team(args, from_session_id)
      ["channel", args] -> dispatch_channel(args, from_session_id)
      [unknown]         -> notify_error(from_session_id, unknown, :unknown_command)
      _                 -> notify_error(from_session_id, rest, :unknown_command)
    end
  end

  defp dispatch(line, from_session_id),
    do: notify_error(from_session_id, "parse", {:malformed_line, line})

  # ---------------------------------------------------------------------------
  # note
  # ---------------------------------------------------------------------------

  defp dispatch_note("task " <> rest, from_session_id) do
    case String.split(rest, " ", parts: 2) do
      [id_str, body] ->
        case ToolHelpers.parse_int(String.trim(id_str)) do
          nil -> notify_error(from_session_id, "note task", {:invalid_id, id_str})
          id -> do_add_task_note(id, body, from_session_id)
        end

      _ ->
        notify_error(from_session_id, "note task", :missing_body)
    end
  end

  defp dispatch_note(body, from_session_id) when body != "" do
    Notes.create_note(%{body: body, parent_id: from_session_id, parent_type: "session"})
    notify_success(from_session_id, "note added to session #{from_session_id}")
  end

  defp dispatch_note(_, from_session_id),
    do: notify_error(from_session_id, "note", :empty_body)

  # ---------------------------------------------------------------------------
  # commit
  # ---------------------------------------------------------------------------

  defp dispatch_commit(hash, from_session_id) when hash != "" do
    case Commits.create_commit(%{commit_hash: hash, session_id: from_session_id}) do
      {:ok, _} -> notify_success(from_session_id, "commit #{hash} logged")
      {:error, reason} -> notify_error(from_session_id, "commit", reason)
    end
  end

  defp dispatch_commit(_, from_session_id),
    do: notify_error(from_session_id, "commit", :empty_hash)

  # ---------------------------------------------------------------------------
  # spawn
  # ---------------------------------------------------------------------------

  defp dispatch_spawn(args, from_session_id) do
    case extract_flag(args, "--instructions") do
      {:ok, instructions} ->
        session = get_session!(from_session_id)

        description =
          case extract_flag(args, "--description") do
            {:ok, d} -> d
            _ -> "Spawned by session #{from_session_id}"
          end

        opts =
          [
            instructions: instructions,
            description: description,
            project_id: session && session.project_id,
            project_path: session && session.git_worktree_path
          ]
          |> put_optional_flag(args, "--model", :model)
          |> put_optional_flag(args, "--worktree", :worktree)
          |> put_optional_flag(args, "--effort-level", :effort_level)
          |> put_optional_flag(args, "--team-name", :team_name)
          |> put_optional_flag(args, "--member-name", :member_name)
          |> put_optional_flag(args, "--agent", :agent)
          |> put_optional_flag(args, "--provider", :agent_type)

        opts =
          if String.contains?(args, "--yolo"),
            do: Keyword.put(opts, :bypass_sandbox, true),
            else: opts

        case AgentManager.create_agent(opts) do
          {:ok, %{agent: agent, session: new_session}} ->
            notify_success(
              from_session_id,
              "spawned agent=#{agent.id} session=#{new_session.id} uuid=#{new_session.uuid}"
            )

          {:error, reason} ->
            notify_error(from_session_id, "spawn", reason)
        end

      err ->
        notify_error(from_session_id, "spawn (missing --instructions)", err)
    end
  end

  # ---------------------------------------------------------------------------
  # channel
  # ---------------------------------------------------------------------------

  defp dispatch_channel("send " <> rest, from_session_id) do
    case String.split(rest, " ", parts: 2) do
      [channel_id_str | tail] ->
        args = List.first(tail, "")

        with channel_id when not is_nil(channel_id) <- ToolHelpers.parse_int(String.trim(channel_id_str)),
             {:ok, body} <- extract_flag(args, "--body") do
          session = get_session!(from_session_id)

          attrs = %{
            channel_id: channel_id,
            session_id: from_session_id,
            agent_id: session && session.agent_id,
            body: body,
            sender_role: "agent"
          }

          do_send_channel_message(attrs, channel_id, from_session_id)
        else
          _ -> notify_error(from_session_id, "channel send", :invalid_channel_id_or_missing_body)
        end

      _ ->
        notify_error(from_session_id, "channel send", :expected_channel_id_and_body)
    end
  end

  defp dispatch_channel(unknown, from_session_id),
    do: notify_error(from_session_id, "channel", {:unknown_subcommand, unknown})

  defp do_add_task_note(id, body, from_session_id) do
    if Tasks.task_linked_to_session?(id, from_session_id) do
      Notes.create_note(%{body: body, parent_id: id, parent_type: "task"})
      notify_success(from_session_id, "note added to task #{id}")
    else
      notify_error(from_session_id, "note task", {:not_linked, id})
    end
  end

  defp do_send_channel_message(attrs, channel_id, from_session_id) do
    case ChannelMessages.send_channel_message(attrs) do
      {:ok, msg} ->
        notify_success(from_session_id, "channel #{channel_id} message sent (id=#{msg.id})")

      {:error, reason} ->
        notify_error(from_session_id, "channel send", reason)
    end
  end
end
