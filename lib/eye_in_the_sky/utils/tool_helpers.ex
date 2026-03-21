defmodule EyeInTheSky.Utils.ToolHelpers do
  @moduledoc "Shared utilities for resolving entity IDs used by REST API and Claude workers"

  alias EyeInTheSky.{Agents, Sessions, Teams}

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

  def resolve_team(params) do
    cond do
      params[:team_id] -> Teams.get_team(params[:team_id])
      params[:team_name] -> Teams.get_team_by_name(params[:team_name])
      true -> nil
    end
  end
end
