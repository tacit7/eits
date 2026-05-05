defmodule EyeInTheSkyWeb.Components.Rail.Flyout.SkillsSection do
  @moduledoc false
  use EyeInTheSkyWeb, :html

  attr :skill_search, :string, default: ""
  attr :skill_scope, :string, default: "all"
  attr :myself, :any, required: true

  def skills_filters(assigns) do
    ~H"""
    <div class="px-2.5 py-2 border-b border-base-content/8 flex flex-col gap-2">
      <%!-- Search --%>
      <div class="relative">
        <span class="absolute left-2 top-1/2 -translate-y-1/2 text-base-content/30 pointer-events-none">
          <.icon name="hero-magnifying-glass-mini" class="size-3" />
        </span>
        <input
          type="text"
          value={@skill_search}
          placeholder="Search skills…"
          phx-keyup="update_skill_search"
          phx-change="update_skill_search"
          phx-target={@myself}
          phx-debounce="200"
          class="w-full pl-6 pr-2 py-1 text-xs bg-base-content/5 border border-base-content/10 rounded focus:outline-none focus:border-primary/40 placeholder:text-base-content/30"
        />
      </div>

      <%!-- Scope pills --%>
      <div class="flex items-center gap-0.5">
        <.scope_pill label="All" value="all" current={@skill_scope} myself={@myself} />
        <.scope_pill label="Global" value="global" current={@skill_scope} myself={@myself} />
        <.scope_pill label="Project" value="project" current={@skill_scope} myself={@myself} />
      </div>
    </div>
    """
  end

  attr :skills, :list, default: []

  def skills_content(assigns) do
    ~H"""
    <.skill_row :for={s <- @skills} skill={s} />
    <%= if @skills == [] do %>
      <div class="px-3 py-4 text-xs text-base-content/35 text-center">No skills</div>
    <% end %>
    """
  end

  attr :skill, :map, required: true

  defp skill_row(assigns) do
    ~H"""
    <.link
      navigate="/skills"
      data-vim-flyout-item
      class="flex items-center gap-2 px-3 py-2 text-xs text-base-content/65 hover:text-base-content/90 hover:bg-base-content/5 transition-colors [&.vim-nav-focused]:ring-2 [&.vim-nav-focused]:ring-primary/50 [&.vim-nav-focused]:rounded"
    >
      <.icon name="hero-slash" class="size-3 flex-shrink-0 text-base-content/30" />
      <span class="truncate">{@skill.slug}</span>
    </.link>
    """
  end

  attr :label, :string, required: true
  attr :value, :string, required: true
  attr :current, :string, default: "all"
  attr :myself, :any, required: true

  defp scope_pill(assigns) do
    ~H"""
    <% active = @current == @value %>
    <button
      phx-click="set_skill_scope"
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
