defmodule EyeInTheSkyWeb.Components.Rail.Flyout.AgentsSection do
  @moduledoc false
  use EyeInTheSkyWeb, :html

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
end
