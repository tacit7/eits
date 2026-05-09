defmodule EyeInTheSkyWeb.Components.Rail.Flyout.ChatSection do
  @moduledoc false
  use EyeInTheSkyWeb, :html

  attr :channels, :list, default: []
  attr :active_channel_id, :any, default: nil
  attr :unread_counts, :map, default: %{}
  attr :myself, :any, required: true

  def chat_content(assigns) do
    ~H"""
    <%= for channel <- @channels do %>
      <% active =
        not is_nil(@active_channel_id) && to_string(@active_channel_id) == to_string(channel.id) %>
      <% unread = Map.get(@unread_counts, channel.id, 0) %>
      <div class="group flex items-center gap-2 px-3 py-2 text-sm transition-colors hover:bg-base-content/5">
        <.link
          navigate={"/chat?channel_id=#{channel.id}"}
          data-vim-flyout-item
          class={[
            "flex items-center gap-2 flex-1",
            if(active,
              do: "text-primary font-medium",
              else: "text-base-content/60 hover:text-base-content/85"
            )
          ]}
        >
          <span class={[
            "text-[13px] flex-shrink-0",
            if(active, do: "text-primary/60", else: "text-base-content/25")
          ]}>
            #
          </span>
          <span class={[
            "truncate flex-1",
            if(unread > 0 && !active, do: "font-semibold text-base-content/85")
          ]}>
            {channel.name}
          </span>
          <%= if unread > 0 && !active do %>
            <span class="flex-shrink-0 w-1.5 h-1.5 rounded-full bg-primary"></span>
          <% end %>
        </.link>
        <button
          phx-click="delete_channel"
          phx-value-channel_id={channel.id}
          phx-target={@myself}
          title="Delete channel"
          class="opacity-0 group-hover:opacity-100 flex items-center justify-center text-base-content/35 hover:text-base-content/70 transition-all flex-shrink-0 size-5"
          onclick="confirm('Delete this channel?') || event.stopImmediatePropagation()"
        >
          <.icon name="hero-x-mark-mini" class="size-3.5" />
        </button>
      </div>
    <% end %>
    <%= if @channels == [] do %>
      <div class="px-3 py-4 text-xs text-base-content/35 text-center">No channels</div>
    <% end %>
    """
  end
end
