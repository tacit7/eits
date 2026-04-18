defmodule EyeInTheSky.Utils.ToolHelpers do
  @moduledoc "Shared utilities for resolving entity IDs used by REST API and Claude workers"

  alias EyeInTheSky.{Agents, Sessions}

  def resolve_session_int_id(nil), do: {:error, "session_id is required"}

  def resolve_session_int_id(id) when is_integer(id) do
    case Sessions.get_session(id) do
      {:ok, session} -> {:ok, session.id}
      {:error, :not_found} -> {:error, "Session not found: #{id}"}
    end
  end

  def resolve_session_int_id(raw) when is_binary(raw) do
    case Integer.parse(raw) do
      {int_id, ""} ->
        case Sessions.get_session(int_id) do
          {:ok, session} -> {:ok, session.id}
          {:error, :not_found} -> {:error, "Session not found: #{raw}"}
        end

      _ ->
        case Sessions.get_session_by_uuid(raw) do
          {:ok, session} -> {:ok, session.id}
          {:error, :not_found} -> {:error, "Session not found: #{raw}"}
        end
    end
  end

  def resolve_session_int_id(_), do: {:error, "session_id must be a string or integer"}

  @doc "Parse a string or integer to an integer. Returns nil for invalid or nil input."
  def parse_int(nil), do: nil
  def parse_int(val) when is_integer(val), do: val

  def parse_int(val) when is_binary(val) do
    case Integer.parse(val) do
      {n, ""} -> n
      _ -> nil
    end
  end

  def parse_int(_), do: nil

  def maybe_put(map, _key, nil), do: map
  def maybe_put(map, key, value), do: Map.put(map, key, value)

  def resolve_agent_uuid(nil), do: nil

  def resolve_agent_uuid(agent_int_id) do
    case Agents.get_agent(agent_int_id) do
      {:ok, agent} -> agent.uuid
      _ -> nil
    end
  end

  def normalize_parent_type("sessions"), do: "session"
  def normalize_parent_type("agents"), do: "agent"
  def normalize_parent_type("tasks"), do: "task"
  def normalize_parent_type("projects"), do: "project"
  def normalize_parent_type(type), do: type
end
