defmodule EyeInTheSkyWeb.Components.Sidebar.SystemSection do
  @moduledoc false
  use EyeInTheSkyWeb, :html

  attr :sidebar_tab, :atom, required: true
  attr :sidebar_project, :any, default: nil
  attr :collapsed, :boolean, required: true
  attr :expanded_system, :boolean, required: true
  attr :myself, :any, required: true

  def system_section(assigns) do
    ~H"""
    <div class={["px-3 pt-3 pb-0.5", if(@collapsed, do: "hidden")]}>
      <span class="text-xs font-semibold uppercase tracking-widest text-base-content/30">
        System
      </span>
    </div>
    <.system_nav_item
      href="/config"
      icon="hero-cog-6-tooth"
      label="Config"
      active={@sidebar_tab == :config && is_nil(@sidebar_project)}
      collapsed={@collapsed}
    />
    <.system_nav_item
      href="/jobs"
      icon="hero-clock"
      label="Jobs"
      active={@sidebar_tab == :jobs && is_nil(@sidebar_project)}
      collapsed={@collapsed}
    />
    <.system_nav_item
      href="/settings"
      icon="hero-cog-8-tooth"
      label="Settings"
      active={@sidebar_tab == :settings && is_nil(@sidebar_project)}
      collapsed={@collapsed}
    />
    """
  end

  attr :href, :string, required: true
  attr :icon, :string, required: true
  attr :label, :string, required: true
  attr :active, :boolean, default: false
  attr :collapsed, :boolean, default: false

  defp system_nav_item(assigns) do
    ~H"""
    <.link
      navigate={@href}
      class={[
        "flex items-center gap-2 text-sm transition-colors",
        if(@collapsed, do: "px-4 py-3 justify-center", else: "pl-3 pr-3 py-3"),
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
