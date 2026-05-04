defmodule EyeInTheSkyWeb.Api.V1.MessageSearchController do
  use EyeInTheSkyWeb, :controller

  action_fallback EyeInTheSkyWeb.Api.V1.FallbackController

  import EyeInTheSkyWeb.ControllerHelpers

  alias EyeInTheSky.{Messages, Sessions}

  @doc """
  GET /api/v1/messages/search - Cross-session full-text search on message body.
  Query params:
    - q (required): search query string
    - session_id (optional): UUID or integer session ID to scope results
    - limit (optional): max results (default 10, max 100)
    - include_archived (optional): "true" to include messages from archived sessions
  """
  def search(conn, params) do
    query = String.trim(params["q"] || "")

    if query == "" do
      {:error, :bad_request, "q is required"}
    else
      limit = parse_int(params["limit"], 10) |> then(&min(&1, 100))
      include_archived = params["include_archived"] == "true"

      opts_or_error =
        case params["session_id"] do
          nil -> [limit: limit, include_archived: include_archived]
          "" -> [limit: limit, include_archived: include_archived]
          raw ->
            case Sessions.resolve(raw) do
              {:ok, session} -> [limit: limit, session_id: session.id, include_archived: include_archived]
              {:error, :not_found} -> {:error, :not_found, "session not found: #{raw}"}
            end
        end

      case opts_or_error do
        {:error, _, _} = err ->
          err

        opts ->
          messages = Messages.search_messages(query, opts)

          json(conn, %{
            success: true,
            query: query,
            count: length(messages),
            messages:
              Enum.map(messages, fn m ->
                %{
                  id: m.id,
                  session_id: m.session_id,
                  session_uuid: m.session_uuid,
                  session_name: m.session_name,
                  role: m.sender_role,
                  body_excerpt: m.body_excerpt,
                  inserted_at: m.inserted_at
                }
              end)
          })
      end
    end
  end
end
