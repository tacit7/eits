defmodule EyeInTheSkyWeb.Components.DmPage.ActionMenu do
  @moduledoc false

  use EyeInTheSkyWeb, :html

  attr :wrapper_id, :string, default: nil
  attr :button_class, :string, required: true
  attr :show_tabs, :boolean, default: false
  attr :tabs, :list, default: []
  attr :active_tab, :string, default: nil
  attr :reload_label, :string, default: "Reload"
  attr :show_jsonl_export, :boolean, default: false
  attr :show_push_setup, :boolean, default: false
  attr :show_iterm, :boolean, default: false
  attr :active_timer, :any, default: nil
  attr :schedule_btn_id, :string, default: nil
  attr :cancel_btn_id, :string, required: true

  def action_menu(assigns) do
    ~H"""
    <div class="dropdown dropdown-end" id={@wrapper_id}>
      <button
        tabindex="0"
        class={@button_class}
        aria-label="More options"
      >
        <.icon name="hero-ellipsis-horizontal" class="w-5 h-5" />
      </button>
      <ul
        tabindex="0"
        class="dropdown-content menu bg-base-100 rounded-box border border-base-content/10 shadow-lg z-50 p-1 w-52 text-xs"
      >
        <%= if @show_tabs do %>
          <%= for {tab, icon, label} <- @tabs do %>
            <li>
              <button
                phx-click="change_tab"
                phx-value-tab={tab}
                class={[
                  "flex items-center gap-2 px-3 py-2 w-full text-left rounded",
                  @active_tab == tab && "text-primary bg-primary/10",
                  @active_tab != tab && "hover:bg-base-content/5"
                ]}
              >
                <.icon name={icon} class="w-3.5 h-3.5" /> {label}
              </button>
            </li>
          <% end %>
          <li><hr class="border-base-content/10 my-1" /></li>
        <% end %>
        <li>
          <button
            phx-click={JS.dispatch("dm:reload-check", to: "#dm-reload-confirm-modal")}
            class="flex items-center gap-2 px-3 py-2 w-full text-left hover:bg-base-content/5 rounded"
          >
            <.icon name="hero-arrow-path" class="w-3.5 h-3.5" /> {@reload_label}
          </button>
        </li>
        <%= if @show_jsonl_export do %>
          <li>
            <button
              phx-click="export_jsonl"
              class="flex items-center gap-2 px-3 py-2 w-full text-left hover:bg-base-content/5 rounded"
            >
              <.icon name="hero-clipboard-document" class="w-3.5 h-3.5" /> Export as JSONL
            </button>
          </li>
        <% end %>
        <li>
          <button
            phx-click="export_markdown"
            class="flex items-center gap-2 px-3 py-2 w-full text-left hover:bg-base-content/5 rounded"
          >
            <.icon name="hero-clipboard-document" class="w-3.5 h-3.5" /> Export as Markdown
          </button>
        </li>
        <%= if @show_push_setup do %>
          <li>
            <button
              id="dm-push-setup-btn"
              phx-hook="PushSetup"
              phx-update="ignore"
              data-push-state="disabled"
              title="Enable push notifications"
              class="flex items-center gap-2 px-3 py-2 w-full text-left hover:bg-base-content/5 rounded"
            >
              <.icon name="hero-bell" class="w-3.5 h-3.5" /> Notify
            </button>
          </li>
        <% end %>
        <%= if @show_iterm do %>
          <li>
            <button
              phx-click="open_iterm"
              class="flex items-center gap-2 px-3 py-2 w-full text-left hover:bg-base-content/5 rounded"
            >
              <.icon name="hero-command-line" class="w-3.5 h-3.5" /> Open in iTerm
            </button>
          </li>
        <% end %>
        <li><hr class="border-base-content/10 my-1" /></li>
        <li>
          <button
            id={@schedule_btn_id}
            phx-click="open_schedule_timer"
            class="flex items-center gap-2 px-3 py-2 w-full text-left hover:bg-base-content/5 rounded"
          >
            <.icon name="hero-clock" class="w-3.5 h-3.5" /> Schedule Message
          </button>
        </li>
        <%= if @active_timer do %>
          <li>
            <button
              id={@cancel_btn_id}
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
