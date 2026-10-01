defmodule EyeInTheSkyWeb.Components.Rail.Flyout.ChatSection do
  @moduledoc false
  use EyeInTheSkyWeb, :html

  attr :channels, :list, default: []
  attr :active_channel_id, :any, default: nil
  attr :unread_counts, :map, default: %{}

  def chat_content(assigns) do
    ~H"""
    <%= for channel <- @channels do %>
      <% active =
        not is_nil(@active_channel_id) && to_string(@active_channel_id) == to_string(channel.id) %>
      <% unread = Map.get(@unread_counts, channel.id, 0) %>
      <div
        class="group flex h-8 items-center gap-2 rounded-box px-3 text-mini transition-colors hover:bg-base-content/5"
        data-ctx="channel"
        data-ctx-id={channel.id}
        data-ctx-name={channel.name}
      >
        <.link
          navigate={"/chat?channel_id=#{channel.id}"}
          data-vim-flyout-item
          class={[
            "focus-ring flex flex-1 items-center gap-2 rounded-box",
            if(active,
              do: "text-primary font-medium",
              else: "text-base-content/60 hover:text-base-content/85"
            )
          ]}
        >
          <span class={[
            "text-mini flex-shrink-0",
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
          type="button"
          phx-click="delete_channel"
          phx-value-channel_id={channel.id}
          title="Delete channel"
          data-confirm={"Delete ##{channel.name}?"}
          class="focus-ring flex size-5 flex-shrink-0 items-center justify-center rounded-box text-base-content/35 opacity-0 transition-all hover:bg-base-content/8 hover:text-base-content/70 group-hover:opacity-100"
        >
          <.icon name="hero-x-mark-mini" class="size-3.5" />
        </button>
      </div>
    <% end %>
    <%= if @channels == [] do %>
      <div class="px-3 py-4 text-mini text-base-content/35 text-center">No channels</div>
    <% end %>
    """
  end
end
