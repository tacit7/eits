defmodule EyeInTheSkyWebWeb.Helpers.AgentFilters do
  @moduledoc """
  Helpers for filtering project agents by search and status.
  """

  @doc """
  Filters a list of agents using `:search_query` and `:status_filter` in `params`.
  """
  def filter_agents(%{project: %{agents: agents}} = params) when is_list(agents) do
    query = String.downcase(params[:search_query] || "")
    status_filter = params[:status_filter] || "all"

    agents
    |> Enum.filter(fn agent ->
      search_match?(agent, query) and status_match?(agent, status_filter)
    end)
  end

  defp search_match?(_agent, ""), do: true

  defp search_match?(agent, query) do
    Enum.any?(
      [
        agent.id,
        agent.description,
        agent.feature_description,
        agent.session_id
      ],
      fn val -> String.contains?(String.downcase(val || ""), query) end
    )
  end

  defp status_match?(_agent, "all"), do: true
  defp status_match?(_agent, _status), do: true
end
