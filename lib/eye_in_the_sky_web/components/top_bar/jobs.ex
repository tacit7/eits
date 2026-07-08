defmodule EyeInTheSkyWeb.TopBar.Jobs do
  @moduledoc false
  use Phoenix.Component
  import EyeInTheSkyWeb.CoreComponents

  attr :active_tab, :atom, default: :all_jobs
  attr :search_query, :string, default: ""
  attr :project_id, :any, default: nil

  def toolbar(assigns) do
    ~H"""
    <.tab_pills value_key="tab">
      <:item
        label="All Jobs"
        active={@active_tab in [:all_jobs, nil]}
        on_click="switch_tab"
        value="all_jobs"
        active_class="bg-primary/10 rounded-md px-3 py-1 text-primary font-medium"
      />
      <:item
        label="Recurring Agents"
        active={@active_tab == :agent_schedules}
        on_click="switch_tab"
        value="agent_schedules"
        active_class="bg-primary/10 rounded-md px-3 py-1 text-primary font-medium"
      />
    </.tab_pills>
    <.search_bar
      id="jobs-top-bar-search"
      size="xs"
      label="Search jobs"
      placeholder="Search jobs…"
      value={@search_query || ""}
      on_change="filter_jobs"
      on_submit="filter_jobs"
      class="w-44"
    />
    <div class="flex-1" />
    <%= if is_nil(@project_id) do %>
      <.link
        navigate="/oban"
        class="btn btn-ghost btn-xs text-base-content/50"
        title="Oban queue dashboard"
      >
        <.icon name="hero-queue-list" class="size-3.5" />
      </.link>
    <% end %>
    <button phx-click="toggle_claude_drawer" class="btn btn-outline btn-xs gap-1">
      <.icon name="hero-sparkles" class="size-3" /> Create with Claude
    </button>
    <button
      phx-click="new_job"
      phx-value-scope={if @project_id, do: "project", else: "global"}
      class="btn btn-primary btn-xs"
    >
      + New Job
    </button>
    """
  end
end
