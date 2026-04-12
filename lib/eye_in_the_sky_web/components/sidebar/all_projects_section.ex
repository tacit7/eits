defmodule EyeInTheSkyWeb.Components.Sidebar.AllProjectsSection do
  @moduledoc false
  use EyeInTheSkyWeb, :html

  attr :sidebar_tab, :atom, required: true
  attr :sidebar_project, :any, default: nil
  attr :collapsed, :boolean, required: true
  attr :expanded_all_projects, :boolean, required: true
  attr :notification_count, :integer, required: true
  attr :myself, :any, required: true

  def all_projects_section(assigns) do
    ~H"""
    <% overview_active = @sidebar_tab in [:sessions, :tasks, :prompts, :notes, :skills, :teams, :notifications, :usage] && is_nil(@sidebar_project) %>
    <button
      phx-click="toggle_all_projects"
      phx-target={@myself}
      data-section-toggle="overview"
      class={[
        "flex items-center gap-2.5 w-full text-left text-sm transition-colors min-h-[44px]",
        if(@collapsed, do: "px-4 py-2 justify-center", else: "px-3 py-2"),
        if(overview_active,
          do: "text-base-content/80 hover:bg-base-content/5",
          else: "text-base-content/55 hover:text-base-content/80 hover:bg-base-content/5"
        )
      ]}
      title="Overview"
    >
      <%= if !@collapsed do %>
        <.icon
          name={if @expanded_all_projects, do: "hero-chevron-down-mini", else: "hero-chevron-right-mini"}
          class="w-3.5 h-3.5 flex-shrink-0"
        />
      <% end %>
      <.icon name="hero-rectangle-stack" class="w-4 h-4 flex-shrink-0" />
      <span class={["truncate font-medium", if(@collapsed, do: "hidden")]}>Workspace</span>
      <%= if overview_active && !@collapsed do %>
        <span class="ml-auto w-1.5 h-1.5 rounded-full bg-primary flex-shrink-0"></span>
      <% end %>
    </button>

    <%= if @expanded_all_projects || @collapsed do %>
      <div class={if !@collapsed, do: "ml-5 border-l border-base-content/8"}>
        <.section_sub_item
          href="/"
          icon="hero-cpu-chip"
          label="Sessions"
          active={@sidebar_tab == :sessions && is_nil(@sidebar_project)}
          collapsed={@collapsed}
        />
        <.section_sub_item
          href="/tasks"
          icon="hero-clipboard-document-list"
          label="Tasks"
          active={@sidebar_tab == :tasks && is_nil(@sidebar_project)}
          collapsed={@collapsed}
        />
        <.section_sub_item
          href="/prompts"
          icon="hero-chat-bubble-left-right"
          label="Prompts"
          active={@sidebar_tab == :prompts && is_nil(@sidebar_project)}
          collapsed={@collapsed}
        />
        <.section_sub_item
          href="/notes"
          icon="hero-document-text"
          label="Notes"
          active={@sidebar_tab == :notes && is_nil(@sidebar_project)}
          collapsed={@collapsed}
        />
        <.section_sub_item
          href="/skills"
          icon="hero-bolt"
          label="Skills"
          active={@sidebar_tab == :skills}
          collapsed={@collapsed}
        />
        <.section_sub_item
          href="/teams"
          icon="hero-users"
          label="Teams"
          active={@sidebar_tab == :teams}
          collapsed={@collapsed}
        />
        <.section_sub_item
          href="/usage"
          icon="hero-chart-bar"
          label="Usage"
          active={@sidebar_tab == :usage}
          collapsed={@collapsed}
        />
        <button
          phx-click="toggle"
          phx-target="#canvas-overlay"
          class={[
            "flex items-center gap-2 text-sm transition-colors w-full min-h-[44px]",
            if(@collapsed, do: "px-4 py-3 justify-center", else: "pl-3 pr-3 py-3"),
            "text-base-content/50 hover:text-base-content/75 hover:bg-base-content/5"
          ]}
          title="Canvas"
        >
          <.icon name="hero-squares-2x2" class="w-3.5 h-3.5 flex-shrink-0" />
          <span class={["truncate", if(@collapsed, do: "hidden")]}>Canvas</span>
        </button>
        <.section_notification_item
          href="/notifications"
          active={@sidebar_tab == :notifications}
          collapsed={@collapsed}
          count={@notification_count}
        />
      </div>
    <% end %>
    """
  end

  defp section_sub_item(assigns) do
    ~H"""
    <.link
      navigate={@href}
      class={[
        "flex items-center gap-2 text-sm transition-colors min-h-[44px]",
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

  attr :href, :string, required: true
  attr :active, :boolean, default: false
  attr :collapsed, :boolean, default: false
  attr :count, :integer, default: 0

  defp section_notification_item(assigns) do
    ~H"""
    <.link
      navigate={@href}
      class={[
        "flex items-center gap-2 text-sm transition-colors min-h-[44px]",
        if(@collapsed, do: "px-4 py-3 justify-center", else: "pl-3 pr-3 py-3"),
        if(@active,
          do: "text-primary bg-primary/5 font-medium",
          else: "text-base-content/50 hover:text-base-content/75 hover:bg-base-content/5"
        )
      ]}
      title="Notifications"
    >
      <div class="relative">
        <.icon name="hero-bell" class="w-3.5 h-3.5 flex-shrink-0" />
        <%= if @count > 0 do %>
          <span class="absolute -top-1.5 -right-1.5 badge badge-xs badge-primary text-xs leading-none min-w-[18px] h-[18px] px-1">
            {if @count > 99, do: "99+", else: @count}
          </span>
        <% end %>
      </div>
      <span class={["truncate", if(@collapsed, do: "hidden")]}>Notifications</span>
    </.link>
    """
  end
end
