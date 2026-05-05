defmodule EyeInTheSkyWeb.Components.Rail.Flyout.SessionsSection do
  @moduledoc false
  use EyeInTheSkyWeb, :html

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
          phx-change="update_session_name_filter"
          phx-target={@myself}
          phx-debounce="200"
          class="w-full pl-6 pr-2 py-1 text-xs bg-base-content/5 border border-base-content/10 rounded focus:outline-none focus:border-primary/40 placeholder:text-base-content/30"
        />
      </div>

      <%!-- Sort + Show row --%>
      <div class="flex items-center justify-between gap-2">
        <%!-- Sort tabs --%>
        <div class="flex items-center gap-0.5">
          <.sort_tab label="Recent" value="last_activity" current={@session_sort} myself={@myself} />
          <.sort_tab label="Created" value="created" current={@session_sort} myself={@myself} />
          <.sort_tab label="Name" value="name" current={@session_sort} myself={@myself} />
        </div>

        <%!-- Show toggle --%>
        <div class="flex items-center gap-0.5">
          <.show_tab label="20" value="twenty" current={@session_show} myself={@myself} />
          <.show_tab label="Active" value="all_active" current={@session_show} myself={@myself} />
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

  defp sort_tab(assigns) do
    ~H"""
    <% active = to_string(@current) == @value %>
    <button
      phx-click="set_session_sort"
      phx-value-sort={@value}
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
      class="flex items-center gap-2 px-3 py-2 text-sm text-base-content/65 hover:text-base-content/90 hover:bg-base-content/5 transition-colors [&.vim-nav-focused]:ring-2 [&.vim-nav-focused]:ring-primary/50 [&.vim-nav-focused]:rounded"
    >
      <.status_dot status={@session.status} size="xs" />
      <span class="truncate font-medium text-xs">{@session.name || "unnamed"}</span>
    </.link>
    """
  end
end
