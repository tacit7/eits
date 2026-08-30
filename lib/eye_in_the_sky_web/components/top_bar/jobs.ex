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
        active_class="bg-primary/10 rounded-box px-3 py-1 text-primary font-medium"
      />
      <:item
        label="Recurring Agents"
        active={@active_tab == :agent_schedules}
        on_click="switch_tab"
        value="agent_schedules"
        active_class="bg-primary/10 rounded-box px-3 py-1 text-primary font-medium"
      />
    </.tab_pills>
    <div class="flex-1" />
    <.search_bar
      id="jobs-top-bar-search"
      size="xs"
      label="Search jobs"
      placeholder="Search jobs..."
      value={@search_query || ""}
      on_change="filter_jobs"
      on_submit="filter_jobs"
      class="w-48"
    />
    <%= if is_nil(@project_id) do %>
      <.link
        navigate="/oban"
        class="focus-ring flex h-7 items-center justify-center rounded-box px-2 text-base-content/45 transition-colors hover:bg-base-content/5 hover:text-base-content/70"
        title="Oban queue dashboard"
      >
        <.icon name="hero-queue-list" class="size-3.5" />
      </.link>
    <% end %>
    <button
      phx-click="toggle_claude_drawer"
      class="focus-ring flex h-7 items-center gap-1 rounded-box border border-base-content/10 px-2 text-mini font-medium text-base-content/55 transition-colors hover:bg-base-content/5 hover:text-base-content/80"
    >
      <.icon name="hero-sparkles" class="size-3" />
      <span>Create with Claude</span>
    </button>
    <button
      phx-click="new_job"
      phx-value-scope={if @project_id, do: "project", else: "global"}
      class="focus-ring flex h-7 items-center gap-1 rounded-box bg-primary px-2 text-mini font-medium text-primary-content transition-colors hover:bg-primary/85"
    >
      <.icon name="hero-plus-mini" class="size-3.5" />
      <span>New Job</span>
    </button>
    """
  end
end
