defmodule EyeInTheSkyWeb.Components.Sidebar.ChatSection do
  @moduledoc false
  use EyeInTheSkyWeb, :html

  attr :sidebar_tab, :atom, required: true
  attr :collapsed, :boolean, required: true

  def chat_section(assigns) do
    ~H"""
    <.link
      navigate={~p"/chat"}
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
      <.icon name="hero-chat-bubble-left-ellipsis" class="size-4 flex-shrink-0" />
      <span class={["truncate font-medium", if(@collapsed, do: "hidden")]}>Chat</span>
      <%= if @sidebar_tab == :chat && !@collapsed do %>
        <span class="ml-auto w-1.5 h-1.5 rounded-full bg-primary flex-shrink-0"></span>
      <% end %>
    </.link>
    """
  end
end
