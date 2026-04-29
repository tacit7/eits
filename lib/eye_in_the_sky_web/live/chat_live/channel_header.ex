defmodule EyeInTheSkyWeb.ChatLive.ChannelHeader do
  @moduledoc false

  use EyeInTheSkyWeb, :html

  attr :active_channel, :map, default: nil

  def channel_header(assigns) do
    ~H"""
    <div
      class="w-full bg-base-100 border-b border-base-content/[0.12] flex-shrink-0"
      id="chat-header-card"
    >
      <div class="px-5 py-5">
        <div class="flex flex-col gap-1">
          <h1 class="text-xl font-bold tracking-tight text-base-content leading-tight">
            <%= if @active_channel do %>
              <span class="text-primary/50 mr-0.5 font-semibold">#</span>{@active_channel.name || "Channel"}
            <% else %>
              Chat
            <% end %>
          </h1>
          <%= if not is_nil(@active_channel) && not is_nil(@active_channel[:description]) do %>
            <span class="text-xs text-base-content/50 leading-tight">{@active_channel.description}</span>
          <% end %>
        </div>
      </div>
    </div>
    """
  end
end
