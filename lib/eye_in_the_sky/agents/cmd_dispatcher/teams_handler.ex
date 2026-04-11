defmodule EyeInTheSky.Agents.CmdDispatcher.TeamsHandler do
  @moduledoc """
  Handles EITS-CMD teams and team subcommands.

  Supported (teams — plural, team-scoped):
      teams join <team_id> --name <name> [--role <role>]
      teams leave <team_id> <member_id>
      teams done
      teams update-member <team_id> <member_id> --status <status>

  Supported (team — singular, agent-scoped):
      team broadcast --message <text>
  """

  require Logger

  alias EyeInTheSky.Agents.AgentManager
  alias EyeInTheSky.Agents.CmdDispatcher.Helpers
  alias EyeInTheSky.{Sessions, Teams}
  alias EyeInTheSky.Utils.ToolHelpers

  import Helpers, only: [notify_success: 2, notify_error: 3, extract_flag: 2, get_session_or_nil: 1, session_field: 2]

  # ---------------------------------------------------------------------------
  # teams (plural)
  # ---------------------------------------------------------------------------

  def dispatch_teams("join " <> rest, from_session_id) do
    case String.split(rest, " ", parts: 2) do
      [team_id_str | tail] ->
        args = List.first(tail, "")

        with team_id when not is_nil(team_id) <- team_id_str |> String.trim() |> ToolHelpers.parse_int(),
             {:ok, name} <- extract_flag(args, "--name") do
          session = get_session_or_nil(from_session_id)
          role = extract_role(args)

          attrs = %{
            team_id: team_id,
            name: name,
            role: role,
            session_id: from_session_id,
            agent_id: session_field(session, :agent_id)
          }

          do_join_team(attrs, team_id, from_session_id)
        else
          _ -> notify_error(from_session_id, "teams join", :invalid_team_id_or_missing_name)
        end

      _ ->
        notify_error(from_session_id, "teams join", :expected_team_id_and_name)
    end
  end

  def dispatch_teams("leave " <> rest, from_session_id) do
    case String.split(rest, " ", parts: 2) do
      [_team_id_str, member_id_str] ->
        case member_id_str |> String.trim() |> ToolHelpers.parse_int() do
          nil -> notify_error(from_session_id, "teams leave", {:invalid_member_id, member_id_str})
          member_id -> leave_member(member_id, from_session_id)
        end

      _ ->
        notify_error(from_session_id, "teams leave", :expected_team_id_and_member_id)
    end
  end

  def dispatch_teams("done" <> _, from_session_id) do
    Teams.mark_member_done_by_session(from_session_id)
    notify_success(from_session_id, "teams done for session #{from_session_id}")
  end

  def dispatch_teams("update-member " <> rest, from_session_id) do
    case String.split(rest, " ", parts: 3) do
      [_team_id_str, member_id_str | tail] ->
        args = List.first(tail, "")

        with member_id when not is_nil(member_id) <- member_id_str |> String.trim() |> ToolHelpers.parse_int(),
             {:ok, status} <- extract_flag(args, "--status") do
          do_update_member(member_id, status, from_session_id)
        else
          _ ->
            notify_error(
              from_session_id,
              "teams update-member",
              :invalid_member_id_or_missing_status
            )
        end

      _ ->
        notify_error(
          from_session_id,
          "teams update-member",
          :expected_team_id_member_id_and_status
        )
    end
  end

  def dispatch_teams(unknown, from_session_id),
    do: notify_error(from_session_id, "teams", {:unknown_subcommand, unknown})

  # ---------------------------------------------------------------------------
  # team (singular) — broadcast
  # ---------------------------------------------------------------------------

  def dispatch_team("broadcast" <> rest, from_session_id) do
    case extract_flag(rest, "--message") do
      {:ok, message} ->
        members = Teams.list_broadcast_targets(from_session_id)
        {:ok, from_session} = Sessions.get_session(from_session_id)
        sender_name = from_session.name || "session:#{from_session.uuid}"
        dm_body = "[team broadcast] from #{sender_name}: #{message}"

        Enum.each(members, &broadcast_to_member(&1, dm_body))

        notify_success(from_session_id, "team broadcast sent to #{length(members)} members")

      _ ->
        notify_error(from_session_id, "team broadcast", :missing_message_flag)
    end
  end

  def dispatch_team(unknown, from_session_id),
    do: notify_error(from_session_id, "team", {:unknown_subcommand, unknown})

  defp extract_role(args) do
    case extract_flag(args, "--role") do
      {:ok, r} -> r
      _ -> "member"
    end
  end

  defp do_join_team(attrs, team_id, from_session_id) do
    case Teams.join_team(attrs) do
      {:ok, member} ->
        notify_success(
          from_session_id,
          "joined team #{team_id} as #{member.name} (member_id=#{member.id})"
        )

      {:error, reason} ->
        notify_error(from_session_id, "teams join", reason)
    end
  end

  defp leave_member(member_id, from_session_id) do
    case Teams.get_member(member_id) do
      {:error, :not_found} ->
        notify_error(from_session_id, "teams leave", {:member_not_found, member_id})

      {:ok, member} ->
        Teams.leave_team(member)
        notify_success(from_session_id, "member #{member_id} left team")
    end
  end

  defp do_update_member(member_id, status, from_session_id) do
    case Teams.get_member(member_id) do
      {:error, :not_found} ->
        notify_error(from_session_id, "teams update-member", {:member_not_found, member_id})

      {:ok, member} ->
        Teams.update_member_status(member, status)
        notify_success(from_session_id, "team member #{member_id} status -> #{status}")
    end
  end

  defp broadcast_to_member(member, dm_body) do
    Task.Supervisor.start_child(EyeInTheSky.TaskSupervisor, fn ->
      AgentManager.send_message(member.session_id, dm_body)
    end)
  end
end
