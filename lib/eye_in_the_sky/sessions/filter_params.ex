defmodule EyeInTheSky.Sessions.FilterParams do
  alias EyeInTheSky.{Agents, Sessions, Utils.ToolHelpers}

  @doc """
  Builds a keyword list of filter options from raw query params map.
  Used by the session list API endpoint.
  """
  def build(params) do
    agent_int_id = resolve_agent_id(params["agent_id"])

    parent_session_int_id =
      if params["parent_session_id"] do
        case Sessions.resolve(params["parent_session_id"]) do
          {:ok, s} -> s.id
          _ -> nil
        end
      end

    include_archived = params["include_archived"] in ["true", "1", true]
    name = if params["name"] && params["name"] != "", do: params["name"]

    agent_def_slug =
      if params["agent_def_slug"] && params["agent_def_slug"] != "", do: params["agent_def_slug"]

    [search_query: params["q"] || ""]
    |> maybe_put(:project_id, params["project_id"] && ToolHelpers.parse_int(params["project_id"], nil))
    |> maybe_put(:status_filter, params["status"])
    |> maybe_put(:agent_id, agent_int_id)
    |> maybe_put(:parent_session_id, parent_session_int_id)
    |> maybe_put(:include_archived, include_archived && true)
    |> maybe_put(:name_filter, name)
    |> maybe_put(:agent_def_slug, agent_def_slug)
    |> Keyword.put(:limit, ToolHelpers.parse_int(params["limit"], 20))
  end

  defp resolve_agent_id(nil), do: nil
  defp resolve_agent_id(""), do: nil

  defp resolve_agent_id(raw) when is_binary(raw) do
    case ToolHelpers.parse_int(raw) do
      nil ->
        case Agents.get_agent_by_uuid(raw) do
          {:ok, %{id: id}} -> id
          _ -> nil
        end

      n ->
        n
    end
  end

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, _key, false), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)
end
