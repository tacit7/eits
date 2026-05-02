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
    case parse_int(raw) do
      nil ->
        case Ecto.UUID.cast(raw) do
          {:ok, _} ->
            case Sessions.get_session_by_uuid(raw) do
              {:ok, session} -> {:ok, session.id}
              {:error, :not_found} -> {:error, "Session not found: #{raw}"}
            end

          :error ->
            {:error, "Session not found: #{raw}"}
        end

      int_id ->
        case Sessions.get_session(int_id) do
          {:ok, session} -> {:ok, session.id}
          {:error, :not_found} -> {:error, "Session not found: #{raw}"}
        end
    end
  end

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

  @doc """
  Parse a string or integer to an integer with a fallback default.

  Returns `default` for nil, non-integer strings, or any other type.
  The catch-all clause is intentional and consistent with `parse_int/1` returning nil
  for unexpected types. The prior ControllerHelpers.parse_int/2 lacked a catch-all
  (FunctionClauseError on unexpected types), which was an oversight — all callers
  pass HTTP params (string | integer | nil).
  """
  def parse_int(nil, default), do: default
  def parse_int(val, _default) when is_integer(val), do: val

  def parse_int(val, default) when is_binary(val) do
    case Integer.parse(val) do
      {n, ""} -> n
      _ -> default
    end
  end

  def parse_int(_, default), do: default

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
