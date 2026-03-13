defmodule EyeInTheSkyWeb.MCP.Tools.Helpers do
  @moduledoc "Shared utilities for MCP tools"

  alias EyeInTheSkyWeb.Sessions

  @doc """
  Resolves a session identifier (integer, integer string, or UUID string) to an internal integer ID.

  Returns:
    - `{:ok, integer_id}` on success
    - `{:error, reason}` on failure
  """
  def resolve_session_int_id(nil), do: {:error, "session_id is required"}

  def resolve_session_int_id(id) when is_integer(id), do: {:ok, id}

  def resolve_session_int_id(raw) when is_binary(raw) do
    case Integer.parse(raw) do
      {int_id, ""} ->
        {:ok, int_id}

      _ ->
        case Sessions.get_session_by_uuid(raw) do
          {:ok, session} -> {:ok, session.id}
          {:error, :not_found} -> {:error, "Session not found: #{raw}"}
        end
    end
  end
end
