defmodule EyeInTheSkyWeb.Components.Rail.Flyout.AgentsSection do
  @moduledoc false
  use EyeInTheSkyWeb, :html

  attr :agent_search, :string, default: ""
  attr :agent_scope, :string, default: "all"
  attr :myself, :any, required: true

  def agents_filters(assigns) do
    ~H"""
    <div class="px-2.5 py-2 border-b border-base-content/8 flex flex-col gap-2">
      <%!-- Search --%>
      <div class="relative">
        <span class="absolute left-2 top-1/2 -translate-y-1/2 text-base-content/30 pointer-events-none">
          <.icon name="hero-magnifying-glass-mini" class="size-3" />
        </span>
        <input
          type="text"
          value={@agent_search}
          placeholder="Search agents…"
          phx-keyup="update_agent_search"
          phx-target={@myself}
          phx-debounce="200"
          class="w-full pl-6 pr-2 py-1 text-xs bg-base-content/5 border border-base-content/10 rounded focus:outline-none focus:border-primary/40 placeholder:text-base-content/30"
        />
      </div>

      <%!-- Scope pills --%>
      <div class="flex items-center gap-0.5">
        <.scope_pill label="All" value="all" current={@agent_scope} myself={@myself} event="set_agent_scope" />
        <.scope_pill label="Global" value="global" current={@agent_scope} myself={@myself} event="set_agent_scope" />
        <.scope_pill label="Project" value="project" current={@agent_scope} myself={@myself} event="set_agent_scope" />
      </div>
    </div>
    """
  end

  attr :agents, :list, default: []
  attr :myself, :any, required: true

  def agents_content(assigns) do
    ~H"""
    <.agent_row :for={agent <- @agents} agent={agent} myself={@myself} />
    <%= if @agents == [] do %>
      <div class="px-3 py-4 text-xs text-base-content/35 text-center">No agents</div>
    <% end %>
    """
  end

  attr :agent, :map, required: true
  attr :myself, :any, required: true

  def agent_row(assigns) do
    ~H"""
    <button
      type="button"
      phx-click="open_new_session_with_agent"
      phx-value-slug={@agent.slug}
      phx-value-name={@agent.name || @agent.slug}
      phx-target={@myself}
      data-vim-flyout-item
      class="w-full flex items-center gap-2 px-3 py-2 text-sm text-base-content/65 hover:text-base-content/90 hover:bg-base-content/5 transition-colors text-left [&.vim-nav-focused]:ring-2 [&.vim-nav-focused]:ring-primary/50 [&.vim-nav-focused]:rounded"
    >
      <.custom_icon name="lucide-robot" class="size-3 flex-shrink-0 text-base-content/30" />
      <span class="truncate text-xs font-medium">{@agent.name || @agent.slug}</span>
    </button>
    """
  end

  attr :label, :string, required: true
  attr :value, :string, required: true
  attr :current, :string, default: "all"
  attr :myself, :any, required: true
  attr :event, :string, required: true

  defp scope_pill(assigns) do
    ~H"""
    <% active = @current == @value %>
    <button
      phx-click={@event}
      phx-value-scope={@value}
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
end
