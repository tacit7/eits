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

  attr :active_tab, :string, default: "messages"
  attr :search_query, :string, default: nil
  attr :active_timer, :map, default: nil
  attr :session_uuid, :string, default: nil
  attr :show_iterm, :boolean, default: false
  attr :notify_on_stop, :boolean, default: false

  def toolbar(assigns) do
    ~H"""
    <%!-- DM: search always visible on messages tab --%>
    <%= if @active_tab in ["messages", nil] do %>
      <.search_bar
        id="top-bar-dm-search"
        size="xs"
        label="Search messages"
        placeholder="Search messages..."
        value={@search_query || ""}
        on_change="search_messages"
        on_submit="search_messages"
        class="w-48"
      />
    <% end %>
    <.tab_pills value_key="tab">
      <:item
        label="Messages"
        active={@active_tab in ["messages", nil]}
        on_click="change_tab"
        value="messages"
        active_class="bg-base-content/[0.10] rounded-md px-3 py-1 text-base-content/92 font-medium"
      />
      <:item label="Tasks" active={@active_tab == "tasks"} on_click="change_tab" value="tasks" active_class="bg-base-content/[0.10] rounded-md px-3 py-1 text-base-content/92 font-medium" />
      <:item label="Commits" active={@active_tab == "commits"} on_click="change_tab" value="commits" active_class="bg-base-content/[0.10] rounded-md px-3 py-1 text-base-content/92 font-medium" />
      <:item label="Notes" active={@active_tab == "notes"} on_click="change_tab" value="notes" active_class="bg-base-content/[0.10] rounded-md px-3 py-1 text-base-content/92 font-medium" />
      <:item label="Context" active={@active_tab == "context"} on_click="change_tab" value="context" active_class="bg-base-content/[0.10] rounded-md px-3 py-1 text-base-content/92 font-medium" />
      <:item
        label="Settings"
        active={@active_tab == "settings"}
        on_click="change_tab"
        value="settings"
        active_class="bg-base-content/[0.10] rounded-md px-3 py-1 text-base-content/92 font-medium"
      />
    </.tab_pills>
    <div class="flex-1" />
    <%!-- ... menu --%>
    <div class="dropdown dropdown-end">
      <button
        tabindex="0"
        class="btn btn-ghost btn-square w-7 h-7 text-base-content/50 hover:text-base-content/75"
        aria-label="More options"
      >
        <.icon name="hero-ellipsis-horizontal" class="size-4" />
      </button>
      <ul
        tabindex="0"
        class="dropdown-content menu bg-base-100 rounded-box border border-base-content/10 shadow-lg z-50 p-1 w-48 text-xs"
      >
        <%= if @session_uuid do %>
          <li>
            <button
              id="top-bar-copy-uuid"
              phx-hook="CopyToClipboard"
              data-copy={@session_uuid}
              class="flex items-center gap-2 px-3 py-2 w-full text-left hover:bg-base-content/5 rounded font-mono text-mini"
            >
              <.icon name="hero-clipboard-document" class="size-3.5 flex-shrink-0" />
              Copy {String.slice(@session_uuid, 0..7)}…
            </button>
          </li>
        <% end %>
        <%= if @show_iterm do %>
          <li>
            <button
              phx-click="open_iterm"
              class="flex items-center gap-2 px-3 py-2 w-full text-left hover:bg-base-content/5 rounded"
            >
              <.icon name="hero-command-line" class="size-3.5" /> Open in iTerm
            </button>
          </li>
        <% end %>
        <%= if @session_uuid || @show_iterm do %>
          <li>
            <div class="divider my-0"></div>
          </li>
        <% end %>
        <li>
          <button
            phx-click={JS.dispatch("dm:reload-check", to: "#dm-reload-confirm-modal")}
            class="flex items-center gap-2 px-3 py-2 w-full text-left hover:bg-base-content/5 rounded"
          >
            <.icon name="hero-arrow-path" class="size-3.5" /> Reload
          </button>
        </li>
        <li>
          <button
            phx-click="export_markdown"
            class="flex items-center gap-2 px-3 py-2 w-full text-left hover:bg-base-content/5 rounded"
          >
            <.icon name="hero-clipboard-document" class="size-3.5" /> Export as Markdown
          </button>
        </li>
        <li>
          <div class="divider my-0"></div>
        </li>
        <li>
          <button
            id="topbar-push-setup-btn"
            phx-hook="PushSetup"
            phx-update="ignore"
            data-push-state="disabled"
            data-notify-on-stop={if @notify_on_stop, do: "true", else: "false"}
            title="Enable notifications"
            class="flex items-center gap-2 px-3 py-2 w-full text-left hover:bg-base-content/5 rounded"
          >
            <.icon name="hero-bell" class="size-3.5" /> Notify
          </button>
        </li>
        <li>
          <div class="divider my-0"></div>
        </li>
        <li>
          <button
            phx-click="open_schedule_timer"
            class="flex items-center gap-2 px-3 py-2 w-full text-left hover:bg-base-content/5 rounded"
          >
            <.icon name="hero-clock" class="size-3.5" /> Schedule Message
          </button>
        </li>
        <%= if @active_timer do %>
          <li>
            <button
              phx-click="cancel_timer"
              class="flex items-center gap-2 px-3 py-2 w-full text-left hover:bg-error/10 text-error rounded"
            >
              <.icon name="hero-x-circle" class="size-3.5" /> Cancel Schedule
            </button>
          </li>
        <% end %>
      </ul>
    </div>
    """
  end
end
