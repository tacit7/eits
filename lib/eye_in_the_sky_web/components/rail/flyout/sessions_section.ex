defmodule EyeInTheSkyWeb.Components.Rail.Flyout.SessionsSection do
  @moduledoc false
  use EyeInTheSkyWeb, :html
  import EyeInTheSkyWeb.Helpers.ViewHelpers, only: [relative_time: 1]

  attr :session_sort, :atom, default: :last_activity
  attr :session_name_filter, :string, default: ""
  attr :session_show, :atom, default: :twenty
  attr :myself, :any, required: true

  def sessions_filters(assigns) do
    ~H"""
    <div class="px-2.5 py-2 border-b border-base-content/8 flex flex-col gap-2">
      <%!-- Search --%>
      <div class="relative">
        <span class="absolute left-2 top-1/2 -translate-y-1/2 text-base-content/30 pointer-events-none">
          <.icon name="hero-magnifying-glass-mini" class="size-3" />
        </span>
        <input
          type="text"
          value={@session_name_filter}
          placeholder="Search sessions…"
          phx-keyup="update_session_name_filter"
          phx-target={@myself}
          phx-debounce="200"
          class="w-full pl-6 pr-2 py-1 text-xs bg-base-content/5 border border-base-content/10 rounded focus:outline-none focus:border-primary/40 placeholder:text-base-content/30"
        />
      </div>

      <%!-- Sort dropdown + Show toggle --%>
      <div class="flex items-center justify-between gap-2">
        <%!-- Sort: filter icon + native select (form wrapper required for phx-change on select) --%>
        <div class="flex items-center gap-1">
          <.icon name="hero-funnel-mini" class="size-3 text-base-content/30 flex-shrink-0" />
          <form phx-change="set_session_sort" phx-target={@myself}>
            <select
              name="sort"
              class="text-nano bg-transparent text-base-content/55 focus:outline-none cursor-pointer hover:text-base-content/80 transition-colors"
            >
              <option value="last_activity" selected={@session_sort == :last_activity}>Recent</option>
              <option value="created" selected={@session_sort == :created}>Created</option>
              <option value="name" selected={@session_sort == :name}>Name</option>
            </select>
          </form>
        </div>

        <%!-- Show toggle --%>
        <div class="flex items-center gap-0.5">
          <.show_tab label="20" value="twenty" current={@session_show} myself={@myself} />
          <.show_tab label="All" value="all_active" current={@session_show} myself={@myself} />
        </div>
      </div>
    </div>
    """
  end

  attr :sessions, :list, required: true

  def sessions_content(assigns) do
    ~H"""
    <.session_row :for={s <- @sessions} session={s} />

    <%= if @sessions == [] do %>
      <div class="px-3 py-4 text-xs text-base-content/35 text-center">No sessions</div>
    <% end %>
    """
  end

  attr :label, :string, required: true
  attr :value, :string, required: true
  attr :current, :atom, required: true
  attr :myself, :any, required: true

  defp show_tab(assigns) do
    ~H"""
    <% active = to_string(@current) == @value %>
    <button
      phx-click="set_session_show"
      phx-value-show={@value}
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

  attr :session, :map, required: true

  def session_row(assigns) do
    ~H"""
    <.link
      navigate={"/dm/#{@session.id}"}
      data-vim-flyout-item
      class="flyout-session-row flex items-start gap-2 px-3 py-1.5 text-sm text-base-content/65 hover:text-base-content/90 hover:bg-base-content/5 transition-colors [&.vim-nav-focused]:ring-2 [&.vim-nav-focused]:ring-primary/50 [&.vim-nav-focused]:rounded"
    >
      <.status_dot status={@session.status} size="xs" class="mt-[3px] flex-shrink-0" />
      <div class="min-w-0 flex-1">
        <div class="truncate font-medium text-xs text-base-content/75">
          {@session.name || "unnamed"}
        </div>
        <div class="text-nano text-base-content/35 mt-0.5 flex items-center gap-1">
          <span class="capitalize">{@session.status}</span>
          <%= if @session.last_activity_at do %>
            <span>·</span>
            <span>{relative_time(@session.last_activity_at)}</span>
          <% end %>
        </div>
      </div>
    </.link>
    """
  end
end
