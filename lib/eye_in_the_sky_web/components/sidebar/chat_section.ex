defmodule EyeInTheSkyWeb.Components.Sidebar.ChatSection do
  @moduledoc false
  use EyeInTheSkyWeb, :html

  attr :sidebar_tab, :atom, required: true
  attr :collapsed, :boolean, required: true
  attr :expanded_chat, :boolean, required: true
  attr :channels, :list, required: true
  attr :active_channel_id, :any, default: nil
  attr :new_channel_name, :any, default: nil
  attr :myself, :any, required: true

  def chat_section(assigns) do
    ~H"""
    <button
      phx-click="toggle_chat"
      phx-target={@myself}
      class={[
        "flex items-center gap-2.5 w-full text-left text-sm transition-colors min-h-[44px]",
        if(@collapsed, do: "px-4 py-1 justify-center", else: "px-3 py-1"),
        if(@sidebar_tab == :chat,
          do: "text-base-content/80 hover:bg-base-content/5",
          else: "text-base-content/55 hover:text-base-content/80 hover:bg-base-content/5"
        )
      ]}
      title="Chat"
    >
      <%= if !@collapsed do %>
        <.icon
          name={if @expanded_chat, do: "hero-chevron-down-mini", else: "hero-chevron-right-mini"}
          class="w-3.5 h-3.5 flex-shrink-0"
        />
      <% end %>
      <.icon name="hero-chat-bubble-left-ellipsis" class="w-4 h-4 flex-shrink-0" />
      <span class={["truncate font-medium", if(@collapsed, do: "hidden")]}>Chat</span>
      <%= if @sidebar_tab == :chat && !@collapsed do %>
        <span class="ml-auto w-1.5 h-1.5 rounded-full bg-primary flex-shrink-0"></span>
      <% end %>
    </button>

    <%= if @expanded_chat && !@collapsed do %>
      <div class="ml-5 border-l border-base-content/8">
        <%= for channel <- @channels do %>
          <.link
            navigate={~p"/chat?channel_id=#{channel.id}"}
            class={[
              "flex items-center pl-3 pr-3 py-0.5 min-h-[44px] text-sm transition-colors",
              if(@active_channel_id && to_string(@active_channel_id) == to_string(channel.id),
                do: "text-primary font-medium bg-primary/5",
                else: "text-base-content/50 hover:text-base-content/75 hover:bg-base-content/5"
              )
            ]}
          >
            <span class="text-base-content/30 mr-0.5">#</span>{channel.name}
          </.link>
        <% end %>

        <%!-- New channel inline form or button --%>
        <%= if @new_channel_name do %>
          <form
            phx-submit="create_channel"
            phx-target={@myself}
            class="flex items-center gap-1 pl-3 pr-2 py-1"
          >
            <input
              type="text"
              name="name"
              value={@new_channel_name}
              phx-keyup="update_channel_name"
              phx-target={@myself}
              placeholder="channel-name"
              class="flex-1 bg-transparent border-b border-base-content/15 text-xs text-base-content/70 placeholder:text-base-content/25 outline-none py-0.5 font-mono"
              autofocus
            />
          </form>
        <% else %>
          <button
            phx-click="show_new_channel"
            phx-target={@myself}
            class="flex items-center pl-3 pr-3 py-0.5 min-h-[44px] text-sm text-base-content/30 hover:text-base-content/55 transition-colors w-full text-left"
          >
            + New Channel
          </button>
        <% end %>
      </div>
    <% end %>
    """
  end
end
