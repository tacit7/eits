defmodule EyeInTheSkyWeb.TopBar.DM do
  @moduledoc false
  use Phoenix.Component

  use Phoenix.VerifiedRoutes,
    endpoint: EyeInTheSkyWeb.Endpoint,
    router: EyeInTheSkyWeb.Router,
    statics: EyeInTheSkyWeb.static_paths()

  alias Phoenix.LiveView.JS
  import EyeInTheSkyWeb.CoreComponents

  import Phoenix.LiveView.Helpers, only: []

  attr :dm_active_tab, :string, default: "messages"
  attr :dm_message_search_query, :string, default: nil
  attr :dm_active_timer, :map, default: nil

  def toolbar(assigns) do
    ~H"""
    <%!-- DM: search first, then tab pills --%>
    <%= if @dm_active_tab in ["messages", nil] && not is_nil(@dm_message_search_query) do %>
      <.search_bar
        id="top-bar-dm-search"
        size="xs"
        label="Search messages"
        placeholder="Search messages..."
        value={@dm_message_search_query}
        on_change="search_messages"
        on_submit="search_messages"
        class="w-48"
      />
    <% end %>
    <div class="flex items-center gap-1 bg-base-200/40 rounded-lg p-0.5">
      <%= for {tab, label} <- [
        {"messages", "Messages"},
        {"tasks", "Tasks"},
        {"commits", "Commits"},
        {"notes", "Notes"},
        {"context", "Context"},
        {"settings", "Settings"}
      ] do %>
        <button
          phx-click="change_tab"
          phx-value-tab={tab}
          class={"px-2.5 py-1 rounded-md text-[11px] font-medium transition-all duration-150 " <>
            if(@dm_active_tab == tab,
              do: "bg-base-100 text-base-content shadow-sm",
              else: "text-base-content/45 hover:text-base-content/70"
            )}
        >
          {label}
        </button>
      <% end %>
    </div>
    <div class="flex-1" />
    <%!-- ... menu --%>
    <div class="dropdown dropdown-end">
      <button
        tabindex="0"
        class="btn btn-ghost btn-square w-7 h-7 text-base-content/50 hover:text-base-content/75"
        aria-label="More options"
      >
        <.icon name="hero-ellipsis-horizontal" class="w-4 h-4" />
      </button>
      <ul
        tabindex="0"
        class="dropdown-content menu bg-base-100 rounded-box border border-base-content/10 shadow-lg z-50 p-1 w-48 text-xs"
      >
        <li>
          <button
            phx-click={JS.dispatch("dm:reload-check", to: "#dm-reload-confirm-modal")}
            class="flex items-center gap-2 px-3 py-2 w-full text-left hover:bg-base-content/5 rounded"
          >
            <.icon name="hero-arrow-path" class="w-3.5 h-3.5" /> Reload
          </button>
        </li>
        <li>
          <button
            phx-click="export_markdown"
            class="flex items-center gap-2 px-3 py-2 w-full text-left hover:bg-base-content/5 rounded"
          >
            <.icon name="hero-clipboard-document" class="w-3.5 h-3.5" /> Export as Markdown
          </button>
        </li>
        <li><div class="divider my-0"></div></li>
        <li>
          <button
            phx-click="open_schedule_timer"
            class="flex items-center gap-2 px-3 py-2 w-full text-left hover:bg-base-content/5 rounded"
          >
            <.icon name="hero-clock" class="w-3.5 h-3.5" /> Schedule Message
          </button>
        </li>
        <%= if @dm_active_timer do %>
          <li>
            <button
              phx-click="cancel_timer"
              class="flex items-center gap-2 px-3 py-2 w-full text-left hover:bg-error/10 text-error rounded"
            >
              <.icon name="hero-x-circle" class="w-3.5 h-3.5" /> Cancel Schedule
            </button>
          </li>
        <% end %>
      </ul>
    </div>
    """
  end
end
