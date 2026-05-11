defmodule EyeInTheSkyWeb.Api.V1.SessionMessageController do
  use EyeInTheSkyWeb, :controller

  action_fallback EyeInTheSkyWeb.Api.V1.FallbackController

  import EyeInTheSkyWeb.ControllerHelpers

  alias EyeInTheSky.{Messages, Sessions}

  @doc """
  GET /api/v1/sessions/:uuid/messages

  Query params:
    - limit (optional): max messages to return (default 50, max 200)
    - q (optional): filter by body substring
  """
  def index(conn, %{"uuid" => uuid} = params) do
    case Sessions.resolve(uuid) do
      {:ok, session} ->
        limit = parse_int(params["limit"], 50) |> then(&min(&1, 200))
        query = String.trim(params["q"] || "")

        messages =
          if query == "" do
            Messages.list_recent_messages(session.id, limit)
          else
            Messages.search_messages_for_session(session.id, query)
          end

        json(conn, %{
          success: true,
          session_id: session.id,
          session_uuid: session.uuid,
          count: length(messages),
          messages:
            Enum.map(messages, fn m ->
              %{
                id: m.id,
                uuid: m.uuid,
                role: m.sender_role,
                body: m.body,
                direction: m.direction,
                status: m.status,
                inserted_at: m.inserted_at
              }
            end)
        })

      {:error, :not_found} ->
        {:error, :not_found, "session not found: #{uuid}"}
    end
  end
end
