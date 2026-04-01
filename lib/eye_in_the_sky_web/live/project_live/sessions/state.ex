defmodule EyeInTheSkyWeb.ProjectLive.Sessions.State do
  @moduledoc """
  Default assign initialization for the project sessions LiveView.
  Keeps mount/3 declarative: it reads as setup, not as a long assign chain.
  """

  import Phoenix.Component, only: [assign: 3]

  alias EyeInTheSkyWeb.ProjectLive.Sessions.Loader

  @page_size 25

  @doc "Returns the pagination page size for session lists."
  def page_size, do: @page_size

  @doc """
  Assigns all defaults and performs the initial data load.
  Call this inside mount/3 after the project is confirmed present.
  """
  def init(socket) do
    socket
    |> assign(:search_query, "")
    |> assign(:sort_by, "last_message")
    |> assign(:session_filter, "all")
    |> assign(:show_new_session_drawer, false)
    |> assign(:show_filter_sheet, false)
    |> assign(:selected_ids, MapSet.new())
    |> assign(:all_agents, [])
    |> assign(:agents, [])
    |> assign(:depths, %{})
    |> assign(:visible_count, page_size())
    |> assign(:has_more, false)
    |> assign(:editing_session_id, nil)
    |> Loader.load_agents()
  end
end
