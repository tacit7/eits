defmodule EyeInTheSkyWeb.Components.Rail.Flyout.TasksSection do
  @moduledoc false
  use EyeInTheSkyWeb, :html

  alias EyeInTheSkyWeb.Components.Rail.Flyout.Helpers

  attr :task_search, :string, default: ""
  attr :state_filter, :any, default: nil
  attr :myself, :any, required: true

  def tasks_filters(assigns) do
    ~H"""
    <div class="px-2.5 py-2 border-b border-base-content/8 flex flex-col gap-2">
      <%!-- Search --%>
      <div class="relative">
        <span class="absolute left-2 top-1/2 -translate-y-1/2 text-base-content/30 pointer-events-none">
          <.icon name="hero-magnifying-glass-mini" class="size-3" />
        </span>
        <input
          type="text"
          value={@task_search}
          placeholder="Search tasks…"
          phx-keyup="update_task_search"
          phx-change="update_task_search"
          phx-target={@myself}
          phx-debounce="200"
          class="w-full pl-6 pr-2 py-1 text-xs bg-base-content/5 border border-base-content/10 rounded focus:outline-none focus:border-primary/40 placeholder:text-base-content/30"
        />
      </div>

      <%!-- State filter pills --%>
      <div class="flex flex-wrap gap-0.5">
        <.state_pill label="All" value="all" current={@state_filter} myself={@myself} />
        <.state_pill label="To Do" value="1" current={@state_filter} myself={@myself} />
        <.state_pill label="In Progress" value="2" current={@state_filter} myself={@myself} />
        <.state_pill label="In Review" value="4" current={@state_filter} myself={@myself} />
        <.state_pill label="Done" value="3" current={@state_filter} myself={@myself} />
      </div>
    </div>
    """
  end

  attr :tasks, :list, default: []
  attr :task_search, :string, default: ""
  attr :state_filter, :any, default: nil
  attr :sidebar_project, :any, default: nil
  attr :myself, :any, required: true

  def tasks_content(assigns) do
    ~H"""
    <.task_row :for={t <- @tasks} task={t} />

    <%= if @tasks == [] do %>
      <% filtering = @task_search != "" or not is_nil(@state_filter) %>
      <div class="px-3 py-4 text-xs text-base-content/35 text-center">
        {if filtering, do: "No matching tasks", else: "No tasks"}
      </div>
    <% end %>
    """
  end

  attr :label, :string, required: true
  attr :value, :string, required: true
  attr :current, :any, default: nil
  attr :myself, :any, required: true

  defp state_pill(assigns) do
    ~H"""
    <% active = (@value == "all" and is_nil(@current)) or to_string(@current) == @value %>
    <button
      phx-click="set_task_state_filter"
      phx-value-state={@value}
      phx-target={@myself}
      class={[
        "text-nano px-1.5 py-0.5 rounded transition-colors",
        if(active,
          do: "bg-primary/15 text-primary font-medium",
          else: "text-base-content/45 hover:text-base-content/70 hover:bg-base-content/8"
        )
      ]}
    >
      {@label}
    </button>
    """
  end

  attr :task, :map, required: true

  def task_row(assigns) do
    ~H"""
    <.link
      navigate={
        if @task.project_id,
          do: "/projects/#{@task.project_id}/tasks?task_id=#{@task.id}",
          else: "/projects"
      }
      data-vim-flyout-item
      class="flex items-center gap-2 px-3 py-2 text-xs text-base-content/65 hover:text-base-content/90 hover:bg-base-content/5 transition-colors [&.vim-nav-focused]:ring-2 [&.vim-nav-focused]:ring-primary/50 [&.vim-nav-focused]:rounded"
    >
      <span class={["w-1.5 h-1.5 rounded-full flex-shrink-0 mt-px", task_state_dot(@task.state_id)]} />
      <span class="truncate">{@task.title}</span>
    </.link>
    """
  end

  def task_state_dot(1), do: "bg-base-content/30"
  def task_state_dot(2), do: "bg-blue-500"
  def task_state_dot(3), do: "bg-green-500"
  def task_state_dot(4), do: "bg-amber-400"
  def task_state_dot(_), do: "bg-base-content/20"

  attr :project, :any, default: nil
  attr :section, :atom, required: true

  def nav_links(%{project: nil} = assigns) do
    ~H"""
    <div class="px-3 py-4 text-xs text-base-content/35 text-center">Select a project</div>
    """
  end

  def nav_links(%{section: :tasks} = assigns) do
    ~H"""
    <Helpers.simple_link
      href={"/projects/#{@project.id}/kanban"}
      label={"#{@project.name} Board"}
      icon="hero-squares-2x2"
    />
    """
  end

  def nav_links(%{section: :prompts} = assigns) do
    ~H"""
    <Helpers.simple_link
      href={"/projects/#{@project.id}/prompts"}
      label={"#{@project.name} Prompts"}
      icon="hero-folder"
    />
    """
  end

  def nav_links(%{section: :notes} = assigns) do
    ~H"""
    <Helpers.simple_link
      href={"/projects/#{@project.id}/notes"}
      label={"#{@project.name} Notes"}
      icon="hero-folder"
    />
    """
  end

  def nav_links(%{section: :sessions} = assigns) do
    ~H"""
    <Helpers.simple_link
      href={"/projects/#{@project.id}/sessions"}
      label="List"
      icon="hero-list-bullet"
    />
    """
  end
end
