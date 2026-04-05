defmodule EyeInTheSky.Agents.CmdDispatcher.DmHandler do
  @moduledoc """
  Handles EITS-CMD dm subcommands.

  Supported:
      dm --to <session_ref> --message <text>
      dm list [--limit <n>]
  """

  require Logger

  alias EyeInTheSky.{Messages, Sessions}
  alias EyeInTheSky.Agents.AgentManager
  alias EyeInTheSky.Agents.CmdDispatcher.Helpers
  alias EyeInTheSky.Utils.ToolHelpers

  import Helpers, only: [notify_success: 2, notify_error: 3, extract_flag: 2]

  def dispatch("list" <> rest, from_session_id) do
    limit =
      case extract_flag(rest, "--limit") do
        {:ok, n} ->
          case n |> String.trim() |> ToolHelpers.parse_int() do
            nil -> 20
            v -> min(v, 50)
          end

        _ ->
          20
      end

    dms = Messages.list_inbound_dms(from_session_id, limit)

    if dms == [] do
      AgentManager.send_message(from_session_id, "[EITS] dm list: no DMs found")
    else
      lines =
        Enum.map(dms, fn m ->
          ts = Calendar.strftime(m.inserted_at, "%Y-%m-%d %H:%M:%S")
          "[#{ts}] from_session:#{m.from_session_id} — #{m.body}"
        end)

      payload = "[EITS] dm list (#{length(dms)}):\n" <> Enum.join(lines, "\n")
      AgentManager.send_message(from_session_id, payload)
    end

    Logger.info("[CmdDispatcher] dm list for session #{from_session_id}, #{length(dms)} results")
  end

  def dispatch(args, from_session_id) do
    with {:ok, to_ref} <- extract_flag(args, "--to"),
         {:ok, message} <- extract_flag(args, "--message") do
      case Sessions.get_session(from_session_id) do
        {:ok, from_session} ->
          resolve_and_send_dm(from_session, to_ref, message, from_session_id)

        {:error, :not_found} ->
          notify_error(from_session_id, "dm", {:sender_session_not_found, from_session_id})

        err ->
          notify_error(from_session_id, "dm", err)
      end
    else
      err -> notify_error(from_session_id, "dm", err)
    end
  end

  defp resolve_and_send_dm(from_session, to_ref, message, from_session_id) do
    case Sessions.resolve(to_ref) do
      {:ok, to_session} ->
        send_dm(from_session, to_session, message, from_session_id)

      {:error, :not_found} ->
        notify_error(from_session_id, "dm", {:target_session_not_found, to_ref})

      err ->
        notify_error(from_session_id, "dm", err)
    end
  end

  defp send_dm(from_session, to_session, message, from_session_id) do
    sender_name = from_session.name || "session:#{from_session.uuid}"
    dm_body = "DM from:#{sender_name} (session:#{from_session.uuid}) #{message}"

    attrs = %{
      uuid: Ecto.UUID.generate(),
      session_id: to_session.id,
      from_session_id: from_session.id,
      to_session_id: to_session.id,
      body: dm_body,
      sender_role: "agent",
      recipient_role: "agent",
      direction: "inbound",
      status: "sent",
      provider: "claude",
      metadata: %{
        sender_name: sender_name,
        from_session_uuid: from_session.uuid,
        to_session_uuid: to_session.uuid
      }
    }

    case AgentManager.send_message(to_session.id, dm_body) do
      {:ok, _} ->
        case Messages.create_message(attrs) do
          {:ok, msg} ->
            EyeInTheSky.Events.session_new_dm(to_session.id, msg)
            notify_success(from_session_id, "dm sent to session #{to_session.id}")

          {:error, reason} ->
            notify_error(from_session_id, "dm persist", reason)
        end

      {:error, reason} ->
        notify_error(from_session_id, "dm send", reason)
    end
  end
end
