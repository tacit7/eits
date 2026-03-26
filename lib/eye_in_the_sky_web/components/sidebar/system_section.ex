defmodule EyeInTheSkyWeb.Components.Sidebar.SystemSection do
  use EyeInTheSkyWeb, :html

  attr :sidebar_tab, :atom, required: true
  attr :sidebar_project, :any, default: nil
  attr :collapsed, :boolean, required: true
  attr :expanded_system, :boolean, required: true
  attr :myself, :any, required: true

  def system_section(assigns) do
    ~H"""
    <% system_active = @sidebar_tab in [:config, :jobs, :settings] && is_nil(@sidebar_project) %>
    <button
      phx-click="toggle_system"
      phx-target={@myself}
      data-section-toggle="system"
      class={[
        "flex items-center gap-2.5 w-full text-left text-sm transition-colors",
        if(@collapsed, do: "px-4 py-1 justify-center", else: "px-3 py-1"),
        if(system_active,
          do: "text-base-content/80 hover:bg-base-content/5",
          else: "text-base-content/55 hover:text-base-content/80 hover:bg-base-content/5"
        )
      ]}
      title="System"
    >
      <%= if !@collapsed do %>
        <.icon
          name={if @expanded_system, do: "hero-chevron-down-mini", else: "hero-chevron-right-mini"}
          class="w-3.5 h-3.5 flex-shrink-0"
        />
      <% end %>
      <.icon name="hero-squares-2x2" class="w-4 h-4 flex-shrink-0" />
      <span class={["truncate font-medium", if(@collapsed, do: "hidden")]}>System</span>
      <%= if system_active && !@collapsed do %>
        <span class="ml-auto w-1.5 h-1.5 rounded-full bg-primary flex-shrink-0"></span>
      <% end %>
    </button>

    <%= if @expanded_system || @collapsed do %>
      <div class={if !@collapsed, do: "ml-5 border-l border-base-content/8"}>
        <.section_sub_item
          href="/config"
          icon="hero-cog-6-tooth"
          label="Claude Config"
          active={@sidebar_tab == :config && is_nil(@sidebar_project)}
          collapsed={@collapsed}
        />
        <.section_sub_item
          href="/jobs"
          icon="hero-calendar-days"
          label="Jobs"
          active={@sidebar_tab == :jobs}
          collapsed={@collapsed}
        />
        <.section_sub_item
          href="/settings"
          icon="hero-cog-8-tooth"
          label="Settings"
          active={@sidebar_tab == :settings}
          collapsed={@collapsed}
        />
      </div>
    <% end %>
    """
  end

  attr :href, :string, required: true
  attr :icon, :string, required: true
  attr :label, :string, required: true
  attr :active, :boolean, default: false
  attr :collapsed, :boolean, default: false

  defp section_sub_item(assigns) do
    ~H"""
    <.link
      navigate={@href}
      class={[
        "flex items-center gap-2 text-sm transition-colors",
        if(@collapsed, do: "px-4 py-1 justify-center", else: "pl-3 pr-3 py-0.5"),
        if(@active,
          do: "text-primary bg-primary/5 font-medium",
          else: "text-base-content/50 hover:text-base-content/75 hover:bg-base-content/5"
        )
      ]}
      title={@label}
    >
      <.icon name={@icon} class="w-3.5 h-3.5 flex-shrink-0" />
      <span class={["truncate", if(@collapsed, do: "hidden")]}>{@label}</span>
    </.link>
    """
  end
end
