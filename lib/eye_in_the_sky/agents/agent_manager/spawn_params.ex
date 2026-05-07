defmodule EyeInTheSky.Agents.AgentManager.SpawnParams do
  @moduledoc "Builds keyword opts for create_agent from raw HTTP spawn params."

  @months ~w(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec)

  # Name resolution priority:
  # 1. Explicit "name" param (trimmed, non-empty)
  # 2. "member_name @ team_name" when both present
  # 3. "member_name" alone
  # 4. Agent definition slug (e.g. "setup-guardian")
  # 5. Datetime stamp "May 7 14:23:45" fallback
  def resolve_session_name(%{"name" => name} = params, team)
      when is_binary(name) and name != "" do
    case String.trim(name) do
      "" -> resolve_session_name(Map.delete(params, "name"), team)
      trimmed -> trimmed
    end
  end

  def resolve_session_name(params, %{name: team_name})
      when is_binary(team_name) do
    member = params["member_name"]

    if member,
      do: "#{member} @ #{team_name}",
      else: params["agent"] || timestamp_name()
  end

  def resolve_session_name(%{"member_name" => member}, _team) when is_binary(member),
    do: member

  def resolve_session_name(params, _team),
    do: params["agent"] || timestamp_name()

  defp timestamp_name do
    %{month: m, day: d, hour: h, minute: min, second: s} = DateTime.utc_now()
    month = Enum.at(@months, m - 1)
    "#{month} #{d} #{zero_pad(h)}:#{zero_pad(min)}:#{zero_pad(s)}"
  end

  defp zero_pad(n), do: String.pad_leading(Integer.to_string(n), 2, "0")

  def build(params, team) do
    name = resolve_session_name(params, team)

    [
      instructions: params["instructions"],
      model: params["model"],
      agent_type: params["provider"] || "claude",
      project_id: params["project_id"],
      project_name: params["project_name"],
      project_path: params["project_path"],
      name: name,
      description: name,
      worktree: params["worktree"],
      stash_if_dirty: params["stash_if_dirty"] == true,
      effort_level: params["effort_level"],
      parent_agent_id: params["parent_agent_id"],
      parent_session_id: params["parent_session_id"],
      agent: params["agent"],
      bypass_sandbox: params["bypass_sandbox"] == true
    ]
  end
end
