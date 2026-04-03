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

  alias EyeInTheSky.{Sessions, Teams}
  alias EyeInTheSky.Agents.AgentManager
  alias EyeInTheSky.Agents.CmdDispatcher.Helpers

  import Helpers, only: [notify_success: 2, notify_error: 3, extract_flag: 2, get_session!: 1]

  # ---------------------------------------------------------------------------
  # teams (plural)
  # ---------------------------------------------------------------------------

  def dispatch_teams("join " <> rest, from_session_id) do
    case String.split(rest, " ", parts: 2) do
      [team_id_str | tail] ->
        args = List.first(tail, "")

        with {team_id, ""} <- Integer.parse(String.trim(team_id_str)),
             {:ok, name} <- extract_flag(args, "--name") do
          session = get_session!(from_session_id)

          role =
            case extract_flag(args, "--role") do
              {:ok, r} -> r
              _ -> "member"
            end

          attrs = %{
            team_id: team_id,
            name: name,
            role: role,
            session_id: from_session_id,
            agent_id: session && session.agent_id
          }

          case Teams.join_team(attrs) do
            {:ok, member} ->
              notify_success(
                from_session_id,
                "joined team #{team_id} as #{member.name} (member_id=#{member.id})"
              )

            {:error, reason} ->
              notify_error(from_session_id, "teams join", reason)
          end
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
        case Integer.parse(String.trim(member_id_str)) do
          {member_id, ""} ->
            case Teams.get_member(member_id) do
              nil ->
                notify_error(from_session_id, "teams leave", {:member_not_found, member_id})

              member ->
                Teams.leave_team(member)
                notify_success(from_session_id, "member #{member_id} left team")
            end

          _ ->
            notify_error(from_session_id, "teams leave", {:invalid_member_id, member_id_str})
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

        with {member_id, ""} <- Integer.parse(String.trim(member_id_str)),
             {:ok, status} <- extract_flag(args, "--status") do
          case Teams.get_member(member_id) do
            nil ->
              notify_error(from_session_id, "teams update-member", {:member_not_found, member_id})

            member ->
              Teams.update_member_status(member, status)
              notify_success(from_session_id, "team member #{member_id} status -> #{status}")
          end
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

        Enum.each(members, fn member ->
          Task.Supervisor.start_child(EyeInTheSky.TaskSupervisor, fn ->
            AgentManager.send_message(member.session_id, dm_body)
          end)
        end)

        notify_success(from_session_id, "team broadcast sent to #{length(members)} members")

      _ ->
        notify_error(from_session_id, "team broadcast", :missing_message_flag)
    end
  end

  def dispatch_team(unknown, from_session_id),
    do: notify_error(from_session_id, "team", {:unknown_subcommand, unknown})
end
