defmodule EyeInTheSkyWeb.Components.Rail.Flyout.CanvasSection do
  @moduledoc false
  use EyeInTheSkyWeb, :html

  alias EyeInTheSkyWeb.Components.DmHelpers

  attr :canvases, :list, default: []

  def canvas_content(assigns) do
    ~H"""
    <div class="px-3 pb-1">
      <.link
        navigate="/canvases"
        class="text-xs text-base-content/40 hover:text-base-content/70 transition-colors"
      >
        All Canvases &rarr;
      </.link>
    </div>
    <%= if @canvases == [] do %>
      <div class="px-3 py-4 text-xs text-base-content/35 text-center">No canvases</div>
    <% end %>
    <%= for canvas <- @canvases do %>
      <.link
        navigate={"/canvases/#{canvas.id}"}
        data-vim-flyout-item
        class="flex items-center gap-2 px-3 py-1.5 text-sm text-base-content/70 hover:text-base-content/90 hover:bg-base-content/5 transition-colors [&.vim-nav-focused]:ring-2 [&.vim-nav-focused]:ring-primary/50 [&.vim-nav-focused]:rounded"
      >
        <.icon name="hero-squares-2x2" class="size-3 flex-shrink-0 text-base-content/30" />
        <span class="truncate font-medium text-xs">{canvas.name}</span>
      </.link>
      <%= for session <- canvas.sessions do %>
        <div class="flex items-center hover:bg-base-content/5 transition-colors group">
          <.link
            navigate={"/canvases/#{canvas.id}?focus=#{session.id}"}
            class="flex items-center gap-2 pl-7 py-1 flex-1 min-w-0 text-xs text-base-content/50 group-hover:text-base-content/80"
          >
            <span class={[
              "w-1.5 h-1.5 rounded-full flex-shrink-0",
              canvas_session_dot(session.status)
            ]} />
            <span class="truncate">{session.name || "unnamed"}</span>
          </.link>
          <.link
            navigate={"/dm/#{session.id}"}
            class={[
              "flex-shrink-0 px-3 py-1 transition-opacity hover:opacity-80",
              if(session.status == "working", do: "opacity-80", else: "opacity-30")
            ]}
            title="Open DM"
          >
            <img
              src={DmHelpers.provider_icon(session.provider)}
              class={[
                "size-3.5",
                DmHelpers.provider_icon_class(session.provider),
                session.status == "working" && "animate-pulse"
              ]}
              alt={session.provider || "agent"}
            />
          </.link>
        </div>
      <% end %>
      <%= if canvas.sessions == [] do %>
        <div class="pl-7 pr-3 py-1 text-micro text-base-content/30">no sessions</div>
      <% end %>
    <% end %>
    """
  end

  def canvas_session_dot("working"), do: "bg-success"
  def canvas_session_dot("waiting"), do: "bg-warning"
  def canvas_session_dot(_), do: "bg-base-content/20"
end
