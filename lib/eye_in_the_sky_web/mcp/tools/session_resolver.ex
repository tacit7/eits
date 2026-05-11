defmodule EyeInTheSkyWeb.MCP.Tools.SessionResolver do
  @moduledoc """
  Centralized session ID resolution for MCP tools.

  Handles both integer IDs and UUID strings, with optional agent UUID fallback for special cases.
  """

  alias EyeInTheSky.{Agents, Sessions}
  alias EyeInTheSky.Utils.ToolHelpers

  @doc """
  Resolve a session from an integer ID or UUID string.

  Returns `{:ok, session}` or `{:error, :not_found}`.
  """
  @spec resolve(integer() | String.t() | nil) :: {:ok, Sessions.Session.t()} | {:error, :not_found}
  def resolve(nil), do: {:error, :not_found}
  def resolve(""), do: {:error, :not_found}
  def resolve(id) when is_integer(id), do: Sessions.get_session(id)

  def resolve(ref) when is_binary(ref) do
    if int_id = ToolHelpers.parse_int(ref) do
      Sessions.get_session(int_id)
    else
      Sessions.get_session_by_uuid(ref)
    end
  end

  @doc """
  Resolve a session ID to an integer, returning the ID directly.

  Returns `{:ok, integer()}` or `{:error, :not_found}`.
  """
  @spec resolve_int(integer() | String.t() | nil) :: {:ok, integer()} | {:error, :not_found}
  def resolve_int(nil), do: {:error, :not_found}
  def resolve_int(""), do: {:error, :not_found}
  def resolve_int(id) when is_integer(id), do: Sessions.get_session(id) |> result_to_int()

  def resolve_int(ref) when is_binary(ref) do
    if int_id = ToolHelpers.parse_int(ref) do
      Sessions.get_session(int_id) |> result_to_int()
    else
      Sessions.get_session_by_uuid(ref) |> result_to_int()
    end
  end

  @doc """
  Resolve a session with fallback to agent UUID lookup (for senders/from-sessions).

  If the ref is not found as a session, tries to resolve it as an agent UUID
  and returns the first session for that agent.

  Returns `{:ok, session}` or `{:error, :not_found}`.
  """
  @spec resolve_with_agent_fallback(String.t() | integer() | nil) ::
          {:ok, Sessions.Session.t()} | {:error, :not_found}
  def resolve_with_agent_fallback(nil), do: {:error, :not_found}
  def resolve_with_agent_fallback(""), do: {:error, :not_found}

  def resolve_with_agent_fallback(ref) do
    case resolve(ref) do
      {:ok, session} ->
        {:ok, session}

      {:error, :not_found} ->
        if _int_id = ToolHelpers.parse_int(ref) do
          {:error, :not_found}
        else
          session_for_agent_uuid(ref)
        end
    end
  end

  defp session_for_agent_uuid(ref) do
    case Agents.get_agent_by_uuid(ref) do
      {:ok, agent} ->
        case Sessions.list_sessions_for_agent(agent.id, limit: 1) do
          [session | _] -> {:ok, session}
          [] -> {:error, :not_found}
        end

      {:error, :not_found} ->
        {:error, :not_found}
    end
  end

  @doc """
  Resolve a session, returning only the integer ID or nil on failure.

  Convenient for cases where you just need the ID and want to handle failure silently.
  """
  @spec resolve_int_or_nil(integer() | String.t() | nil) :: integer() | nil
  def resolve_int_or_nil(ref) do
    case resolve_int(ref) do
      {:ok, id} -> id
      {:error, :not_found} -> nil
    end
  end

  @doc """
  Resolve an optional session ID. Returns nil if input is nil/empty, error tuple otherwise.
  """
  @spec resolve_optional(integer() | String.t() | nil) ::
          {:ok, Sessions.Session.t()} | {:ok, nil} | {:error, :not_found}
  def resolve_optional(nil), do: {:ok, nil}
  def resolve_optional(""), do: {:ok, nil}

  def resolve_optional(ref) do
    resolve(ref)
  end

  @doc """
  Resolve an optional session ID to an integer. Returns nil if input is nil/empty.
  """
  @spec resolve_optional_int(integer() | String.t() | nil) :: {:ok, integer() | nil} | {:error, :not_found}
  def resolve_optional_int(nil), do: {:ok, nil}
  def resolve_optional_int(""), do: {:ok, nil}

  def resolve_optional_int(ref) do
    resolve_int(ref)
  end

  # Helpers

  defp result_to_int({:ok, session}), do: {:ok, session.id}
  defp result_to_int({:error, reason}), do: {:error, reason}
end
