defmodule EyeInTheSkyWeb.Components.Rail.Flyout.AgentsSection do
  @moduledoc false
  use EyeInTheSkyWeb, :html

  attr :agent_search, :string, default: ""
  attr :agent_scope, :string, default: "all"

  def agents_filters(assigns) do
    ~H"""
    <div class="px-2.5 py-2 border-b border-base-content/8 flex flex-col gap-2">
      <%!-- Search --%>
      <div class="relative">
        <span class="absolute left-2 top-1/2 -translate-y-1/2 text-base-content/30 pointer-events-none">
          <.icon name="hero-magnifying-glass-mini" class="size-3" />
        </span>
        <input
          id="rail-agent-search"
          type="text"
          value={@agent_search}
          placeholder="Search agents..."
          phx-keyup="update_agent_search"
          phx-debounce="200"
          class="focus-ring h-7 w-full rounded-box border border-base-content/10 bg-base-content/5 pl-6 pr-2 text-micro text-base-content/80 placeholder:text-base-content/30 focus:border-primary/40"
        />
      </div>

      <%!-- Scope pills --%>
      <div class="flex items-center gap-0.5">
        <.scope_pill
          label="All"
          value="all"
          current={@agent_scope}
          event="set_agent_scope"
        />
        <.scope_pill
          label="Global"
          value="global"
          current={@agent_scope}
          event="set_agent_scope"
        />
        <.scope_pill
          label="Project"
          value="project"
          current={@agent_scope}
          event="set_agent_scope"
        />
      </div>
    </div>
    """
  end

  attr :agents, :list, default: []

  def agents_content(assigns) do
    ~H"""
    <.agent_row :for={agent <- @agents} agent={agent} />
    <%= if @agents == [] do %>
      <div class="px-3 py-4 text-mini text-base-content/35 text-center">No agents</div>
    <% end %>
    """
  end

  attr :agent, :map, required: true

  def agent_row(assigns) do
    ~H"""
    <button
      type="button"
      phx-click="open_new_session_with_agent"
      phx-value-slug={@agent.slug}
      phx-value-name={@agent.name || @agent.slug}
      data-vim-flyout-item
      class="focus-ring flex h-8 w-full items-center gap-2 rounded-box px-3 text-left text-mini text-base-content/65 transition-colors hover:bg-base-content/5 hover:text-base-content/90 [&.vim-nav-focused]:ring-2 [&.vim-nav-focused]:ring-primary/50"
    >
      <.custom_icon name="lucide-robot" class="size-3 flex-shrink-0 text-base-content/30" />
      <span class="truncate text-mini font-medium">{@agent.name || @agent.slug}</span>
    </button>
    """
  end

  attr :label, :string, required: true
  attr :value, :string, required: true
  attr :current, :string, default: "all"
  attr :event, :string, required: true

  defp scope_pill(assigns) do
    ~H"""
    <% active = @current == @value %>
    <button
      type="button"
      phx-click={@event}
      phx-value-scope={@value}
      class={[
        "focus-ring rounded-box px-1.5 py-0.5 text-nano transition-colors",
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
end
