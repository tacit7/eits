defmodule EyeInTheSkyWebWeb.Components.OverviewNav do
  use Phoenix.Component
  import EyeInTheSkyWebWeb.CoreComponents, only: [icon: 1]

  use Phoenix.VerifiedRoutes,
    endpoint: EyeInTheSkyWebWeb.Endpoint,
    router: EyeInTheSkyWebWeb.Router

  attr :current_tab, :atom, required: true

  def render(assigns) do
    ~H"""
    <div class="border-b border-base-300 bg-base-100">
      <div class="px-4 sm:px-6 lg:px-8">
        <div class="flex items-center gap-1 -mb-px">
          <.nav_tab href={~p"/"} icon="hero-clock" label="Sessions" active={@current_tab == :sessions} />
          <.nav_tab href={~p"/notes"} icon="hero-document-text" label="Notes" active={@current_tab == :notes} />
          <.nav_tab href={~p"/tasks"} icon="hero-clipboard-document-list" label="Tasks" active={@current_tab == :tasks} />
          <.nav_tab href={~p"/usage"} icon="hero-chart-bar" label="Usage" active={@current_tab == :usage} />
          <.nav_tab href={~p"/prompts"} icon="hero-chat-bubble-left-right" label="Prompts" active={@current_tab == :prompts} />
          <.nav_tab href={~p"/skills"} icon="hero-bolt" label="Skills" active={@current_tab == :skills} />
          <.nav_tab href={~p"/config"} icon="hero-cog-6-tooth" label="Claude Config" active={@current_tab == :config} />
          <.nav_tab href={~p"/jobs"} icon="hero-calendar-days" label="Jobs" active={@current_tab == :jobs} />
          <.nav_tab href={~p"/settings"} icon="hero-cog-8-tooth" label="Settings" active={@current_tab == :settings} />
        </div>
      </div>
    </div>
    """
  end

  attr :href, :string, required: true
  attr :icon, :string, required: true
  attr :label, :string, required: true
  attr :active, :boolean, default: false

  defp nav_tab(assigns) do
    ~H"""
    <a
      href={@href}
      class={[
        "flex items-center gap-2 px-4 py-2 border-b-2 text-sm transition-colors",
        if(@active,
          do: "border-primary font-medium text-base-content",
          else: "border-transparent hover:border-base-content/20 text-base-content/60 hover:text-base-content"
        )
      ]}
    >
      <.icon name={@icon} class="w-4 h-4" />
      {@label}
    </a>
    """
  end
end
